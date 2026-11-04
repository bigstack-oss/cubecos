#!/bin/sh
# Write the source directory of a QA dummy fixpack (bigstack-oss/cubecos#2223).
#
#   mkdummyfix.sh <dir> <fixpack-id> <firmware-version> <rollback: yes|no> <reboot: yes|no>
#
# A dummy changes one harmless file that the image already has and the rootfs git tracks,
# /usr/lib/cube/fixpack-dummy ("base" in the image), so an install leaves a git record and a
# rollback has something to restore. Each hook writes one line to /var/log/fixpack-dummy.log,
# so QA can see which hooks ran. Nothing else on the node changes.
set -e

[ $# -eq 5 ] || { echo "usage: $0 <dir> <fixpack-id> <firmware-version> <yes|no> <yes|no>" >&2; exit 2; }
DIR=$1 ID=$2 VER=$3 ROLLBACK=$4 REBOOT=$5
case "$ID" in dummy-*) ;; *) echo "$0: the ID must start with dummy-: $ID" >&2; exit 2 ;; esac
PLACEHOLDER=usr/lib/cube/fixpack-dummy

rm -rf "$DIR"
mkdir -p "$DIR/rootfs/$(dirname $PLACEHOLDER)"
echo "$ID" > "$DIR/rootfs/$PLACEHOLDER"
echo "$PLACEHOLDER" > "$DIR/backup.lst"

if [ "$ROLLBACK" = yes ] ; then
    ROLLBACK_FIELD=Yes ROLLBACK_TEXT="rollback allowed"
else
    # The marker file, not the ROLLBACK field, decides: hex_fixpack_install overwrites the field.
    : > "$DIR/norollback"
    ROLLBACK_FIELD=No ROLLBACK_TEXT="no rollback"
fi
if [ "$REBOOT" = yes ] ; then
    # The UI/API reads REBOOT_REQUIRED; the CLI reads /var/fixpack/need_reboot from post_install.
    REBOOT_ROLES="control compute storage" REBOOT_TEXT="reboot required"
else
    REBOOT_ROLES="" REBOOT_TEXT="no reboot"
fi

cat > "$DIR/fixpack.info" <<EOF
FIXPACK_ID="$ID"
FIXPACK_NAME="$ID"
FIXPACK_DESCRIPTION="QA dummy fixpack: $ROLLBACK_TEXT, $REBOOT_TEXT. Changes /$PLACEHOLDER only."
SUPPORTED_FIRMWARES="$VER"
REBOOT_REQUIRED="$REBOOT_ROLES"
ROLLBACK="$ROLLBACK_FIELD"
EOF

for HOOK in pre_install post_install pre_rollback post_rollback ; do
    {
        echo '#!/bin/sh'
        echo 'FIXPACK_SRCDIR="$1"'
        echo "echo \"\$(date -u +%FT%TZ) \$(hostname) $ID $HOOK\" >> /var/log/fixpack-dummy.log"
        [ "$HOOK" = post_install ] && [ "$REBOOT" = yes ] && echo 'touch /var/fixpack/need_reboot'
        echo 'exit 0'
    } > "$DIR/$HOOK.sh"
    chmod 755 "$DIR/$HOOK.sh"
done

cat > "$DIR/README" <<EOF
$ID is a dummy fixpack for QA and test clusters only; never install it on a cluster that must
stay clean, and never give it to a customer. It installs only on firmware $VER. It changes only
/$PLACEHOLDER (to "$ID"), and each hook adds one line to /var/log/fixpack-dummy.log.
It has $ROLLBACK_TEXT and $REBOOT_TEXT.
EOF
