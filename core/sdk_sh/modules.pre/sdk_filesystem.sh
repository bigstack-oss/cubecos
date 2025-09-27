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

filesystem_read_file()
{
    local exec_output=""
    local exec_error=""

    local path="${1:-""}"

    if [ ! -f "$path" ] ; then
        return 0
    fi

    _hex_function exec_output exec_error cat "$path"
    if [[ "$?" == "0" ]] ; then
        cat <<< "$exec_output"
    fi
}

_filesystem_decode_base64string()
{
    local input="${1:-""}"
    echo -e "$input" | base64 -d -
}

filesystem_decode_base64string()
{
    local exec_output=""
    local exec_error=""
    local input="${1:-""}"

    if _hex_function exec_output exec_error _filesystem_decode_base64string "$input"; then
        printf "%s" "$exec_output"
    fi
}

_filesystem_encode_base64string()
{
    local input="${1:-""}"
    echo -e "$input" | base64 -
}

filesystem_encode_base64string()
{
    local exec_output=""
    local exec_error=""
    local input="${1:-""}"

    if _hex_function exec_output exec_error _filesystem_encode_base64string "$input"; then
        printf "%s" "$exec_output"
    fi
}
