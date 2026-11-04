#!/bin/sh
# Run on a node before the kernel fixpack changes anything. Ships inside the fixpack.
#
#   fixpack-git-check.sh [<expected HEAD>]
#
# The fixpack records its change in the node's rootfs git; on 3.0.0-3.1.20 that git push is also
# what carries usr/lib/modules and usr/lib/firmware to the other nodes. Repairs what can be
# repaired, refuses the rest with one line per problem, and exits 1 if anything is refused:
#   - the commit identity: older firmware keeps it only in /root/.gitconfig, which an admin login
#     never reads (HOME=/tmp), so the commit failed with "unable to auto-detect email address".
#     It is copied into the repository's own config, where every login finds it;
#   - /.git/index.lock: another git is running, or a killed one left it;
#   - tracked files with changes not recorded yet: they would go into this fixpack's commit (or,
#     on 3.0.0-3.1.20, be discarded by a peer's next stash). Deletions alone are allowed: a node
#     that lacks a role's files always shows them as deleted;
#   - with <expected HEAD>: a node on another commit cannot pull this fixpack cleanly.
# A node without /.git (git never set up) passes: there is nothing to record.

cd / || exit 1
[ -d .git ] || exit 0
host=$(hostname)
r=0

if [ -e .git/index.lock ] ; then
    if pgrep -x git >/dev/null 2>&1 ; then
        echo "$host: a git command is running; retry when it is done"
    else
        echo "$host: /.git/index.lock was left by a killed git; remove it and retry"
    fi
    exit 1
fi

email=$(git config --local user.email 2>/dev/null)
[ -n "$email" ] || email=$(git config --file /root/.gitconfig user.email 2>/dev/null)
if [ -z "$email" ] ; then
    ip=$(hostname -i 2>/dev/null | awk '{print $1}')
    [ -n "$ip" ] && [ "$ip" != 127.0.0.1 ] && email="$host@$ip"
fi
if [ -z "$email" ] ; then
    echo "$host: no git commit identity, and none can be derived; set it: git -C / config user.email $host@<management ip>"
    r=1
else
    git config --local user.email "$email" &&
    { git config --local user.name >/dev/null 2>&1 || git config --local user.name root ; } &&
    git var GIT_COMMITTER_IDENT >/dev/null 2>&1 ||
    { echo "$host: cannot set the git commit identity"; r=1 ; }
fi

changed=$(git status --porcelain -uno 2>/dev/null | grep -v -E '^ ?D ' | awk '{print $2}' | head -5 | tr '\n' ' ')
if [ -n "$changed" ] ; then
    echo "$host: tracked files changed but not recorded: $changed- record them (hex_sdk git_push '<why>') or revert them first"
    r=1
fi

if [ -n "${1:-}" ] && [ "$(git rev-parse HEAD 2>/dev/null)" != "$1" ] ; then
    echo "$host: on commit $(git rev-parse --short HEAD 2>/dev/null), not $(echo $1 | cut -c1-7); bring it in line (git pull) first"
    r=1
fi

[ $r -ne 0 ] || echo "$host: ready ($(git config --local user.email))"
exit $r
