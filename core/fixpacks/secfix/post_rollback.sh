#!/bin/sh
# Kernel security fixpack: it has norollback, so hex_config refuses a rollback before this runs.
# If it ever runs, stop: the old kernel is kept in the other boot slot, not restored from here.
echo "kernel fixpack $FIXPACK_ID cannot be rolled back; boot the other slot to use the old kernel"
exit 1
