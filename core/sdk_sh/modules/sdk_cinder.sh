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
ERROR_CINDER_WRITE_EXT_STORAGE_BACKEND_CONFIG_FAILED="3"
ERROR_CINDER_WRITE_EXT_STORAGE_EXTRA_CONFIG_OWNERSHIP_FAILED="4"
ERROR_CINDER_WRITE_EXT_STORAGE_EXTRA_CONFIG_FAILED="5"
ERROR_CINDER_APPLY_EXT_STORAGE_FAILED="6"
ERROR_CINDER_APPLY_VOLUME_TYPE_PROPERTIES_FAILED="7"

cinder_is_all_true()
{
    local lines="${1:-""}"

    while read -r line ; do
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

    if [ -z "$file_name" ] ; then
        return "$ERROR_CINDER_WRITE_MODEL_FILE_FAILED"
    fi

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

    local multipath="${1:-""}"

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

    is_valid_json "$multipath"
    if [[ "$?" != "0" ]] ; then
        # The config is not a valid JSON.
        return "$ERROR_JSON_INVALID_JSON"
    fi
    json_is_array "$multipath"
    if [[ "$?" != "0" ]] ; then
        # The config is not an array.
        return "$ERROR_JSON_NOT_ARRAY"
    fi

    while read -r section ; do
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

        while read -r attribute ; do
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

            output+="    ${key} \"${value}\"\n"
        done <<< "$(echo "$attributes" | jq -c ".[]")"

        # section subsections
        sub_sections="$(json_get_compact_value "$section" ".subSections")"
        json_is_array "$sub_sections"
        if [[ "$?" != "0" ]] ; then
            # Field subSections is not an array.
            return "$ERROR_JSON_NOT_ARRAY"
        fi

        while read -r sub_section ; do
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

            while read -r attribute ; do
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

                output+="        ${key} \"${value}\"\n"
            done <<< "$(echo "$attributes" | jq -c ".[]")"

            output+="    }\n"
        done <<< "$(echo "$sub_sections" | jq -c ".[]")"

        output+="}\n"
    done <<< "$(echo "$multipath" | jq -c ".[]")"

    echo -e "$output"
}

