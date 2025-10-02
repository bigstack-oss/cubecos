
if ! fixpack_sync >/dev/null 2>&1 ; then
    hex_sdk git_push "$FIXPACK_ID $FIXPACK_NAME ROLLBACK=$ROLLBACK $FIXPACK_DESCRIPTION Installed"
    hex_sdk cmd "[ $HOSTNAME = \$HOSTNAME ] || echo rm -rf $ROLLBACK_DIR"
    cubectl node rsync $ROLLBACK_DIR >/dev/null 2>&1
    hex_sdk cmd "[ $HOSTNAME = \$HOSTNAME ] || /usr/sbin/hex_config fixpack_add_history \"$FIXPACK_ID\" \"$FIXPACK_NAME\" \"$ROLLBACK\" \"$FIXPACK_DESCRIPTION\" \"Installed\""
fi
