# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

LICENSE_DIR=/etc/update
LICENSE_DAT=$LICENSE_DIR/license.dat
LICENSE_SIG=$LICENSE_DIR/license.sig
CMP_LICENSE_DAT=$LICENSE_DIR/license-cmp.dat
CMP_LICENSE_SIG=$LICENSE_DIR/license-cmp.sig

# space-free stem an imported license is normalized to
LICENSE_STAGE=/var/support/license_import

# license error codes
LICENSE_BADSOURCE=2
LICENSE_VALID=1
LICENSE_BADSYS=255
LICENSE_BADSIG=254
LICENSE_BADHW=253
LICENSE_NOEXIST=252
LICENSE_EXPIRED=251

host_local_run()
{
    # spwan a new session for env vars to fully take effect
    ssh root@localhost $@ 2>/dev/null
}

host_remote_run()
{
    local host=$1
    shift 1
    if [ "$host" == $HOSTNAME ] ; then
        $@ 2>/dev/null
    else
        ssh root@$host $@ 2>/dev/null
    fi
}

license_value_get()
{
    local key=$1
    local license=${2:-$LICENSE_DAT}

    if [ -f "$license" ] ; then
        grep "$key" "$license" | awk -F'=' '{print $2}' | tr -d '\n'
    fi
}

license_serial_get()
{
    /usr/sbin/dmidecode -s system-serial-number | sed "s/ //g"
}

license_error_string()
{
    local err=$1
    local days=$2
    local license=$3
    if [ $err -eq $LICENSE_VALID ] ; then
        local type=$(license_value_get "license.type" "$license")
        echo "License (type: $type) is valid for $days days"
    elif [ $err -eq $LICENSE_BADSYS ] ; then
        echo "License system is compromised"
    elif [ $err -eq $LICENSE_BADSIG ] ; then
        echo "Invalid license signature"
    elif [ $err -eq $LICENSE_BADHW ] ; then
        local serial=$(license_serial_get)
        echo "Invalid license files for this hardware (type: $serial)"
    elif [ $err -eq $LICENSE_NOEXIST ] ; then
        echo "License files are not installed"
    elif [ $err -eq $LICENSE_EXPIRED ] ; then
        echo "License files have expired"
    fi
}

license_check()
{
    local app=${1:-def}

    local days=
    days=$($HEX_CFG license_check $app)
    local r=$?
    if [ "$VERBOSE" == "1" ] ; then
        echo "hostname: $HOSTNAME"
        local license=$LICENSE_DAT
        if [ "x$app" = "xcmp" ] ; then
            license=$CMP_LICENSE_DAT
        fi
        license_error_string $r $days "$license"
        printf "\n"
    fi

    return $r
}

# extract $dir/$name.license to $LICENSE_STAGE.dat/.sig, locating the members
# by extension rather than by name
license_import_stage()
{
    local dir=$1
    local name=$2
    local work=$LICENSE_STAGE.d

    [ -f "$dir/$name.license" ] || return $LICENSE_BADSOURCE

    rm -rf "$work" && mkdir -p "$work" || return $LICENSE_BADSOURCE
    unzip -o -q "$dir/$name.license" -d "$work" || return $LICENSE_BADSOURCE

    local dat=
    dat=$(find "$work" -maxdepth 1 -type f -name '*.dat' | head -1)
    if [ -z "$dat" ] || [ ! -f "${dat%.dat}.sig" ] ; then
        rm -rf "$work"
        return $LICENSE_BADSOURCE
    fi

    cp -f "$dat" "$LICENSE_STAGE.dat" && cp -f "${dat%.dat}.sig" "$LICENSE_STAGE.sig"
    local r=$?
    rm -rf "$work"

    [ $r -eq 0 ] || return $LICENSE_BADSOURCE
    return 0
}

license_import_unstage()
{
    rm -rf "$LICENSE_STAGE.dat" "$LICENSE_STAGE.sig" "$LICENSE_STAGE.d" 2>/dev/null
}

