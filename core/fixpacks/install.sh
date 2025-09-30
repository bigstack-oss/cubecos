
if ! fixpack_sync >/dev/null 2>&1 ; then
    hex_sdk git_push "$FIXPACK_ID $FIXPACK_NAME ROLLBACK=$ROLLBACK $FIXPACK_DESCRIPTION Installed"
    hex_sdk cmd "[ $HOSTNAME = \$HOSTNAME ] || echo rm -rf $ROLLBACK_DIR"
    cubectl node rsync $ROLLBACK_DIR
    hex_sdk cmd "[ $HOSTNAME = \$HOSTNAME ] || rm -rf $ROLLBACK_DIR/fixpack-9"
    hex_sdk cmd "[ $HOSTNAME = \$HOSTNAME ] || for N in 8 7 6 5 4 3 2 1 0 ; do [ -d $ROLLBACK_DIR/fixpack-\$N ] && mv $ROLLBACK_DIR/fixpack-\$N $ROLLBACK_DIR/fixpack-\`expr \$N + 1\` ; done"
    hex_sdk cmd "[ $HOSTNAME = \$HOSTNAME ] || mv $tmpdir $ROLLBACK_DIR/fixpack-0"
    hex_sdk cmd "[ $HOSTNAME = \$HOSTNAME ] || /usr/sbin/hex_config fixpack_add_history \"$FIXPACK_ID\" \"$FIXPACK_NAME\" \"$ROLLBACK\" \"$FIXPACK_DESCRIPTION\" \"Installed\""
    hex_sdk cmd "[ $HOSTNAME = \$HOSTNAME ] || mv $tmpdir $ROLLBACK_DIR/fixpack-0"
fi
