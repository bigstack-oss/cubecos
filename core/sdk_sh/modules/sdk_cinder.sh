# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

CINDER_USER_INPUT_MODEL_DIRECTORY="/etc/cube/cos/cinder/models"
CINDER_BUILTIN_MODEL_DIRECTORY="/usr/share/cube/cos/cinder/builtin_models"

ERROR_CINDER_WRITE_MODEL_FILE_FAILED="1"
ERROR_CINDER_WRITE_MULTIPATH_CONFIG_FAILED="2"

cinder_is_all_true()
{
    local lines="${1:-""}"

    while read -r line; do
        if [ -z "$line" ]; then
            continue
        fi

        if [[ "$line" != "true" ]] ; then
            return 1
        fi
    done <<< "$lines"

    return 0
}

cinder_are_services_up()
{
    local exec_output=""
    local exec_error=""
    local storage_backends="${1:-""}"

    _hex_function exec_output exec_error openstack volume service list -c Binary -c Host -c State -f json
    is_valid_json "$exec_output"
    if [[ "$?" != "0" ]] ; then
        # the status is not a valid JSON string
        return 1
    fi
    local status="$exec_output"

    _hex_function_ret cinder_is_all_true "$(echo "$status" | jq -r ".[] | select(.Binary == \"cinder-scheduler\") | .State | test(\"up\")")"
    local isSchedulerUp="$?"
    if [[ "$isSchedulerUp" != "0" ]] ; then
        # cinder-scheduler is not up
        return 2
    fi

    _hex_function_ret cinder_is_all_true "$(echo "$status" | jq -r ".[] | select(.Binary == \"cinder-backup\") | .State | test(\"up\")")"
    local isBackupUp="$?"
    if [[ "$isBackupUp" != "0" ]] ; then
        # cinder-backup is not up
        return 3
    fi

    local isVolumeUp="0"
    if [ ! -z "$storage_backends" ] ; then
        while read -r backend ; do
            _hex_function_ret cinder_is_all_true "$(echo "$status" | jq -r ".[] | select(.Binary == \"cinder-volume\" and .Host == \"${backend//\"/}\") | .State | test(\"up\")")"
            isVolumeUp="$?"

            if [[ "$isVolumeUp" != "0" ]] ; then
                # cinder-volume is not up for this storage backend
                return 4
            fi
        done <<< "$(echo "$storage_backends" | tr ',' '\n')"
    else
        _hex_function_ret cinder_is_all_true "$(echo "$status" | jq -r ".[] | select(.Binary == \"cinder-volume\") | .State | test(\"up\")")"
        isVolumeUp="$?"

        if [[ "$isVolumeUp" != "0" ]] ; then
            # cinder-volume is not up for all storage backends
            return 4
        fi
    fi

    return 0
}

cinder_wait_for_services_up()
{
    local storage_backends="${1:-""}"
    local timeout="${2:-10}"

    local i=0
    while [ $i -lt $timeout ] ; do
        if cinder_are_services_up "$storage_backends" ; then
            break
        else
            sleep 1
        fi
        i=$(expr $i + 1)
    done
    [ $i -lt $timeout ]
}

cinder_get_model_file_name()
{
    local driver="${1:-""}"

    local output="${driver##*( )}"
    output="${output%%*( )}"
    output="${output#"cinder.volume.drivers."}"
    output="${output//./-}"

    echo -n "$output"
}

cinder_write_model_file()
{
    local exec_output=""
    local exec_error=""
    local file_name="${1:-""}"
    local model="${2:-""}"
    is_valid_json "$model"
    if [[ "$?" != "0" ]] ; then
        # The model is not a valid JSON string.
        return "$ERROR_JSON_INVALID_JSON"
    fi

    # output the model config to /etc/cube/cos/cinder/models as a YAML file
    _hex_function exec_output exec_error yq -p=json -o=yaml <(printf "%s" "$model")
    if [[ "$?" != "0" ]] ; then
        # The conversion from JSON to YAML failed.
        return "$ERROR_JSON_PARSING_FAILED"
    fi
    _hex_function_ret filesystem_write_file "${CINDER_USER_INPUT_MODEL_DIRECTORY}/${file_name}.yaml" "$exec_output"
    if [[ "$?" != "0" ]] ; then
        # Failed to write the model file.
        return "$ERROR_CINDER_WRITE_MODEL_FILE_FAILED"
    fi
}