cinder_write_multipath_conf()
{
    local ret=""
    local file_name="${1:-""}"
    local multipath_conf="${2:-""}"

    if [ -z "$file_name" ] ; then
        return "$ERROR_CINDER_WRITE_MULTIPATH_CONFIG_FAILED"
    fi

    # set the multipath settings to /etc/multipath/conf.d
    _hex_function_ret filesystem_write_file "/etc/multipath/conf.d/${file_name}.conf" "$multipath_conf"
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
    #          name: "", // name = test.conf => file path = /etc/cinder/external_storage_extra_configs/test.conf
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

    # set the model file
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

    # set multipath settings
    local multipath="$(json_get_value "$input" ".multipath")"
    local multipath_conf=""
    multipath_conf="$(cinder_marshal_multipath_conf "$multipath")"
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
    fi
    _hex_function_ret cinder_write_multipath_conf "$model_file_name" "$multipath_conf"
    ret="$?"
    if [[ "$ret" != "0" ]] ; then
        jq -c -n \
            '{message: "failed to write the multipath config file"}' \
            >&2
        return "$ERROR_CINDER_WRITE_MULTIPATH_CONFIG_FAILED"
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
    #           name: "", // name = test.conf => file path = /etc/cinder/external_storage_extra_configs/test.conf
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
    while read -r model ; do
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
        local multipath_conf=""
        multipath_conf="$(cinder_marshal_multipath_conf "$multipath")"
        if [[ "$?" != "0" ]] ; then
            # Skip it silently.
            continue
        fi
        _hex_function_ret cinder_write_multipath_conf "$model_file_name" "$multipath_conf"
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
    #          name: "", // name = test.conf => file path = /etc/cinder/external_storage_extra_configs/test.conf
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
    #           name: "", // name = test.conf => file path = /etc/cinder/external_storage_extra_configs/test.conf
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

cinder_delete_model()
{
    # input format: {
    #   driver: "",
    # }
    #
    # stdout format: {
    #   message: "",
    # }
    #
    # stderr format: {
    #   message: "",
    # }

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

    # remove the model file
    local model_file_name="$(cinder_get_model_file_name "$driver")"
    local model_file_path="${CINDER_USER_INPUT_MODEL_DIRECTORY}/${model_file_name}.yaml"
    if [ ! -f "$model_file_path" ] ; then
        jq -c -n \
            '{message: "the model does not exist"}' \
            >&2
        return 1
    fi
    rm -f "$model_file_path"

    # remove the multipath config file
    local multipath_conf_file_path="/etc/multipath/conf.d/${model_file_name}.conf"
    if [ -f "$multipath_conf_file_path" ] ; then
        rm -f "$multipath_conf_file_path"
    fi

    # apply multipathd changes
    if is_compute_node ; then
        # multipathd is only need by nova-compute on compute nodes
        _hex_function_ret systemctl reload multipathd
    fi

    jq -c -n \
        --arg message "model ${driver} deleted" \
        '{message: $message}'
}

cinder_get_storage_name()
{
    local storage_name="${1:-""}"

    local output="${storage_name##*( )}"
    output="${output%%*( )}"
    output="${output//./-}"

    echo -n "$output"
}

cinder_marshal_storage_external_backend_conf()
{
    local exec_output=""
    local exec_error=""

    local external_backend="${1:-""}"
    local name="${2:-""}"
    local driver="${3:-""}"

    is_valid_json "$external_backend"
    if [[ "$?" != "0" ]] ; then
        # The input is not a valid JSON string.
        return "$ERROR_JSON_INVALID_JSON"
    fi

    local storage_name="$(cinder_get_storage_name "$name")"
    local settings=""
    local setting=""
    local key=""
    local value=""
    local config_section=""
    local config="[]"

    # prepare the config object of the driver section
    settings="$(json_get_value "$external_backend" ".driverSection")"
    json_is_array "$settings"
    if [[ "$?" != "0" ]] ; then
        return "$ERROR_JSON_NOT_ARRAY"
    fi
    config_section="$(jq -c -n \
        --arg name "$storage_name" \
        --arg driver "$driver" \
        '{
header: $name,
attributes: [
    {
        key: "backend_host",
        value: $name
    },
    {
        key: "volume_backend_name",
        value: $name
    },
    {
        key: "volume_driver",
        value: $driver
    }
]}')"
    while read -r setting ; do
        key="$(json_get_value "$setting" ".key")"
        value="$(json_get_value "$setting" ".value")"

        if [[ "$key" == "backend_host" \
            || "$key" == "volume_backend_name" \
            || "$key" == "volume_driver" ]] ; then
            # driver section title, field backend_host, field volume_backend_name,
            # and field volume_driver are controlled fields
            continue
        fi

        _hex_function \
            exec_output \
            exec_error \
            jq -c \
            --arg key "$key" \
            --arg value "$value" \
            '.attributes += [{key: $key, value: $value}]' \
            <(printf "%s" "$config_section")
        if [[ "$?" != "0" ]] ; then
            # failed to add the key value pair into the config object
            continue
        fi
        config_section="$exec_output"
    done <<< "$(echo "$settings" | jq -c ".[]")"
    _hex_function \
        exec_output \
        exec_error \
        jq -c \
        --argjson driverConfig "$config_section" \
        '. += [$driverConfig]' \
        <(printf "%s" "$config")
    if [[ "$?" == "0" ]] ; then
        config="$exec_output"
    fi

    # prepare the config objects of extraSettings sections
    local extra_settings="$(json_get_value "$external_backend" ".extraSettings")"
    json_is_array "$extra_settings"
    if [[ "$?" != "0" ]] ; then
        return "$ERROR_JSON_NOT_ARRAY"
    fi
    local section=""
    local section_header=""
    while read -r section ; do
        section_header="$(json_get_value "$section" ".sectionHeader")"
        if [ -z "$section_header" ] ; then
            # section header should not be blank
            continue
        fi

        config_section="$(jq -c -n \
            --arg header "$section_header" \
            '{header: $header, attributes: []}')"

        settings="$(json_get_value "$section" ".settings")"
        json_is_array "$settings"
        if [[ "$?" != "0" ]] ; then
            return "$ERROR_JSON_NOT_ARRAY"
        fi

        while read -r setting ; do
            key="$(json_get_value "$setting" ".key")"
            value="$(json_get_value "$setting" ".value")"

            _hex_function \
                exec_output \
                exec_error \
                jq -c \
                --arg key "$key" \
                --arg value "$value" \
                '.attributes += [{key: $key, value: $value}]' \
                <(printf "%s" "$config_section")
            if [[ "$?" != "0" ]] ; then
                # failed to add the key value pair into the config object
                continue
            fi

            config_section="$exec_output"
        done <<< "$(echo "$settings" | jq -c ".[]")"

        _hex_function \
            exec_output \
            exec_error \
            jq -c \
            --argjson configSection "$config_section" \
            '. += [$configSection]' \
            <(printf "%s" "$config")
        if [[ "$?" == "0" ]] ; then
            config="$exec_output"
        fi
    done <<< "$(echo "$extra_settings" | jq -c ".[]")"

    # generate the config file content for the external storage backend.
    ini_marshal_config "$config"
}

