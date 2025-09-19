# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

ERROR_JSON_INVALID_JSON=10
ERROR_JSON_PARSING_FAILED=11
ERROR_JSON_KEY_MISSING=12
ERROR_JSON_NOT_ARRAY=13

# Dump hex_sdk json module error codes.
json_get_error_codes()
{
    jq -c -n \
        --arg invalidJson "$ERROR_JSON_INVALID_JSON" \
        --arg parsingFailed "$ERROR_JSON_PARSING_FAILED" \
        --arg keyMissing "$ERROR_JSON_KEY_MISSING" \
        --arg notArray "$ERROR_JSON_NOT_ARRAY" \
        '{
($invalidJson): "invalid json",
($parsingFailed): "parsing failed",
($keyMissing): "key missing",
($notArray): "not array"
}'
}

# Check if JSON has a key or not.
json_has_key()
{
    local input="${1:-"{}"}"
    local key="${2:-""}"

    _hex_function_ret jq -e "has(\"${key}\")" <(echo "$input")
    return $?
}

# Check if JSON is array or not.
json_is_array()
{
    local input="${1:-"{}"}"

    _hex_function_ret jq -e "type == \"array\"" <(echo "$input")
    return $?
}

# Get JSON value by key.
# Value null would be alternated with no value.
json_get_value()
{
    local exec_output=""
    local exec_error=""
    local input="${1:-"{}"}"
    local key="${2:-"."}"

    _hex_function exec_output exec_error jq -r "${key} // empty" <(echo "$input")
    local ret=$?
    echo -n "$exec_output"
    return $ret
}

# Get JSON compact value by key
# Value null would be alternated with no value.
json_get_compact_value()
{
    local exec_output=""
    local exec_error=""
    local input="${1:-"{}"}"
    local key="${2:-"."}"

    _hex_function exec_output exec_error jq -c "${key} // empty" <(echo "$input")
    local ret=$?
    echo -n "$exec_output"
    return $ret
}