cinder_marshal_multipath_conf()
{
    local exec_output=""
    local exec_error=""
    local multipath_conf="${1:-""}"
    local section=""
    local section_name=""
    local attributes=""
    local attribute=""
    local sub_sections=""
    local sub_section=""
    local sub_section_name=""
    local key=""
    local value=""
    local output=""

    is_valid_json "$multipath_conf"
    if [[ "$?" != "0" ]] ; then
        # The config is not a valid JSON.
        return "$ERROR_JSON_INVALID_JSON"
    fi
    json_is_array "$multipath_conf"
    if [[ "$?" != "0" ]] ; then
        # The config is not an array.
        return "$ERROR_JSON_NOT_ARRAY"
    fi

    while read -r section; do
        if [ -z "$section" ] ; then
            continue
        fi

        if ! json_has_key "$section" "section" ; then
            # Field section should exist.
            return "$ERROR_JSON_KEY_MISSING"
        fi
        if ! json_has_key "$section" "attributes" ; then
            # Field attributes should exist.
            return "$ERROR_JSON_KEY_MISSING"
        fi
        if ! json_has_key "$section" "subSections" ; then
            # Field subSections should exist.
            return "$ERROR_JSON_KEY_MISSING"
        fi

        # section name
        section_name="$(json_get_value "$section" ".section")"
        output+="${section_name} {\n"

        # section attributes
        attributes="$(json_get_compact_value "$section" ".attributes")"
        json_is_array "$attributes"
        if [[ "$?" != "0" ]] ; then
            # Field attributes is not an array.
            return "$ERROR_JSON_NOT_ARRAY"
        fi

        while read -r attribute; do
            if [ -z "$attribute" ] ; then
                continue
            fi

            if ! json_has_key "$attribute" "key" ; then
                # Field key should exist.
                return "$ERROR_JSON_KEY_MISSING"
            fi
            if ! json_has_key "$attribute" "value" ; then
                # Field value should exist.
                return "$ERROR_JSON_KEY_MISSING"
            fi

            key="$(json_get_value "$attribute" ".key")"
            value="$(json_get_value "$attribute" ".value")"

            output+="    ${key} ${value}\n"
        done <<< "$(echo "$attributes" | jq -c ".[]")"

        # section subsections
        sub_sections="$(json_get_compact_value "$section" ".subSections")"
        json_is_array "$sub_sections"
        if [[ "$?" != "0" ]] ; then
            # Field subSections is not an array.
            return "$ERROR_JSON_NOT_ARRAY"
        fi

        while read -r sub_section; do
            if [ -z "$sub_section" ] ; then
                continue
            fi

            if ! json_has_key "$sub_section" "section" ; then
                # Field section should exist.
                return "$ERROR_JSON_KEY_MISSING"
            fi
            if ! json_has_key "$sub_section" "attributes" ; then
                # Field attributes should exist.
                return "$ERROR_JSON_KEY_MISSING"
            fi

            sub_section_name="$(json_get_value "$sub_section" ".section")"
            output+="    ${sub_section_name} {\n"

            attributes="$(json_get_compact_value "$sub_section" ".attributes")"
            json_is_array "$attributes"
            if [[ "$?" != "0" ]] ; then
                # Field attributes is not an array.
                return "$ERROR_JSON_NOT_ARRAY"
            fi

            while read -r attribute; do
                if [ -z "$attribute" ] ; then
                    continue
                fi

                if ! json_has_key "$attribute" "key" ; then
                    # Field key should exist.
                    return "$ERROR_JSON_KEY_MISSING"
                fi
                if ! json_has_key "$attribute" "value" ; then
                    # Field value should exist.
                    return "$ERROR_JSON_KEY_MISSING"
                fi

                key="$(json_get_value "$attribute" ".key")"
                value="$(json_get_value "$attribute" ".value")"

                output+="        ${key} ${value}\n"
            done <<< "$(echo "$attributes" | jq -c ".[]")"

            output+="    }\n"
        done <<< "$(echo "$sub_sections" | jq -c ".[]")"

        output+="}\n"
    done <<< "$(echo "$multipath_conf" | jq -c ".[]")"

    echo -e "$output"
}

