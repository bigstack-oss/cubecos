#!/bin/bash
#
# Unit test for the git sync in ../modules/sdk_git.sh.
# The rootfs is a git worktree of the image commit. Neither _git_client_init nor
# git_push may rewrite the working tree (no stash/pull/checkout) or touch peers;
# git_push records this node's changes on its own branch.
#
# Self-contained: extracts just these functions and mocks the git/Quiet/cmd
# layers, so it needs no cluster, no cephfs and no repo.  Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_git.sh"

for fn in _git_identity _git_firmware_branch _git_server_init _git_client_init git_push ; do
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
        diff--cached) [ -n "${CLEAN:-}" ] ; return ;;
        check-ref-format--branch) command git "$@" ; return ;;
        rev-parse-q) [ -z "${NOHEAD:-}" ] ; return ;;
    esac
    return 0
}
git(){ _gitmock "$@" ; }
Quiet(){ [ "${1:-}" = "-n" ] && shift ; "$@" ; }
cmd(){ echo "cmd $*" >> "$LOG" ; }
Error(){ echo "Error $*" >> "$LOG" ; return 1 ; }
log_info(){ echo "info $*" >> "$LOG" ; }
pushd(){ : ; } ; popd(){ : ; }
git_ignore_file(){ : ; }
cubectl(){ echo '[]' ; }
jq(){ echo "10.0.0.1" ; }
HEX_SDK=_hexsdkmock
_hexsdkmock(){ return 0 ; }              # cube_node_ready -> ready
CEPHFS_BACKUP_DIR=$(mktemp -d)
CEPHFS_STORE_DIR=$CEPHFS_BACKUP_DIR
HOSTNAME=testnode

# the production code must not hard-code this path, so a test can point it
# somewhere writable
CUBE_GITIGNORE=$(mktemp) ; : > "$CUBE_GITIGNORE"
CUBE_GIT_WORKTREE=$(mktemp -d)
CUBE_GIT_ROOT_CONFIG=/nonexistent
CUBE_VERSION_FILE=$(mktemp)
FW=CUBE_3.2.0_20261116-0411_bb180a14
printf '%s\n' "$FW" > "$CUBE_VERSION_FILE"
mountpoint(){ return 0 ; }
hex_cli(){ : ; }

# 1. client init: adopt history, keep the working tree
: > "$LOG"
_git_client_init
chk "1 tracks its firmware branch" "$(saw "git branch --track $FW cube/$FW$")" "y"
chk "1 never master"            "$(saw 'master')"             "n"
chk "1 mixed reset"             "$(saw 'git reset -q$')"      "y"
chk "1 does NOT stage all"      "$(saw 'git add -A')"         "n"
chk "1 does NOT stash"          "$(saw 'git stash')"          "n"
chk "1 does NOT pull"           "$(saw 'git pull')"           "n"
chk "1 no hard reset"           "$(saw 'reset.*--hard')"      "n"

# 2. git_push: commits tracked changes to this node's own branch, never tells
#    peers anything
: > "$LOG"
git_push "a message"
chk "2 stages tracked only" "$(saw 'git add -u')"                          "y"
chk "2 commits"             "$(saw 'git commit')"                          "y"
chk "2 pushes own branch"   "$(saw 'git push -q cube +HEAD:refs/heads/nodes/testnode')" "y"
chk "2 no stash"            "$(saw 'stash')"                               "n"
chk "2 no pull"             "$(saw 'pull')"                                "n"
chk "2 no peer fan-out"     "$(saw '^cmd ')"                               "n"

# 3. git_push with nothing staged: records nothing
: > "$LOG" ; CLEAN=1
git_push "a message"
chk "3 does NOT commit"     "$(saw 'git commit')"  "n"
chk "3 says so"             "$(saw 'info ')"       "y"
CLEAN=

# 4. server init: publishes this firmware's tree on that firmware's branch, never on master
: > "$LOG"
_git_server_init
chk "4 bare repo on its firmware" "$(saw "git init --bare -b $FW$")"                     "y"
chk "4 pushes HEAD to it"         "$(saw "git push --set-upstream cube HEAD:$FW$")"      "y"
chk "4 never master"              "$(saw 'master')"                                      "n"

# 5. no firmware version: neither side creates any git state
#    (the only git before it: the client's "already has history" probe, and the name check)
others(){ grep '^git ' "$LOG" | grep -v -e '^git log -1$' -e 'check-ref-format' | wc -l | tr -d ' ' ; }
: > "$CUBE_VERSION_FILE"
for fn in _git_server_init _git_client_init ; do
    : > "$LOG"
    $fn ; rc=$?
    chk "5 $fn fails"        "$rc"                 "1"
    chk "5 $fn says why"     "$(saw '^Error git: no valid firmware version')" "y"
    chk "5 $fn runs no git"  "$(others)"           "0"
done

# 6. a version that is not a valid branch name: same
printf 'bad name~1\n' > "$CUBE_VERSION_FILE"
: > "$LOG"
_git_client_init ; rc=$?
chk "6 invalid name fails"   "$rc"                 "1"
chk "6 says why"             "$(saw '^Error git: no valid firmware version')" "y"
chk "6 runs no git"           "$(others)"           "0"
printf '%s\n' "$FW" > "$CUBE_VERSION_FILE"

# 7. git_push on a node with no history: says so instead of "nothing to record"
#    (no HEAD and nothing tracked: the index is empty, so `diff --cached` sees no change)
: > "$LOG" ; NOHEAD=1 ; CLEAN=1
git_push "a message" ; rc=$?
chk "7 fails"                "$rc"                 "1"
chk "7 says why"             "$(saw '^Error git: no history')" "y"
chk "7 does NOT stage"       "$(saw 'git add')"    "n"
chk "7 does NOT commit"      "$(saw 'git commit')" "n"
chk "7 does NOT push"        "$(saw 'git push')"   "n"
chk "7 not 'nothing to record'" "$(saw 'info ')"   "n"
NOHEAD= ; CLEAN=

rm -rf "$LOG" "$CUBE_GITIGNORE" "$CEPHFS_BACKUP_DIR" "$CUBE_GIT_WORKTREE" "$CUBE_VERSION_FILE" 2>/dev/null
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: git sync" ; exit 0 ; } || exit 1