# report current vs staged license. No arguments: it runs on peers too, and a
# name must not cross an ssh/scp hop.
license_staged_check()
{
    local new_ret=$LICENSE_BADSOURCE

    if [ -f "$LICENSE_STAGE.dat" ] && [ -f "$LICENSE_STAGE.sig" ] ; then
        local app="def"
        local product=$(license_value_get "product" "$LICENSE_STAGE.dat")
        if [ "x$product" = "xCubeCMP" ] ; then
            app="cmp"
        else
            product="CubeCOS"
        fi

        local license=$LICENSE_DAT
        if [ "x$app" = "xcmp" ] ; then
            license=$CMP_LICENSE_DAT
        fi

        local curr_days=
        curr_days=$($HEX_CFG license_check $app)
        local curr_ret=$?

        local new_days=
        new_days=$($HEX_CFG license_check $app "$LICENSE_STAGE")
        new_ret=$?

        printf "\nHostname: %s" "$HOSTNAME"
        printf "\nProduct: %s\n" "$product"
        printf "+%10s+%64s+\n" | tr " " "-"
        printf "| %8s | %-62s |\n" "Current" "$(license_error_string $curr_ret $curr_days "$license")"
        printf "| %8s | %-62s |\n" "New" "$(license_error_string $new_ret $new_days "$LICENSE_STAGE.dat")"
        printf "+%10s+%64s+\n" | tr " " "-"
    fi

    return $new_ret
}

license_import_check()
{
    local dir=$1
    local name=$2

    license_import_stage "$dir" "$name" || return $LICENSE_BADSOURCE
    license_staged_check
    local r=$?
    license_import_unstage
    return $r
}

license_show()
{
    local app=${1:-def}
    local days=
    days=$($HEX_CFG license_check $app)
    local r=$?
    local serial=$(license_serial_get)

    local license=$LICENSE_DAT
    if [ "x$app" = "xcmp" ] ; then
        license=$CMP_LICENSE_DAT
    fi

    if [ "$FORMAT" == "json" ] ; then
        printf "{ \"hostname\": \"$HOSTNAME\", \"serial\": \"$serial\", \"check\": $r "
        if [ $r -eq $LICENSE_VALID -o $r -eq $LICENSE_BADHW -o $r -eq $LICENSE_EXPIRED ] ; then
            local name=$(license_value_get "license.name" "$license")
            local type=$(license_value_get "license.type" "$license")
            local issueby=$(license_value_get "issue.by" "$license")
            local issueto=$(license_value_get "issue.to" "$license")
            local hardware=$(license_value_get "issue.hardware" "$license")
            local product=$(license_value_get "product" "$license")
            local feature=$(license_value_get "feature" "$license")
            local quantity=$(license_value_get "quantity" "$license")
            local supportplan=$(license_value_get "support.plan" "$license")
            local date=$(license_value_get "issue.date" "$license")
            local expiry=$(license_value_get "expiry.date" "$license")
            printf ", \"name\": \"$name\", \"type\": \"$type\", \"issueby\": \"$issueby\", \"issueto\": \"$issueto\", \"hardware\": \"$hardware\", \"product\": \"$product\", \"feature\": \"$feature\", \"quantity\": \"$quantity\", \"supportplan\": \"$supportplan\", \"date\": \"$date\", \"expiry\": \"$expiry\" "
            if [ $r -eq $LICENSE_VALID ] ; then
                printf ", \"days\": $days "
            fi
        fi
        printf "}"
    else
        printf "hostname: %s\n" "$HOSTNAME"
        printf "serial: %s\n" "$serial"
        if [ $r -eq $LICENSE_VALID -o $r -eq $LICENSE_BADHW -o $r -eq $LICENSE_EXPIRED ] ; then
            printf "%64s\n" | tr " " "-"
            cat "$license"
            printf "%64s\n" | tr " " "-"
        fi
        printf "state: %s\n" "$(license_error_string $r $days "$license")"
    fi
}