cinder_write_multipath_conf()
{
    local ret=""
    local file_name="${1:-""}"
    local multipath="${2:-""}"
    is_valid_json "$multipath"
    if [[ "$?" != "0" ]] ; then
        # The input is not a valid JSON string.
        return "$ERROR_JSON_INVALID_JSON"
    fi

    # set the multipath settings to /etc/multipath/conf.d
    local multipath_conf_file=""
    multipath_conf_file="$(cinder_marshal_multipath_conf "$multipath")"
    ret="$?"
    if [[ "$ret" != "0" ]] ; then
        # Failed to generate the multipath config file.
        return "$ret"
    fi

    _hex_function_ret filesystem_write_file "/etc/multipath/conf.d/${file_name}.conf" "$multipath_conf_file"
    if [[ "$?" != "0" ]] ; then
        # Failed to write the multipath config file.
        return "$ERROR_CINDER_WRITE_MULTIPATH_CONFIG_FAILED"
    fi
}

cinder_put_model()
{
    # input format : {
    #   driver: "",
    #   vendor: "",
    #   model: "",
    #   multipath: [
    #     {
    #       section: "",
    #       attributes: [
    #         {
    #           key: "",
    #           value: "",
    #         },
    #       ],
    #       subSections: [
    #         {
    #           section: "",
    #           attributes: [
    #             {
    #               key: "",
    #               value: "",
    #             },
    #           ],
    #         },
    #       ],
    #     },
    #   ],
    #   storage: {
    #     service: {
    #       driverSection: [
    #         {
    #           key: "",
    #           value: "",
    #         },
    #       ],
    #       extraSettings: [
    #         {
    #           sectionHeader: "",
    #           settings: [
    #             {
    #               key: "",
    #               value: "",
    #             },
    #           ],
    #         },
    #       ],
    #      extraConfigFiles: [
    #        {
    #          name: "", // name = test.conf => file path = /etc/cinder/external_storage/test.conf
    #          content: "", // base64 encoded file content
    #        },
    #      ],
    #     },
    #     volumeType: {
    #       settings: [
    #         {
    #           key: "",
    #           value: "",
    #         },
    #       ],
    #     },
    #     image: {
    #       useMultipath: true,
    #       forceMultipath: true,
    #     },
    #   },
    # }
    #
    # stdout format: {
    #   message: "",
    # }
    #
    # stderr format: {
    #   message: "",
    # }

    local ret=""
    local input="${1:-""}"
    is_valid_json "$input"
    if [[ "$?" != "0" ]] ; then
        # The input is not a valid JSON string.
        jq -c -n \
            '{message: "the input is not a valid JSON string"}' \
        >&2
        return "$ERROR_JSON_INVALID_JSON"
    fi

    # process inputs
    local driver="$(json_get_value "$input" ".driver")"
    if [ -z "$driver" ] ; then
        # The field driver is the ID, and it should not be blank.
        jq -c -n \
            '{message: "field driver should not be blank"}' \
            >&2
        return "$ERROR_JSON_KEY_MISSING"
    fi

    local model_file_name="$(cinder_get_model_file_name "$driver")"
    _hex_function_ret cinder_write_model_file "$model_file_name" "$input"
    ret="$?"
    if [[ "$ret" == "$ERROR_JSON_INVALID_JSON" ]] ; then
        jq -c -n \
            '{message: "the input is not a valid JSON string"}' \
            >&2
        return "$ret"
    elif [[ "$ret" == "$ERROR_JSON_PARSING_FAILED" ]] ; then
        jq -c -n \
            '{message: "failed to convert the input JSON to YAML"}' \
            >&2
        return "$ret"
    elif [[ "$ret" == "$ERROR_CINDER_WRITE_MODEL_FILE_FAILED" ]] ; then
        jq -c -n \
            '{message: "failed to write the model file"}' \
            >&2
        return "$ret"
    fi

    local multipath="$(json_get_value "$input" ".multipath")"
    _hex_function_ret cinder_write_multipath_conf "$model_file_name" "$multipath"
    ret="$?"
    if [[ "$ret" == "$ERROR_JSON_INVALID_JSON" ]] ; then
        jq -c -n \
            '{message: "the input is not a valid JSON string"}' \
            >&2
        return "$ret"
    elif [[  "$ret" == "$ERROR_JSON_KEY_MISSING" ]] ; then
        jq -c -n \
            '{message: "a field is missing"}' \
            >&2
        return "$ret"
    elif [[ "$ret" == "$ERROR_JSON_NOT_ARRAY" ]] ; then
        jq -c -n \
            '{message: "a field should be an array"}' \
            >&2
        return "$ret"
    elif [[ "$ret" == "$ERROR_CINDER_WRITE_MULTIPATH_CONFIG_FAILED" ]] ; then
        jq -c -n \
            '{message: "failed to write the multipath config file"}' \
            >&2
        return "$ret"
    fi

    # apply multipathd changes
    if is_compute_node ; then
        # multipathd is only need by nova-compute on compute nodes
        _hex_function_ret systemctl reload multipathd
    fi

    jq -c -n \
        --arg message "model ${driver} created" \
        '{message: $message}'
}

