# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

haproxy_stats()
{
    echo "show stat" | nc -U $1 | cut -d "," -f 1,2,37  | column -s, -t | grep -v "BACKEND\|FRONTEND"
}
