#!/bin/bash
#
# Unit test, with a real git, for the node's git record that a fixpack install depends on:
# git_push and _git_identity in ../modules/sdk_git.sh, fixpack_precheck in ../../main/proj_functions.
#
# The field failure: hex_cli is setuid root but keeps the caller's HOME, and the admin login's HOME
# is /tmp. The commit identity lived only in /root/.gitconfig, so `git commit` failed with
# "unable to auto-detect email address", the failure went unseen, and the install said successful.
# Here HOME is an empty directory and the identity is only in a stand-in for /root/.gitconfig.
#
# Self-contained: a throwaway worktree and bare remote; no cluster. Run: bash test_...sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for fn in _git_identity git_push ; do
    body="$(awk -v f="^${fn}\\\\(\\\\)" '$0~f{p=1} p{print} p&&/^}/{exit}' "$DIR/../modules/sdk_git.sh")"
    [ -n "$body" ] || { echo "FAIL: $fn not extracted"; exit 1; }
    eval "$body"
done
body="$(awk '/^fixpack_precheck\(\)/{p=1} p{print} p&&/^}/{exit}' "$DIR/../../main/proj_functions")"
[ -n "$body" ] || { echo "FAIL: fixpack_precheck not extracted"; exit 1; }
eval "$body"

pass=0 fail=0
chk(){ if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export HOME=$T/home GIT_CONFIG_NOSYSTEM=1          # the admin login's HOME: no .gitconfig there
mkdir -p "$HOME"
CUBE_GIT_ROOT_CONFIG=$T/root.gitconfig              # stands in for /root/.gitconfig
printf '[user]\n\temail = testnode@10.0.0.1\n' > "$CUBE_GIT_ROOT_CONFIG"
CUBE_GIT_WORKTREE=$T/wt
HOSTNAME=testnode
GIT=git
ERR=$T/err
Error(){ echo "Error $*" >> "$ERR" ; return 1 ; }
log_info(){ : ; }
Quiet(){ [ "${1:-}" = "-n" ] && shift ; "$@" >/dev/null 2>&1 ; }
HEX_SDK=true                                        # _git_client_init: the repo already exists
hex_sdk(){ "$@" ; }                                 # fixpack_precheck calls hex_sdk _git_identity
cubectl(){ echo '[]' ; }
jq(){ echo 10.0.0.1 ; }

# A node's rootfs repo: one tracked file, pushed to the cluster's bare repo as `cube`.
git init -q --bare -b master "$T/cube.git"
git init -q -b master "$CUBE_GIT_WORKTREE"
echo base > "$CUBE_GIT_WORKTREE/placeholder"
git -C "$CUBE_GIT_WORKTREE" add placeholder
git -C "$CUBE_GIT_WORKTREE" -c user.email=image@build -c user.name=build commit -q -m image
git -C "$CUBE_GIT_WORKTREE" remote add cube "$T/cube.git"
change(){ echo "$1" > "$CUBE_GIT_WORKTREE/placeholder" ; }
commits(){ git -C "$CUBE_GIT_WORKTREE" rev-list --count HEAD ; }
pushed(){ git -C "$T/cube.git" rev-parse --verify -q refs/heads/nodes/testnode || echo none ; }

# 0. The field failure, as it was: with this HOME, a plain commit has no identity.
change field
git -C "$CUBE_GIT_WORKTREE" commit -q -am field 2>"$T/out" ; rc=$?
chk "0 plain commit fails with HOME=/tmp-like" "$rc" "128"
chk "0 the same error as the field log" "$(grep -c 'unable to auto-detect email address' "$T/out")" "1"
git -C "$CUBE_GIT_WORKTREE" checkout -q -- placeholder

# 1. The gate passes on a clean node, and sets the identity in the repository's own config.
out=$(fixpack_precheck) ; rc=$?
chk "1 precheck passes on a clean node" "$rc" "0"
chk "1 identity is repo-local" "$(git -C "$CUBE_GIT_WORKTREE" config --local user.email)" "testnode@10.0.0.1"

# 2. git_push records a change under that HOME, and pushes it to this node's branch.
change 2 ; : > "$ERR"
git_push "two" ; rc=$?
chk "2 git_push succeeds" "$rc" "0"
chk "2 committed" "$(commits)" "2"
chk "2 author is the node" "$(git -C "$CUBE_GIT_WORKTREE" log -1 --format=%ae)" "testnode@10.0.0.1"
chk "2 pushed to nodes/testnode" "$(pushed)" "$(git -C "$CUBE_GIT_WORKTREE" rev-parse HEAD)"
chk "2 tree clean after" "$(git -C "$CUBE_GIT_WORKTREE" status --porcelain -uno)" ""

# 3. Nothing changed: no commit, success.
git_push "nothing" ; rc=$?
chk "3 clean push succeeds" "$rc" "0"
chk "3 no new commit" "$(commits)" "2"

# 4. A dirty tree fails the gate and names the file.
change 4
out=$(fixpack_precheck) ; rc=$?
chk "4 precheck refuses a modified tracked file" "$rc" "1"
chk "4 names it" "$(echo "$out" | grep -c 'placeholder')" "1"

# 4b. A deleted tracked file alone (a role's files missing on this node) does not fail the gate.
git -C "$CUBE_GIT_WORKTREE" checkout -q -- placeholder
echo x > "$CUBE_GIT_WORKTREE/control-only" ; git -C "$CUBE_GIT_WORKTREE" add control-only
git -C "$CUBE_GIT_WORKTREE" commit -q -m "base from a control node"
rm "$CUBE_GIT_WORKTREE/control-only"
out=$(fixpack_precheck) ; rc=$?
chk "4b precheck passes with only a deletion" "$rc" "0"
change 4

# 5. A lock left by a killed git fails the gate and git_push, and nothing is committed.
: > "$CUBE_GIT_WORKTREE/.git/index.lock" ; : > "$ERR"
out=$(fixpack_precheck) ; rc=$?
chk "5 precheck refuses a lock" "$rc" "1"
chk "5 says so" "$(echo "$out" | grep -c 'index.lock exists')" "1"
git_push "five" ; rc=$?
chk "5 git_push fails" "$rc" "1"
chk "5 git_push says why" "$(grep -c 'index.lock exists' "$ERR")" "1"
chk "5 nothing committed" "$(commits)" "3"
rm -f "$CUBE_GIT_WORKTREE/.git/index.lock"

# 6. A push that fails is reported, though the commit stays on the node.
git -C "$CUBE_GIT_WORKTREE" remote set-url cube "$T/missing.git" ; : > "$ERR"
git_push "six" ; rc=$?
chk "6 git_push fails" "$rc" "1"
chk "6 says committed but not pushed" "$(grep -c 'committed on the node but not pushed' "$ERR")" "1"
chk "6 the commit is on the node" "$(commits)" "4"

# 6b. Rerunning git_push once the remote is back pushes that commit, with no new commit, even
#     after the master's _git_server_init pushed the same HEAD to master.
git -C "$CUBE_GIT_WORKTREE" remote set-url cube "$T/cube.git" ; : > "$ERR"
git -C "$CUBE_GIT_WORKTREE" push -q cube HEAD:refs/heads/master
git_push "six again" ; rc=$?
chk "6b git_push succeeds" "$rc" "0"
chk "6b no new commit" "$(commits)" "4"
chk "6b pushed to nodes/testnode" "$(pushed)" "$(git -C "$CUBE_GIT_WORKTREE" rev-parse HEAD)"

# 7. No identity anywhere is caught by the gate, before anything changes.
git -C "$CUBE_GIT_WORKTREE" config --local --unset user.email
CUBE_GIT_ROOT_CONFIG=$T/none
cubectl(){ return 1 ; } ; jq(){ return 1 ; } ; HOSTNAME=
git -C "$CUBE_GIT_WORKTREE" checkout -q -- placeholder
out=$(fixpack_precheck) ; rc=$?
chk "7 precheck refuses with no identity" "$rc" "1"
chk "7 says so" "$(echo "$out" | grep -c 'no git commit identity')" "1"

# 8. A node without a repository passes: there is nothing to record.
CUBE_GIT_WORKTREE=$T/norepo ; mkdir -p "$CUBE_GIT_WORKTREE"
out=$(fixpack_precheck) ; rc=$?
chk "8 no repository passes" "$rc" "0"

echo "----" ; echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ] && { echo "OK: git push identity and fixpack precheck" ; exit 0 ; } || exit 1
