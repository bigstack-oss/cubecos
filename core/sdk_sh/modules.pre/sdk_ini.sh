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

    if ! json_is_array "$input" ; then
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

        if ! json_is_array "$attributes" ; then
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

# Unmarshal ini file content to ini config JSON object.
# We would allow .[].header to be blank to represent configs without a section header.
# The .[].attributes[].key should not be blank.
ini_unmarshal_config()
{
    # stdout format: [
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
    local IFS=$'='

    local input="${1:-""}"

    local output="[]"

    local line=""
    local first_part=""
    local second_part=""
    local section_header=""
    local section_no_header="$(jq -c -n '{header: "", attributes: []}')"
    local section="$(jq -c -n '{header: "", attributes: []}')"
    while read -r line ; do
        # split the line by the first '='
        read -r first_part second_part <<< "$line"
        if [ -z "$first_part" ] ; then
            continue
        fi

        first_part="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<< "$first_part")"
        second_part="$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<< "$second_part")"

        if [ -z "$section_header" ] && [ -n "$first_part" ] && [ -n "$second_part" ] ; then
            # These are configs without a section header.
            _hex_function exec_output exec_error \
                jq -c \
                --arg key "$first_part" \
                --arg value "$second_part" \
                '.attributes += [{key: $key, value: $value}]' \
                <(printf "%s" "$section_no_header")
            if [[ "$?" == "0" ]] ; then
                section_no_header="$exec_output"
            fi

            continue
        fi

        if [[ "$first_part" =~ ^"[".*"]"$ ]] ; then
            # This is a section header.
            first_part="${first_part#"["}"
            first_part="${first_part%"]"}"

            if [[ "$first_part" != "$section_header" ]] ; then
                # save the previous section into the output
                if [[ -n "$(json_get_value "$section" ".header")" ]] ; then
                    _hex_function exec_output exec_error \
                        jq -c \
                        --argjson section "$section" \
                        '. += [$section]' \
                        <(printf "%s" "$output")
                    if [[ "$?" == "0" ]] ; then
                        output="$exec_output"
                    fi
                fi

                section_header="$first_part"
                section="$(jq -c -n '{header: "", attributes: []}')"

                _hex_function exec_output exec_error \
                    jq -c \
                    --arg header "$section_header" \
                    '.header = $header' \
                    <(printf "%s" "$section")
                if [[ "$?" == "0" ]] ; then
                    section="$exec_output"
                fi
            fi

            continue
        fi

        if [[ "$section_header" == "$(json_get_value "$section" ".header")" ]] ; then
            # ensure it is the correct section object
            _hex_function exec_output exec_error \
                jq -c \
                --arg key "$first_part" \
                --arg value "$second_part" \
                '.attributes += [{key: $key, value: $value}]' \
                <(printf "%s" "$section")
            if [[ "$?" == "0" ]] ; then
                section="$exec_output"
            fi
        fi
    done <<< "$input"

    # If the section (with header) has an empty header, the section should be ignored.
    if [ -n "$(json_get_value "$section" ".header")" ] ; then
        _hex_function exec_output exec_error \
            jq -c \
            --argjson section "$section" \
            '. += [$section]' \
            <(printf "%s" "$output")
        if [[ "$?" == "0" ]] ; then
            output="$exec_output"
        fi
    fi

    if [[ "$(json_get_value "$section_no_header" ".attributes | length > 0")" == "true" ]] ; then
        _hex_function exec_output exec_error \
            jq -c \
            --argjson section "$section_no_header" \
            '. += [$section]' \
            <(printf "%s" "$output")
        if [[ "$?" == "0" ]] ; then
            output="$exec_output"
        fi
    fi

    json_get_compact_value "$output" "."
}
