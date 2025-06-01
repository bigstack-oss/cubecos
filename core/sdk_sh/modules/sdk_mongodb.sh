# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

mongodb_stats()
{
    $MONGODB --quiet --eval 'rs.status()'
}

mongodb_repair_keyfile_ownership()
{
    local mongodb_keyfile="/etc/mongodb/keyfile"
    local mongod_name="mongod"
    if [ -f "$mongodb_keyfile" ] ; then
        local user=$(stat -c '%U' "$mongodb_keyfile")
        local group=$(stat -c '%G' "$mongodb_keyfile")

        if [[ "$user" != "$mongod_name" || "$group" != "$mongod_name" ]] ; then
            chown "$mongod_name":"$mongod_name" "$mongodb_keyfile"
        fi
    fi
}
