# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

memcache_stats()
{
    echo stats | nc $(netstat -lntp | grep memcached | awk '{print $4}' | awk -F: '{print $1}') 11211
}
