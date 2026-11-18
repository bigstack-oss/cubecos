#!/bin/bash
#
# Unit test for the shared repo's branch in ../modules/sdk_git.sh.
# Server and client init use the firmware the node runs as the branch, never
# master: an older peer stashes its / onto cube/master, so a release published
# there during a rolling update would replace that peer's rootfs.
#
# Self-contained: extracts just these functions and mocks the git/Quiet/cmd
# layers, so it needs no cluster, no cephfs and no repo.  Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_git.sh"

for fn in _git_firmware_branch _git_server_init _git_client_init ; do
    body="$(awk -v f="^${fn}\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$SRC")"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done

LOG=$(mktemp)
pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
saw(){ grep -qe "$1" "$LOG" && echo y || echo n; }

# --- mocks: record what the git layer is asked to do; succeed at everything.
# `git log -1` must fail: that is the "no commit yet, needs init" precondition.
GIT=_gitmock
_gitmock(){
    echo "git $*" >> "$LOG"
    case "${1:-}${2:-}" in
        log*|-Plog) return 1 ;;
        check-ref-format--branch) command git "$@" ; return ;;
        symbolic-ref-q) echo "${LOCAL_BRANCH:-$FW}" ; return 0 ;;
    esac
    return 0
}
git(){ _gitmock "$@" ; }
Quiet(){ [ "${1:-}" = "-n" ] && shift ; "$@" ; }
cmd(){ echo "cmd $*" >> "$LOG" ; }
Error(){ echo "Error $*" >> "$LOG" ; return 1 ; }
log_warning(){ echo "warn $*" >> "$LOG" ; }
pushd(){ : ; } ; popd(){ : ; }
git_ignore_file(){ : ; }
_git_suid_save(){ : ; } ; _git_suid_restore(){ : ; }
cubectl(){ echo '[]' ; }
jq(){ echo "10.0.0.1" ; }
mountpoint(){ return 0 ; }
hex_cli(){ : ; }
HEX_SDK=_hexsdkmock
_hexsdkmock(){ return 0 ; }              # cube_node_ready -> ready
CEPHFS_BACKUP_DIR=$(mktemp -d)
CEPHFS_STORE_DIR=$CEPHFS_BACKUP_DIR
HOSTNAME=testnode

CUBE_GITIGNORE=$(mktemp) ; : > "$CUBE_GITIGNORE"
CUBE_GIT_OPTOUT=$(mktemp -u)
CUBE_VERSION_FILE=$(mktemp)
FW=CUBE_3.1.20_20261014-0841_7462e394
printf '%s\n' "$FW" > "$CUBE_VERSION_FILE"

# 1. server init: publishes this firmware's tree on that firmware's branch, never on master
: > "$LOG"
_git_server_init
chk "1 bare repo on its firmware" "$(saw "git init --bare -b $FW$")"                "y"
chk "1 / on its firmware"         "$(saw "^git init -b $FW$")"                      "y"
chk "1 pushes HEAD to it"         "$(saw "git push --set-upstream cube HEAD:$FW$")" "y"
chk "1 never master"              "$(saw 'master')"                                 "n"

# 1b. a / that already has history on master (sdk_git.sh replaced without a firmware install):
#     publish the firmware branch too, but keep master's upstream, or git_push's plain
#     `git push` is refused for an upstream of another name
: > "$LOG" ; LOCAL_BRANCH=master
_git_server_init
chk "1b pushes HEAD to its firmware" "$(saw "git push cube HEAD:$FW$")"  "y"
chk "1b keeps the upstream"          "$(saw 'set-upstream')"             "n"
LOCAL_BRANCH=

# 2. client init: tracks and pulls its own firmware's branch, never master
: > "$LOG"
_git_client_init
chk "2 / on its firmware"          "$(saw "git init -b $FW$")"               "y"
chk "2 tracks its firmware branch" "$(saw "git branch --track $FW cube/$FW$")" "y"
chk "2 pulls its firmware branch"  "$(saw "git pull cube $FW --rebase$")"    "y"
chk "2 never master"               "$(saw 'master')"                         "n"

# 3. no firmware version: neither side creates any git state
#    (the only git before it: the client's "already has history" probe, and the name check)
others(){ grep '^git ' "$LOG" | grep -v -e '^git log -1$' -e 'check-ref-format' | wc -l | tr -d ' ' ; }
: > "$CUBE_VERSION_FILE"
for fn in _git_server_init _git_client_init ; do
    : > "$LOG"
    $fn ; rc=$?
    chk "3 $fn fails"        "$rc"       "1"
    chk "3 $fn says why"     "$(saw '^Error git: no valid firmware version')" "y"
    chk "3 $fn runs no git"  "$(others)" "0"
done

# 4. a version that is not a valid branch name: same
printf 'bad name~1\n' > "$CUBE_VERSION_FILE"
: > "$LOG"
_git_client_init ; rc=$?
chk "4 invalid name fails"   "$rc"       "1"
chk "4 says why"             "$(saw '^Error git: no valid firmware version')" "y"
chk "4 runs no git"          "$(others)" "0"

rm -rf "$LOG" "$CUBE_GITIGNORE" "$CEPHFS_BACKUP_DIR" "$CUBE_VERSION_FILE" 2>/dev/null
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: git firmware branch" ; exit 0 ; } || exit 1
