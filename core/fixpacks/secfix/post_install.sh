#!/bin/sh
# Kernel security fixpack, post-install. The fixpack installer sources this with errexit; exit 1
# restores the files this fixpack replaced on this node and fails the install.
#
# The new bzImage and initramfs.cgz go into the active /boot slot only; the other slot is put
# back as pre_install saved it, so the node can still boot the old kernel. The kernel and its
# usr/lib/modules/<version> belong together:
#   - 3.2.0 and later: every node installs the fixpack itself, so this node is complete here.
#     fixpack_sync records it in this node's git; the new modules and firmware are staged here
#     first, because git_push alone takes only files git already tracks.
#   - 3.0.0 to 3.1.20: this node installs for the cluster. The other nodes get usr/lib/modules and
#     usr/lib/firmware by git (commit, push, pull) and /boot by cubectl. Git goes first and every
#     step is checked: a node must never get the new kernel before it has the new modules. If git
#     fails, no other node is changed. (The old template ran git last and ignored its result.)

FIXPACK_SRCDIR="$1"
VERSION=$(awk '/^sys.product.version/ {print $NF}' /etc/settings.sys)
BOOT_BACKUP=/var/fixpack/kernel-boot-backup

PARTN=$(hex_cli -c firmware list | grep ACTIVE | cut -d":" -f1 | tr -d ' ' || true)
case "$PARTN" in
    1|2) ;;
    *) echo "kernel fixpack: cannot tell the active boot slot ($PARTN)"; exit 1 ;;
esac
OTHER=$((3 - PARTN))
[ -d $BOOT_BACKUP/Part$OTHER ] || { echo "kernel fixpack: no saved copy of boot slot $OTHER"; exit 1; }

if [ "$(printf '%s\n%s\n' 3.2.0 "$VERSION" | sort -V | head -1)" != 3.2.0 ] ; then
    MSG="$FIXPACK_ID $FIXPACK_NAME ROLLBACK=No $FIXPACK_DESCRIPTION Installed"
    ( cd / && git add -A && git commit -q -m "$MSG" && git push -q ) ||
        { echo "kernel fixpack: git commit/push failed on $(hostname); no other node was changed"; exit 1; }
    # Not `git pull`: it refuses to overwrite untracked files, and a peer can still hold firmware
    # an earlier kernel fixpack left untracked. Move the index to the new commit (mixed reset,
    # no file written), then write out the trees this fixpack changes. pre_install checked that
    # no peer has changes of its own there.
    hex_sdk cmd -v "git -C / fetch -q && git -C / reset -q @{upstream} && git -C / checkout -- usr/lib/modules usr/lib/firmware" ||
        { echo "kernel fixpack: not every node took the new modules (see above); /boot was not sent to any node"; exit 1; }
    cubectl node rsync /boot/Part$PARTN ||
        { echo "kernel fixpack: copying /boot/Part$PARTN to the other nodes failed; they have the modules but not the kernel"; exit 1; }
fi

if [ "$(printf '%s\n%s\n' 3.2.0 "$VERSION" | sort -V | head -1)" = 3.2.0 ] ; then
    # fixpack_sync's git_push stages only tracked files, so the new modules and firmware would
    # be left out of this node's record; stage them here so its commit holds them.
    git -C / add -- usr/lib/modules usr/lib/firmware ||
        echo "kernel fixpack: could not stage usr/lib/modules and usr/lib/firmware for the git record"
fi

rm -rf /boot/Part$OTHER
cp -a $BOOT_BACKUP/Part$OTHER /boot/
rm -rf $BOOT_BACKUP
touch /var/fixpack/need_reboot
exit 0