cinder_write_storage_external_backend_conf()
{
    local name="${1:-""}"
    local external_backend_conf="${2:-""}"

    if [ -z "$name" ] ; then
        return "$ERROR_CINDER_WRITE_EXT_STORAGE_BACKEND_CONFIG_FAILED"
    fi

    local storage_name="$(cinder_get_storage_name "$name")"

    # set the config to /etc/cinder/backends
    # file name format: ext_storage_*.conf
    _hex_function_ret filesystem_write_file "/etc/cinder/backends/ext_storage_${storage_name}.conf" "$external_backend_conf"
    if [[ "$?" != "0" ]] ; then
        # Failed to write the external storage backend config file.
        return "$ERROR_CINDER_WRITE_EXT_STORAGE_BACKEND_CONFIG_FAILED"
    fi
}

cinder_marshal_storage_extra_configs_ownership()
{
    local exec_output=""
    local exec_error=""

    local name="${1:-""}"
    local extra_configs="${2:-""}"
    local ownership="{}"

    if [ -z "$name" ] || ! json_is_array "$extra_configs" ; then
        echo -e "$ownership"
        return
    fi

    local storage_name="$(cinder_get_storage_name "$name")"
    local ownership="$(jq -c -n \
        --arg storage "$storage_name" \
        '{storage: $storage, extraConfigFiles: []}')"

    local extra_config=""
    local file_name=""
    while read -r extra_config ; do
        file_name="$(json_get_value "$extra_config" ".name")"
        if [ -z "$file_name" ] ; then
            continue
        fi

        _hex_function \
            exec_output \
            exec_error \
            jq -c \
            --arg name "$file_name" \
            '.extraConfigFiles += [{name: $name}]' \
            <(printf "%s" "$ownership")
        if [[ "$?" != "0" ]] ; then
            # failed to add the key value pair into the config object
            continue
        fi

        ownership="$exec_output"
    done <<< "$(echo "$extra_configs" | jq -c ".[]")"

    echo -e "$ownership"
}

cinder_write_storage_extra_configs_ownership()
{
    local exec_output=""
    local exec_error=""

    local file_name="${1:-""}"
    local ownership="${2:-""}"

    if [ -z "$file_name" ] ; then
        return "$ERROR_CINDER_WRITE_EXT_STORAGE_EXTRA_CONFIG_OWNERSHIP_FAILED"
    fi

    is_valid_json "$ownership"
    if [[ "$?" != "0" ]] ; then
        # The ownership is not a valid JSON string.
        return "$ERROR_JSON_INVALID_JSON"
    fi

    _hex_function exec_output exec_error yq -p=json -o=yaml <(printf "%s" "$ownership")
    if [[ "$?" != "0" ]] ; then
        # The conversion from JSON to YAML failed.
        return "$ERROR_JSON_PARSING_FAILED"
    fi
    _hex_function_ret filesystem_write_file "/etc/cube/cos/cinder/storage_extra_configs_ownership/${file_name}.yaml" "$exec_output"
    if [[ "$?" != "0" ]] ; then
        # Failed to write the ownership file.
        return "$ERROR_CINDER_WRITE_EXT_STORAGE_EXTRA_CONFIG_OWNERSHIP_FAILED"
    fi
}

cinder_write_storage_extra_config_file()
{
    local file_name="${1:-""}"
    # base64 encoded file content
    local file_content_base64="${2:-""}"

    if [ -z "$file_name" ] ; then
        return "$ERROR_CINDER_WRITE_EXT_STORAGE_EXTRA_CONFIG_FAILED"
    fi

    local file_content="$(filesystem_decode_base64string "$file_content_base64")"

    # set the config under /etc/cinder/external_storage_extra_configs
    _hex_function_ret filesystem_write_file "/etc/cinder/external_storage_extra_configs/${file_name}" "$file_content"
    if [[ "$?" != "0" ]] ; then
        # Failed to write the external storage backend config file.
        return "$ERROR_CINDER_WRITE_EXT_STORAGE_EXTRA_CONFIG_FAILED"
    fi
}

