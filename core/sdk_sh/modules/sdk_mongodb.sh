# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

mongodb_stats()
{
    $MONGODB --quiet --eval 'rs.status()'
}
