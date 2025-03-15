# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

util_url_download()
{
    local url=$1
    local local_dir=$2
    local timeout=${3:-60}

    Quiet -n $WGET -q --no-check-certificate $url -P $local_dir
}