cinder_apply_storage()
{
    local exec_output=""
    local exec_error=""

    local storage_name="${1:-""}"
    local is_default="${2:-""}"
    local image_use_multipath="${3:-""}"
    local image_enforce_multipath="${4:-""}"

    if [ -z "$storage_name" ] \
        || [[ "$is_default" != "true" && "$is_default" != "false" ]] \
        || [[ "$image_use_multipath" != "true" && "$image_use_multipath" != "false" ]] \
        || [[ "$image_enforce_multipath" != "true" && "$image_enforce_multipath" != "false" ]] ; then
        return "$ERROR_CINDER_APPLY_EXT_STORAGE_FAILED"
    fi

    # edit the policy file
    local input_dir="$(MakeTempDir)"
    mkdir -p "${input_dir}/external_storage"
    cp -f "/etc/policies/external_storage/external_storage1_0.yml" "${input_dir}/external_storage/"
    local ext_storage_policy_file="${input_dir}/external_storage/external_storage1_0.yml"

    # storage backends
    _hex_function exec_output exec_error yq '.backends | length' "$ext_storage_policy_file"
    if [[ "$?" != "0" ]] ; then
        return "$ERROR_CINDER_APPLY_EXT_STORAGE_FAILED"
    fi
    local backend_count_minus_one=$(($(echo -n "$exec_output") - 1))
    local storage_found="false"
    local backend_index="0"
    for backend_index in "$(seq 0 "$backend_count_minus_one")" ; do
        _hex_function exec_output exec_error yq -r ".backends[${backend_index}].name" "$ext_storage_policy_file"
        if [[ "$?" == "0" && "$exec_output" == "$storage_name" ]] ; then
            storage_found="true"
            break
        fi
    done
    if [[ "$storage_found" == "false" ]] ; then
        _hex_function_ret yq -i ".backends[$((${backend_count_minus_one} + 1))].name = \"${storage_name}\"" "$ext_storage_policy_file"
        if [[ "$?" != "0" ]] ; then
            return "$ERROR_CINDER_APPLY_EXT_STORAGE_FAILED"
        fi
    fi

    # default volume type
    if [[ "$is_default" == "true" ]] ; then
        _hex_function_ret yq -i ".volumeType.default = \"${storage_name}\"" "$ext_storage_policy_file"
        if [[ "$?" != "0" ]] ; then
            return "$ERROR_CINDER_APPLY_EXT_STORAGE_FAILED"
        fi
    fi

    # glance volume-backed image use/force multipath
    _hex_function_ret yq -i ".image.multipath.use = ${image_use_multipath}" "$ext_storage_policy_file"
    if [[ "$?" != "0" ]] ; then
        return "$ERROR_CINDER_APPLY_EXT_STORAGE_FAILED"
    fi
    _hex_function_ret yq -i ".image.multipath.enforce = ${image_enforce_multipath}" "$ext_storage_policy_file"
    if [[ "$?" != "0" ]] ; then
        return "$ERROR_CINDER_APPLY_EXT_STORAGE_FAILED"
    fi

    # apply configs, and restart services
    $HEX_CFG apply $input_dir
    if [[ "$?" != "0" ]] ; then
        return "$ERROR_CINDER_APPLY_EXT_STORAGE_FAILED"
    fi

    return 0
}

cinder_is_volume_type_in_use()
{
    local volume_type="${1:-""}"
    if [ -z "$volume_type" ] ; then
        return 0
    fi

    _hex_function exec_output exec_error openstack volume list --long -f json
    if [[ "$?" != "0" ]] || ! json_is_array "$exec_output" ; then
        return 1
    fi
    _hex_function exec_output exec_error \
        jq -c "map(select(.Type == \"${volume_type}\")) | length" <(printf "%s" "$exec_output")
    if [[ "$?" != "0" || "$exec_output" != "0" ]] ; then
         # the volume type is in use
        return 1
    fi

    return 0
}

