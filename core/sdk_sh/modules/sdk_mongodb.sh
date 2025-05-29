# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

mongodb_check_rs_inited()
{
    $MONGODB --quiet --eval "db.hello().isWritablePrimary || db.hello().secondary" | grep -q true
    return $?
}

mongodb_init_rs()
{
    $MONGODB --quiet --eval "rs.initiate({_id:\"cube-cos-rs\",members:[{_id:0,host:\"$(hostname)\"}]})"
    return $?
}

mongodb_stats()
{
    $MONGODB --quiet --eval 'rs.status()'
}
