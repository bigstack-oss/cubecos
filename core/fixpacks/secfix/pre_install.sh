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

rm -rf $BOOT_BACKUP
mkdir -p $BOOT_BACKUP
cp -a /boot/Part1 /boot/Part2 $BOOT_BACKUP/
exit 0