cinder_set_volume_type_properties()
{
    local exec_output=""
    local exec_error=""

    local storage_name="${1:-""}"
    local properties="${2:-""}"

    # check if the volume type exist
    _hex_function exec_output exec_error openstack volume type list -c Name -f json
    is_valid_json "$exec_output"
    if [[ "$?" != "0" ]] ; then
        return "$ERROR_JSON_INVALID_JSON"
    fi
    json_is_array "$exec_output"
    if [[ "$?" != "0" ]] ; then
        return "$ERROR_JSON_NOT_ARRAY"
    fi

    local volume_type_found="false"
    local volume_type=""
    while read -r volume_type ; do
        if [[ "$(json_get_value "$volume_type" ".Name")" == "$storage_name" ]] ; then
            volume_type_found="true"
            break
        fi
    done <<< "$(echo "$exec_output" | jq -c ".[]")"
    if [[ "$volume_type_found" == "false" ]] ; then
        return "$ERROR_CINDER_APPLY_VOLUME_TYPE_PROPERTIES_FAILED"
    fi

    # check if the volume type is in use, skip applying changes if in use
    if ! cinder_is_volume_type_in_use "$storage_name" ; then
        return "$ERROR_CINDER_APPLY_VOLUME_TYPE_PROPERTIES_FAILED"
    fi

    # compute the difference between the current properties
    # of the volume type and the target properties
    json_is_array "$properties"
    if [[ "$?" != "0" ]] ; then
        return "$ERROR_JSON_NOT_ARRAY"
    fi

    _hex_function exec_output exec_error openstack volume type show "$storage_name" -f json
    if [[ "$?" != "0" ]] ; then
        return "$ERROR_CINDER_APPLY_VOLUME_TYPE_PROPERTIES_FAILED"
    fi
    _hex_function exec_output exec_error jq -c ".properties" <(printf "%s" "$exec_output")
    if [[ "$?" != "0" ]] ; then
        return "$ERROR_CINDER_APPLY_VOLUME_TYPE_PROPERTIES_FAILED"
    fi
    local current_properties="$exec_output"
    local current_property_key=""
    local current_value=""

    local property=""
    local key=""
    local value=""
    local properties_to_set="[]"
    local property_object="{}"

    while read -r property ; do
        key="$(json_get_value "$property" ".key")"
        value="$(json_get_value "$property" ".value")"

        if [ -z "$value" ] ; then
            continue
        fi

        if _hex_function \
            exec_output \
            exec_error \
            jq -c \
            --arg key "$key" \
            --arg value "$value" \
            '.[$key] = $value' \
            <(printf "%s" "$property_object") ; then
            property_object="$exec_output"
        fi

        current_value="$(json_get_value "$current_properties" ".\"${key}\"")"

        if [[ "$value" != "$current_value" ]] ; then
            _hex_function \
                exec_output \
                exec_error \
                jq -c \
                --arg key "$key" \
                --arg value "$value" \
                '. += [{key: $key, value: $value}]' \
                <(printf "%s" "$properties_to_set")
            if [[ "$?" != "0" ]] ; then
                # failed to add the key value pair into array properties_to_set,
                # skip it silently
                continue
            fi

            properties_to_set="$exec_output"
        fi
    done <<< "$(echo "$properties" | jq -c ".[]")"

    local properties_to_unset="[]"
    while read -r current_property_key ; do
        if [[ "$current_property_key" == "volume_backend_name" ]] ; then
            # we should not remove this property
            continue
        fi

        value="$(json_get_value "$property_object" ".\"${current_property_key}\"")"
        if [ -n "$value" ] ; then
            continue
        fi

        _hex_function \
            exec_output \
            exec_error \
            jq -c \
            --arg key "$current_property_key" \
            '. += [$key]' \
            <(printf "%s" "$properties_to_unset")
        if [[ "$?" != "0" ]] ; then
            # failed to add the key into array properties_to_unset,
            # skip it silently
            continue
        fi

        properties_to_unset="$exec_output"
    done <<< "$(echo "$current_properties" | jq -r "keys[]")"

    # apply changes of volume type properties
    local flag_index="0"
    declare -a unset_flag
    while read -r property ; do
        if [ -z "$property" ] ; then
            continue
        fi

        unset_flag["$flag_index"]="--property"
        flag_index=$(($flag_index + 1))
        unset_flag["$flag_index"]="${property}"
        flag_index=$(($flag_index + 1))
    done <<< "$(echo "$properties_to_unset" | jq -r ".[]")"

    if [[ "$flag_index" != "0" ]] ; then
        _hex_function_ret openstack volume type unset "${unset_flag[@]}" "$storage_name"
    fi

    flag_index="0"
    declare -a set_flag
    while read -r property ; do
        if [ -z "$property" ] ; then
            continue
        fi

        key="$(json_get_value "$property" ".key")"
        value="$(json_get_value "$property" ".value")"

        if [ -z "$key" ] || [ -z "$value" ] ; then
            continue
        fi

        set_flag["$flag_index"]="--property"
        flag_index=$(($flag_index + 1))
        set_flag["$flag_index"]="${key}=${value}"
        flag_index=$(($flag_index + 1))
    done <<< "$(echo "$properties_to_set" | jq -c ".[]")"

    if [[ "$flag_index" != "0" ]] ; then
        _hex_function_ret openstack volume type set "${set_flag[@]}" "$storage_name"
    fi
}