cinder_put_models()
{
    # input format: [
    #   {
    #     driver: "",
    #     vendor: "",
    #     model: "",
    #     multipath: [
    #       {
    #         section: "",
    #         attributes: [
    #           {
    #             key: "",
    #             value: "",
    #           },
    #         ],
    #         subSections: [
    #           {
    #             section: "",
    #             attributes: [
    #               {
    #                 key: "",
    #                 value: "",
    #               },
    #             ],
    #           },
    #         ],
    #       },
    #     ],
    #     storage: {
    #       service: {
    #         driverSection: [
    #           {
    #             key: "",
    #             value: "",
    #           },
    #         ],
    #         extraSettings: [
    #           {
    #             sectionHeader: "",
    #             settings: [
    #               {
    #                 key: "",
    #                 value: "",
    #               },
    #             ],
    #           },
    #         ],
    #       extraConfigFiles: [
    #         {
    #           name: "", // name = test.conf => file path = /etc/cinder/external_storage/test.conf
    #           content: "", // base64 encoded file content
    #         },
    #       ],
    #       },
    #       volumeType: {
    #         settings: [
    #           {
    #             key: "",
    #             value: "",
    #           },
    #         ],
    #       },
    #       image: {
    #         useMultipath: true,
    #         forceMultipath: true,
    #       },
    #     },
    #   }
    # ]
    #
    # stdout format: {
    #   message: "",
    # }

    local exec_output=""
    local exec_error=""
    local input="${1:-""}"
    local created_drivers=""
    is_valid_json "$input"
    if [[ "$?" != "0" ]] ; then
        # The input is not a valid JSON string.
        jq -c -n \
            '{message: "the input is not a valid JSON string"}' \
        >&2
        return "$ERROR_JSON_INVALID_JSON"
    fi
    json_is_array "$input"
    if [[ "$?" != "0" ]] ; then
        # The input is not an array.
        jq -c -n \
            '{message: "the input should be an array"}' \
            >&2
        return "$ERROR_JSON_NOT_ARRAY"
    fi

    local driver=""
    local model_file_name=""
    while read -r model; do
        driver="$(json_get_value "$model" ".driver")"
        if [ -z "$driver" ] ; then
            # The field driver is the ID, and it should not be blank.
            # Skip it silently.
            continue
        fi

        model_file_name="$(cinder_get_model_file_name "$driver")"
        _hex_function_ret cinder_write_model_file "$model_file_name" "$model"
        if [[ "$?" != "0" ]] ; then
            # Skip it silently.
            continue
        fi

        local multipath="$(json_get_value "$model" ".multipath")"
        _hex_function_ret cinder_write_multipath_conf "$model_file_name" "$multipath"
        if [[ "$?" != "0" ]] ; then
            # Skip it silently.
            continue
        fi

        if [ -z "$created_drivers" ] ; then
            created_drivers+="${driver}"
        else
            created_drivers+=",${driver}"
        fi
    done <<< "$(echo "$input" | jq -c ".[]")"

    # apply multipathd changes
    if is_compute_node ; then
        # multipathd is only need by nova-compute on compute nodes
        _hex_function_ret systemctl reload multipathd
    fi

    if [ -z "$created_drivers" ] ; then
        jq -c -n \
            --arg message "no model created" \
            '{message: $message}'
    else
        jq -c -n \
            --arg message "model ${created_drivers} created" \
            '{message: $message}'
    fi
}

