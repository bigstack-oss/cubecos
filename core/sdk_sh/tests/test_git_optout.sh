#!/bin/bash
#
# Unit test for the hidden git opt-out in ../modules/sdk_git.sh.
# The rootfs is a git worktree of the image commit, and both _git_client_init
# (first boot after an upgrade) and git_push (cluster-wide fan-out) stash local
# modifications away -- silently reverting any hot-patched tracked file. With
# $CUBE_GIT_OPTOUT present a node must keep its uncommitted changes instead:
# adopt the image history, skip the add/stash/pull trio, and never publish the
# node's local edits to the shared repo.
#
# Self-contained: extracts just these functions and mocks the git/Quiet/cmd
# layers, so it needs no cluster, no cephfs and no repo.  Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_git.sh"

for fn in _git_client_init git_push ; do
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
        -Pstatus) echo "	modified:   usr/sbin/bootstrap" ; return 0 ;;
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
HEX_SDK=_hexsdkmock
_hexsdkmock(){ return 0 ; }              # cube_node_ready -> ready
CEPHFS_BACKUP_DIR=$(mktemp -d)
HOSTNAME=testnode

# the two paths the production code must not hard-code, so a test can point them
# somewhere writable
CUBE_GITIGNORE=$(mktemp) ; : > "$CUBE_GITIGNORE"
OPTOUT=$(mktemp -u)
CUBE_GIT_OPTOUT=$OPTOUT

# 1. client init WITHOUT the marker: the existing destructive path is unchanged
: > "$LOG" ; rm -f "$OPTOUT"
_git_client_init
chk "1 tracks the image branch" "$(saw 'git branch --track')" "y"
chk "1 stages everything"       "$(saw 'git add -A')"         "y"
chk "1 stashes local changes"   "$(saw 'git stash')"          "y"
chk "1 pulls"                   "$(saw 'git pull')"           "y"

# 2. client init WITH the marker: adopt history, keep the working tree
: > "$LOG" ; : > "$OPTOUT"
_git_client_init
chk "2 still tracks the image branch" "$(saw 'git branch --track')" "y"
chk "2 does NOT stage"                "$(saw 'git add -A')"         "n"
chk "2 does NOT stash"                "$(saw 'git stash')"          "n"
chk "2 does NOT pull"                 "$(saw 'git pull')"           "n"
chk "2 warns"                         "$(saw 'warn ')"              "y"

# 3. git_push WITHOUT the marker: commits, pushes, and tells peers to stash+pull
: > "$LOG" ; rm -f "$OPTOUT"
git_push "a message"
chk "3 commits"        "$(saw 'git commit')"  "y"
chk "3 pushes"         "$(saw 'git push')"    "y"
chk "3 peers stash"    "$(saw 'cmd .*stash')" "y"

# 4. git_push WITH the marker: never harvests or publishes this node's edits,
#    and never tells peers to throw theirs away
: > "$LOG" ; : > "$OPTOUT"
git_push "a message"
chk "4 does NOT commit"     "$(saw 'git commit')"  "n"
chk "4 does NOT push"       "$(saw 'git push')"    "n"
chk "4 no peer stash"       "$(saw 'cmd .*stash')" "n"
chk "4 warns"               "$(saw 'warn ')"       "y"

rm -rf "$LOG" "$OPTOUT" "$CUBE_GITIGNORE" "$CEPHFS_BACKUP_DIR" 2>/dev/null
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: git opt-out" ; exit 0 ; } || exit 1
