# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

filesystem_write_file()
{
    local path="${1:-""}"
    local content="${2:-""}"
    cat <<< "$content" > "$path"
}