cinder_put_storage()
{
    # input format: {
    #   name: "",
    #   driver: "",
    #   isDefault: true,
    #   storage: {
    #     service: {
    #       driverSection: [
    #         {
    #           key: "",
    #           value: "",
    #         }
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
    #       extraConfigFiles: [
    #         {
    #           name: "", // name = test.conf => file path = /etc/cinder/external_storage_extra_configs/test.conf
    #           content: "", // base64 encoded file content
    #         },
    #       ],
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

    local exec_output=""
    local exec_error=""
    local ret=""

    # process inputs
    local input="${1:-""}"
    is_valid_json "$input"
    if [[ "$?" != "0" ]] ; then
        # The input is not a valid JSON string.
        jq -c -n \
            '{message: "the input is not a valid JSON string"}' \
            >&2
        return "$ERROR_JSON_INVALID_JSON"
    fi

    local name="$(json_get_value "$input" ".name")"
    if [ -z "$name" ] ; then
        # The field name is required. Field name is also the ID of this put operation.
        jq -c -n \
            '{message: "field name should not be blank"}' \
            >&2
        return "$ERROR_JSON_KEY_MISSING"
    fi

    if [[ "$name" == "__DEFAULT__" \
        || "$name" == "CubeStorage" \
        || "$name" == "cube" \
        || "$name" == "ceph" ]] ; then
        # The value of field name is reserved.
        jq -c -n \
            --arg message "name ${name} is reserved" \
            '{message: $message}' \
            >&2
        return 1
    fi

    if [ -f "/etc/settings.cluster.json" ] ; then
        local cluster_settings=""
        _hex_function exec_output exec_error jq -c "." "/etc/settings.cluster.json"
        if [[ "$?" == "0" ]] ; then
            cluster_settings="$exec_output"
            _hex_function exec_output exec_error jq -r "keys[]" "/etc/settings.cluster.json"
            if [[ "$?" == "0" ]] ; then
                local nodes=($exec_output)
                local node=""
                for node in "${nodes[@]}" ; do
                    if [[ "$name" == "$node" ]] ; then
                        # The value of field name is reserved.
                        jq -c -n \
                            --arg message "name ${name} is reserved" \
                            '{message: $message}' \
                            >&2
                        return 1
                    fi
                done
            fi
        fi
    fi

    if [[ "$name" == *"-pool" || "$name" == *"-ssd" ]] ; then
        # The value of field name is reserved.
        jq -c -n \
            --arg message "name ${name} is reserved" \
            '{message: $message}' \
            >&2
        return 1
    fi

    local driver="$(json_get_value "$input" ".driver")"
    if [ -z "$driver" ] ; then
        # The field driver is required.
        jq -c -n \
            '{message: "field driver should not be blank"}' \
            >&2
        return "$ERROR_JSON_KEY_MISSING"
    fi

    # set the configs
    local storage="$(json_get_compact_value "$input" ".storage")"
    if [ -z "$storage" ] ; then
        # The field storage is required.
        jq -c -n \
            '{message: "field storage should not be blank"}' \
            >&2
        return "$ERROR_JSON_KEY_MISSING"
    fi

    local external_backend="$(json_get_compact_value "$storage" ".service")"
    local extra_configs="$(json_get_compact_value "$external_backend" ".extraConfigFiles")"
    json_is_array "$extra_configs"
    if [[ "$?" != "0" ]] ; then
        # The field extraConfigFiles is not an array.
        jq -c -n \
            '{message: "the field extraConfigFiles should be an array"}' \
            >&2
        return "$ERROR_JSON_NOT_ARRAY"
    fi

    # set the storage config
    local external_backend_conf=""
    external_backend_conf="$(cinder_marshal_storage_external_backend_conf "$external_backend" "$name" "$driver")"
    ret="$?"
    if [[ "$ret" == "$ERROR_JSON_INVALID_JSON" ]] ; then
        # The input is not a valid JSON string.
        jq -c -n \
            '{message: "the input is not a valid JSON string"}' \
            >&2
        return "$ret"
    elif [[ "$ret" == "$ERROR_JSON_NOT_ARRAY" ]] ; then
        jq -c -n \
            '{message: "a field should be an array"}' \
            >&2
        return "$ret"
    fi

    _hex_function_ret cinder_write_storage_external_backend_conf "$name" "$external_backend_conf"
    ret="$?"
    if [[ "$ret" != "0" ]] ; then
        jq -c -n \
            '{message: "failed to write the storage config file"}' \
            >&2
        return "$ERROR_CINDER_WRITE_EXT_STORAGE_BACKEND_CONFIG_FAILED"
    fi

    # set the extra config files ownership
    # We write the ownership file first in case writing extra config files fail.
    local storage_extra_configs_ownership=""
    storage_extra_configs_ownership="$(cinder_marshal_storage_extra_configs_ownership "$name" "$extra_configs")"
    _hex_function_ret cinder_write_storage_extra_configs_ownership "$name" "$storage_extra_configs_ownership"
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
    elif [[ "$ret" == "$ERROR_CINDER_WRITE_EXT_STORAGE_EXTRA_CONFIG_OWNERSHIP_FAILED" ]] ; then
        jq -c -n \
            '{message: "failed to write the extra config ownership file"}' \
            >&2
        return "$ret"
    fi

    # set the extra configs
    local extra_config=""
    local file_name=""
    local file_content_base64=""
    while read -r extra_config ; do
        file_name="$(json_get_value "$extra_config" ".name")"
        if [ -z "$file_name" ] ; then
            continue
        fi

        file_content_base64="$(json_get_value "$extra_config" ".content")"

        _hex_function_ret cinder_write_storage_extra_config_file "$file_name" "$file_content_base64"
        if [[ "$ret" != "0" ]] ; then
            jq -c -n \
                '{message: "failed to write the storage extra config files"}' \
                >&2
            return "$ERROR_CINDER_WRITE_EXT_STORAGE_EXTRA_CONFIG_FAILED"
        fi
    done <<< "$(echo "$extra_configs" | jq -c ".[]")"

    # apply changes
    local is_default="$(json_get_value "$input" ".isDefault")"
    if [[ "$is_default" != "true" ]] ; then
        is_default="false"
    fi
    local image_use_multipath="$(json_get_value "$storage" ".image.useMultipath")"
    if [[ "$image_use_multipath" != "true" ]] ; then
        image_use_multipath="false"
    fi
    local image_force_multipath="$(json_get_value "$storage" ".image.forceMultipath")"
    if [[ "$image_force_multipath" != "true" ]] ; then
        image_force_multipath="false"
    fi
    _hex_function_ret \
        cinder_apply_storage \
        "$name" \
        "$is_default" \
        "$image_use_multipath" \
        "$image_force_multipath"
    if [[ "$?" != "0" ]] ; then
        jq -c -n \
            '{message: "failed to apply the storage config"}' \
            >&2
        return "$ERROR_CINDER_APPLY_EXT_STORAGE_FAILED"
    fi

    # set volume type properties
    local volume_type_settings="$(json_get_compact_value "$storage" ".volumeType.settings")"
    cinder_set_volume_type_properties "$name" "$volume_type_settings"
    ret="$?"
    local message="storage ${name} created"
    if [[ "$ret" == "$ERROR_JSON_INVALID_JSON" ]] ; then
        jq -c -n \
            '{message: "the input is not a valid JSON string"}' \
            >&2
        return "$ret"
    elif [[ "$ret" == "$ERROR_JSON_NOT_ARRAY" ]] ; then
        jq -c -n \
            '{message: "a field should be an array"}' \
            >&2
        return "$ret"
    elif [[ "$ret" == "$ERROR_CINDER_APPLY_VOLUME_TYPE_PROPERTIES_FAILED" ]] ; then
        message+=", volume type properties ignored"
    fi

    jq -c -n \
        --arg message "$message" \
        '{message: $message}'
}