cinder_get_model()
{
    # input format: {
    #   driver: "",
    # }
    #
    # stdout format : {
    #   driver: "",
    #   vendor: "",
    #   model: "",
    #   multipath: [
    #     {
    #       section: "",
    #       attributes: [
    #         {
    #           key: "",
    #           value: "",
    #         },
    #       ],
    #       subSections: [
    #         {
    #           section: "",
    #           attributes: [
    #             {
    #               key: "",
    #               value: "",
    #             },
    #           ],
    #         },
    #       ],
    #     },
    #   ],
    #   storage: {
    #     service: {
    #       driverSection: [
    #         {
    #           key: "",
    #           value: "",
    #         },
    #       ],
    #       extraSettings: [
    #         {
    #           sectionHeader: "",
    #           settings: [
    #             {
    #               key: "",
    #               value: "",
    #             },
    #           ],
    #         },
    #       ],
    #      extraConfigFiles: [
    #        {
    #          name: "", // name = test.conf => file path = /etc/cinder/external_storage/test.conf
    #          content: "", // base64 encoded file content
    #        },
    #      ],
    #     },
    #     volumeType: {
    #       settings: [
    #         {
    #           key: "",
    #           value: "",
    #         },
    #       ],
    #     },
    #     image: {
    #       useMultipath: true,
    #       forceMultipath: true,
    #     },
    #   },
    # }
    #
    # stderr format: {
    #   message: "",
    # }

    local exec_output=""
    local exec_error=""
    local input="${1:-""}"

    is_valid_json "$input"
    if [[ "$?" != "0" ]] ; then
        # The input is not a valid JSON string.
        jq -c -n \
            '{message: "the input is not a valid JSON string"}' \
            >&2
        return "$ERROR_JSON_INVALID_JSON"
    fi
    local driver="$(json_get_value "$input" ".driver")"
    if [ -z "$driver" ] ; then
        # The field driver is required.
        jq -c -n \
            '{message: "field driver should not be blank"}' \
            >&2
        return "$ERROR_JSON_KEY_MISSING"
    fi

    local model_file_name="$(cinder_get_model_file_name "$driver")"
    local model_file_path=""
    local user_input_model_file_path="${CINDER_USER_INPUT_MODEL_DIRECTORY}/${model_file_name}.yaml"
    local builtin_model_file_path="${CINDER_BUILTIN_MODEL_DIRECTORY}/${model_file_name}.yaml"
    if [ -f "$user_input_model_file_path" ] ; then
        model_file_path="$user_input_model_file_path"
    elif [ -f "$builtin_model_file_path" ] ; then
        model_file_path="$builtin_model_file_path"
    else
        jq -c -n \
            '{message: "the model does not exist"}' \
            >&2
        return 1
    fi

    _hex_function exec_output exec_error yq -p=yaml -o=json "$model_file_path"
    if [[ "$?" != "0" ]] ; then
        jq -c -n \
            '{message: "failed to output the model file as JSON}' \
            >&2
        return "$ERROR_JSON_PARSING_FAILED"
    fi

    json_get_compact_value "$exec_output" "."
}

