# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

mysql_stats()
{
    $MYSQL -u root -e "show global status like 'wsrep_%'"
}

mysql_clear()
{
    local jail_user=$($MYSQL -sNe "select host from mysql.user where host like '%-jail'")
    if [ "x$jail_user" != "x" ]; then
        $MYSQL -sNe "DROP USER 'root'@'$jail_user'"
    fi
}
