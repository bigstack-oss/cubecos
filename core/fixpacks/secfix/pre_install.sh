#!/bin/sh
# Kernel security fixpack, pre-install. The fixpack installer sources this with errexit; exit 1
# stops the install before anything changes.
#
# One fixpack for 3.0.0 to 3.2.0+ (SUPPORTED_FIRMWARES), two ways of installing:
#   - 3.2.0 and later: each node installs the fixpack itself, and fixpack_sync records it in
#     that node's git. Only this node is checked.
#   - 3.0.0 to 3.1.20: one node installs for the cluster. Its git push carries usr/lib/modules
#     and usr/lib/firmware to the other nodes, so every node must be able to record and pull:
#     each one is checked against this node's commit. The old template's add/stash/drop here is
#     gone: on a dirty node it threw changes away; a dirty node is now refused instead.
# fixpack-git-check.sh (shipped in this fixpack) repairs the git commit identity on each node:
# older firmware kept it in /root/.gitconfig only, so an install from an admin login failed to
# commit. The /boot slots are saved node-locally for post_install.

FIXPACK_SRCDIR="$1"
VERSION=$(awk '/^sys.product.version/ {print $NF}' /etc/settings.sys)
CHECK=$FIXPACK_SRCDIR/fixpack-git-check.sh
BOOT_BACKUP=/var/fixpack/kernel-boot-backup

if [ "$(printf '%s\n%s\n' 3.2.0 "$VERSION" | sort -V | head -1)" = 3.2.0 ] ; then
    sh $CHECK || { echo "kernel fixpack: this node is not ready, nothing changed"; exit 1; }
else
    HEAD=$(git -C / rev-parse HEAD 2>/dev/null || true)
    hex_sdk cmd -v "echo $(base64 -w0 $CHECK) | base64 -d | sh -s -- $HEAD" ||
        { echo "kernel fixpack: not every node is ready (see above), nothing changed"; exit 1; }
fi

# Firmware an earlier kernel fixpack left on this node may not be in git: 3.2.0's git_push takes
# only tracked files, and on older firmware the old template's commit failed when the admin
# login's HOME hid the git identity. Record it now, in its own commit, so this fixpack's commit
# holds only what this fixpack changes. The check above made sure nothing else is pending.
if [ -n "$(git -C / status --porcelain --untracked-files=all -- usr/lib/firmware 2>/dev/null)" ] ; then
    MSG="Record firmware already on $(hostname), before $FIXPACK_ID"
    git -C / add -- usr/lib/firmware ||
        { echo "kernel fixpack: could not stage the firmware already on this node, nothing changed"; exit 1; }
    if [ "$(printf '%s\n%s\n' 3.2.0 "$VERSION" | sort -V | head -1)" = 3.2.0 ] ; then
        hex_sdk git_push "$MSG" ||
            { echo "kernel fixpack: could not record the firmware already on this node, nothing changed"; exit 1; }
    else
        # one shared branch: this node commits it; the peers take it with the fixpack's commit
        ( cd / && git commit -q -m "$MSG" && git push -q ) ||
            { echo "kernel fixpack: could not record the firmware already on this node, nothing changed"; exit 1; }
    fi
fi

rm -rf $BOOT_BACKUP
mkdir -p $BOOT_BACKUP
cp -a /boot/Part1 /boot/Part2 $BOOT_BACKUP/
exit 0