cinder_get_models()
{
    # stdout format: [
    #   {
    #     driver: "",
    #     vendor: "",
    #     model: "",
    #     multipath: [
    #       {
    #         section: "",
    #         attributes: [
    #           {
    #             key: "",
    #             value: "",
    #           },
    #         ],
    #         subSections: [
    #           {
    #             section: "",
    #             attributes: [
    #               {
    #                 key: "",
    #                 value: "",
    #               },
    #             ],
    #           },
    #         ],
    #       },
    #     ],
    #     storage: {
    #       service: {
    #         driverSection: [
    #           {
    #             key: "",
    #             value: "",
    #           },
    #         ],
    #         extraSettings: [
    #           {
    #             sectionHeader: "",
    #             settings: [
    #               {
    #                 key: "",
    #                 value: "",
    #               },
    #             ],
    #           },
    #         ],
    #       extraConfigFiles: [
    #         {
    #           name: "", // name = test.conf => file path = /etc/cinder/external_storage/test.conf
    #           content: "", // base64 encoded file content
    #         },
    #       ],
    #       },
    #       volumeType: {
    #         settings: [
    #           {
    #             key: "",
    #             value: "",
    #           },
    #         ],
    #       },
    #       image: {
    #         useMultipath: true,
    #         forceMultipath: true,
    #       },
    #     },
    #   }
    # ]

    local exec_output=""
    local exec_error=""
    local models="[]"
    local model=""
    local driver=""
    declare -A model_set

    # iterate through user input models
    local file=""
    for file in "$(ls "${CINDER_USER_INPUT_MODEL_DIRECTORY}")" ; do
        if [ ! -f "${CINDER_USER_INPUT_MODEL_DIRECTORY}/${file}" ] ; then
            continue
        fi

        _hex_function exec_output exec_error yq -p=yaml -o=json "${CINDER_USER_INPUT_MODEL_DIRECTORY}/${file}"
        if [[ "$?" != "0" ]] ; then
            # parsing failed, skip it silently
            continue
        fi
        model="$(json_get_compact_value "$exec_output" ".")"

        driver="$(json_get_value "$model" ".driver")"
        if [[ "$driver" == "" ]] ; then
            # field driver is missing, skip it silently
            continue
        fi
        if [[ -v model_set["$driver"] ]] ; then
            # duplicated model, skip it silently
            continue
        fi

        _hex_function \
            exec_output \
            exec_error \
            jq -c \
                --argjson model "$model" \
                '. += [$model]' \
                <(printf "%s" "$models")
        if [[ "$?" != "0" ]] ; then
            # failed to add the model into array models, skip it silently
            continue
        fi
        models="$exec_output"
        model_set["$driver"]=1
    done

    # iterate through built-in models
    # if it is already defined in user input models, skip it
    for file in "$(ls "${CINDER_BUILTIN_MODEL_DIRECTORY}")" ; do
        if [ ! -f "${CINDER_BUILTIN_MODEL_DIRECTORY}/${file}" ] ; then
            continue
        fi

        _hex_function exec_output exec_error yq -p=yaml -o=json "${CINDER_BUILTIN_MODEL_DIRECTORY}/${file}"
        if [[ "$?" != "0" ]] ; then
            # parsing failed, skip it silently
            continue
        fi
        model="$(json_get_compact_value "$exec_output" ".")"

        driver="$(json_get_value "$model" ".driver")"
        if [[ "$driver" == "" ]] ; then
            # field driver is missing, skip it silently
            continue
        fi
        if [[ -v model_set["$driver"] ]] ; then
            # duplicated model, skip it silently
            continue
        fi

        _hex_function \
            exec_output \
            exec_error \
            jq -c \
                --argjson model "$model" \
                '. += [$model]' \
                <(printf "%s" "$models")
        if [[ "$?" != "0" ]] ; then
            # failed to add the model into array models, skip it silently
            continue
        fi
        models="$exec_output"
        model_set["$driver"]=1
    done

    json_get_compact_value "$models" "."
}
