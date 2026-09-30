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
        diff--cached) [ -n "${CLEAN:-}" ] ; return ;;
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
HOSTNAME=testnode

# the production code must not hard-code this path, so a test can point it
# somewhere writable
CUBE_GITIGNORE=$(mktemp) ; : > "$CUBE_GITIGNORE"

# 1. client init: adopt history, keep the working tree
: > "$LOG"
_git_client_init
chk "1 tracks the image branch" "$(saw 'git branch --track')" "y"
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

rm -rf "$LOG" "$CUBE_GITIGNORE" "$CEPHFS_BACKUP_DIR" 2>/dev/null
echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: git sync" ; exit 0 ; } || exit 1