license_import_list()
{
    local dir=$1
    local f=

    for f in "$dir"/*.license ; do
        [ -f "$f" ] || continue
        f=$(basename "$f")
        printf "%s\n" "${f%.license}"
    done
}

license_cluster_import_check()
{
    local dir=$1
    local name=$2
    local ret=0

    if ! license_import_stage "$dir" "$name" ; then
        echo "license files .license is missing or malformed: $dir/$name.license"
        return $LICENSE_BADSOURCE
    fi

    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}" ; do
        local node=$(echo $node_entry | head -c -1)

        if [ "$node" == "$(hostname)" ] ; then
            $HEX_SDK license_staged_check
        else
            scp "$LICENSE_STAGE.dat" root@$node:$LICENSE_STAGE.dat 2>/dev/null
            scp "$LICENSE_STAGE.sig" root@$node:$LICENSE_STAGE.sig 2>/dev/null
            host_remote_run $node $HEX_SDK license_staged_check
        fi
        local r=$?
        if [ $r -le 255 -a $r -ge 245 ] ; then
            ret=-1
        fi
    done

    license_import_unstage
    for node_entry in "${node_array[@]}" ; do
        local node=$(echo $node_entry | head -c -1)
        [ "$node" == "$(hostname)" ] || host_remote_run $node $HEX_SDK license_import_unstage
    done

    return $ret
}

license_cluster_check()
{
    local app=${1:-def}

    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}" ; do
        local node=$(echo $node_entry | head -c -1)
        if [ "$node" == "$(hostname)" ] ; then
            $HEX_SDK -v license_check $app
        else
            host_remote_run $node $HEX_SDK -v license_check $app
        fi
    done
}

license_cluster_show()
{
    local app=${1:-def}

    local opts=
    local output=
    if [ "$FORMAT" == "json" ] ; then
        opts="-f json"
    fi
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}" ; do
        local node=$(echo $node_entry | head -c -1)
        if ping -c 1 -w 1 $node >/dev/null ; then
            local item=$(host_remote_run $node $HEX_SDK $opts license_show $app)
            if [ "$FORMAT" == "json" ] ; then
                if [ -n "$output" ] ; then
                    output="$output, $item"
                else
                    output=$item
                fi
            else
                printf "%s\n\n" "$item"
            fi
        fi
    done
    if [ "$FORMAT" == "json" ] ; then
        printf "[%s]" "$output"
    fi
}

license_cluster_import()
{
    local dir=$1
    local name=$2
    local ret=$LICENSE_VALID

    if license_import_stage "$dir" "$name" ; then
        local app="def"
        local suffix=
        local product=$(license_value_get "product" "$LICENSE_STAGE.dat")
        if [ "x$product" = "xCubeCMP" ] ; then
            app="cmp"
            suffix="-$app"
        else
            product="CubeCOS"
        fi

        readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
        declare -p node_array > /dev/null
        for node_entry in "${node_array[@]}" ; do
            local node=$(echo $node_entry | head -c -1)
            if [ "$node" == "$(hostname)" ] ; then
                mkdir -p $LICENSE_DIR
                $HEX_CFG license_check $app "$LICENSE_STAGE" >/dev/null
                ret=$?
                if [ $ret -eq $LICENSE_VALID ] ; then
                    cp -f "$LICENSE_STAGE.dat" $LICENSE_DIR/license$suffix.dat 2>/dev/null
                    cp -f "$LICENSE_STAGE.sig" $LICENSE_DIR/license$suffix.sig 2>/dev/null
                    echo "Imported $product license files for $node"
                    ret=0
                else
                    echo "Not a valid $product license for $node"
                fi
            else
                host_remote_run $node mkdir -p $LICENSE_DIR
                scp "$LICENSE_STAGE.dat" root@$node:$LICENSE_STAGE.dat 2>/dev/null
                scp "$LICENSE_STAGE.sig" root@$node:$LICENSE_STAGE.sig 2>/dev/null
                host_remote_run $node $HEX_CFG license_check $app $LICENSE_STAGE >/dev/null
                ret=$?
                if [ $ret -eq $LICENSE_VALID ] ; then
                    scp "$LICENSE_STAGE.dat" root@$node:$LICENSE_DIR/license$suffix.dat 2>/dev/null
                    scp "$LICENSE_STAGE.sig" root@$node:$LICENSE_DIR/license$suffix.sig 2>/dev/null
                    echo "Imported $product license files for $node"
                    ret=0
                else
                    echo "Not a valid $product license for $node"
                fi
            fi
        done

        license_import_unstage
        for node_entry in "${node_array[@]}" ; do
            local node=$(echo $node_entry | head -c -1)
            [ "$node" == "$(hostname)" ] || host_remote_run $node $HEX_SDK license_import_unstage
        done
    else
        echo "license files .license is missing or malformed: $dir/$name.license"
        ret=$LICENSE_BADSOURCE
    fi
    return $ret
}

license_cluster_serial_get()
{
    local hosts=
    local serials=

    printf "+%18s+%24s+\n" | tr " " "-"
    printf "| %16s | %22s |\n" "Hostname" "Serial"
    printf "+%18s+%24s+\n" | tr " " "-"
    readarray node_array <<<"$(cubectl node list -j | jq -r .[].hostname | sort)"
    declare -p node_array > /dev/null
    for node_entry in "${node_array[@]}" ; do
        local node=$(echo $node_entry | head -c -1)
        local serial=$(host_remote_run $node $HEX_SDK license_serial_get)
        if [ -n "$serials" ] ; then
            hosts="$hosts,$node"
            serials="$serials,$serial"
        else
            hosts=$node
            serials=$serial
        fi
        printf "| %16s | %22s |\n" "$node" "$serial"
    done
    printf "+%18s+%24s+\n\n" | tr " " "-"
    echo "cluster serials for license: $serials"
}
