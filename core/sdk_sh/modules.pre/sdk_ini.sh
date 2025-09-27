# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

# Read a value from an INI with the section and the key.
# If the section is not provided, the section would be ignored.
# If either the file, the section, or the key does not exist, a blank string would be returned.
ini_read_value()
{
    local file="${1:-""}"
    local section="${2:-""}"
    local key="${3:-""}"

    if [ ! -f "$file" ] || [ -z "$key" ]; then
        return 0
    fi

    key="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<< "$key")"

    if [ -z "$section" ] ; then
        awk -v key="$key" '
BEGIN {
    FS = "=";
}
{
    # remove the leading spaces
    gsub(/^[ \t]+/, "", $1)
    # remove the ending spaces
    gsub(/[ \t]+$/, "", $1)
}
$1 == key {
    output=$2;
}
END {
    # remove the leading spaces
    gsub(/^[ \t]+/, "", output)
    # remove the ending spaces
    gsub(/[ \t]+$/, "", output)
    print output;
}
' "$file" | tr -d '\n'
    else
        section="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<< "$section")"

        awk -v section="[${section}]" -v key="$key" '
BEGIN {
    FS = "=";
}
{
    # remove the leading spaces
    gsub(/^[ \t]+/, "", $1)
    # remove the ending spaces
    gsub(/[ \t]+$/, "", $1)
}
$0 !~ FS && $1 == section {
    in_section=1;
    next;
}
$0 !~ FS && $1 ~ /^\[.*\]$/ {
    in_section=0;
}
in_section && $1 == key {
    output=$2;
}
END {
    # remove the leading spaces
    gsub(/^[ \t]+/, "", output)
    # remove the ending spaces
    gsub(/[ \t]+$/, "", output)
    print output;
}
' "$file" | tr -d '\n'
    fi
}

# Marshal ini config JSON object to ini file content.
# We would allow .[].header to be blank to represent configs without a section header.
# If .[].attributes[].key is blank, the config line would be ignored.
ini_marshal_config()
{
    # input format: [
    #   {
    #     header: "",
    #     attributes: [
    #       {
    #         key: "",
    #         value: "",
    #       },
    #     ],
    #   },
    # ]

    local exec_output=""
    local exec_error=""
    local input="${1:-"[]"}"
    local output=""

    json_is_array "$input"
    if [[ "$?" != "0" ]] ; then
        return "$ERROR_JSON_NOT_ARRAY"
    fi

    local section=""
    local section_header=""
    local attributes=""
    local attribute=""
    local key=""
    local value=""
    while read -r section; do
        section_header="$(json_get_value "$section" ".header")"
        attributes="$(json_get_compact_value "$section" ".attributes")"

        json_is_array "$attributes"
        if [[ "$?" != "0" ]] ; then
          return "$ERROR_JSON_NOT_ARRAY"
        fi

        if [ -n "$section_header" ] ; then
            output+="[${section_header}]\n"
        fi

        while read -r attribute; do
            key="$(json_get_value "$attribute" ".key")"
            value="$(json_get_value "$attribute" ".value")"

            if [ -z "$key" ] ; then
                continue
            fi

            output+="${key} = ${value}\n"
        done <<< "$(echo "$attributes" | jq -c ".[]")"

        output+="\n"
    done <<< "$(echo "$input" | jq -c ".[]")"

    echo -e "$output"
}
