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

# $MONGODB addresses the replica set as a whole, which resolves to whichever
# member is currently primary. The FCV gate below needs the version of a *named*
# member instead, so it needs a shell pinned to one host.
mongodb_member_version()
{
    local host=$1
    local access=

    [ -z "$MONGODB_ADMIN_ACCESS" ] || access="admin:$MONGODB_ADMIN_ACCESS@"
    timeout $SRVTO /usr/bin/mongosh "mongodb://$access$host" --quiet --eval 'db.version()'
}

# Print the one major.minor every replica set member reports, returning non-zero
# if they do not all agree or one cannot be reached. This doubles as the FCV
# target: the FCV a replica set belongs at is the version its members actually
# run, once they all run the same one. Deriving it beats naming a version here,
# which would then have to be remembered on every future bump.
#
# The member list comes from rs.status() rather than the node roster: the FCV is
# a property of the replica set, so the set that has to agree is exactly the set
# of members, and asking the set itself needs no node-role lookup.
mongodb_agreed_version()
{
    # Fail-safe: EVERY member must answer AND report the same major.minor. An
    # unreachable member is "unknown", not "absent" -- treating it as absent
    # would report a mid-roll replica set as agreed and raise the FCV past what
    # the still-old member supports, stranding it on rejoin. Any miss => no
    # agreed version, and the loop bails on the first one.
    local members m v vers=

    members=$($MONGODB --quiet --eval 'rs.status().members.map(m => m.name).join(" ")' 2>/dev/null)
    [ -n "$members" ] || return 1
    for m in $members ; do
        v=$(mongodb_member_version "$m" 2>/dev/null | cut -d. -f1,2)
        [ -n "$v" ] || return 1
        vers="$vers $v"
    done

    vers=$(printf '%s\n' $vers | sort -u)
    [ "$(printf '%s\n' "$vers" | wc -l)" = "1" ] || return 1
    echo "$vers"
}

# 0 (uniform) only if every replica set member reports the same MongoDB minor --
# the safe precondition for raising the featureCompatibilityVersion. Raising the
# FCV is not reversible in place, and a member still running the previous major
# cannot rejoin once the FCV is above what its binary supports.
mongodb_version_uniform()
{
    mongodb_agreed_version >/dev/null
}

mongodb_fcv()
{
    $MONGODB --quiet --eval 'db.adminCommand({getParameter:1, featureCompatibilityVersion:1}).featureCompatibilityVersion.version' 2>/dev/null
}

# 0 (stale) only once every member agrees on a version AND the replica set is
# still running below it -- the roll finished but nothing raised the FCV. A
# mid-roll set has no agreed version, so it never reports stale: being behind
# while nodes are still rolling is the expected state, not a fault.
mongodb_fcv_stale()
{
    local target

    target=$(mongodb_agreed_version) || return 1
    [ "$(mongodb_fcv)" != "$target" ]
}

# Raise the FCV to the version the members agree on. Refuses on a set with no
# agreed version, so this is safe to call unconditionally -- it stays a no-op
# until the last node has rolled.
mongodb_raise_fcv()
{
    local target

    target=$(mongodb_agreed_version) || return 1
    $MONGODB --quiet --eval "JSON.stringify(db.adminCommand({setFeatureCompatibilityVersion:\"$target\", confirm:true}))" | grep -q '"ok":1'
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

mongodb_add_read_write_role()
{
    $MONGODB --quiet --eval 'JSON.stringify(db.getSiblingDB("admin").getUser("admin"))' 2>/dev/null | jq -r '.roles[].role' | grep -q "readWriteAnyDatabase"
    local could_read_write_db=$?
    if [ ${could_read_write_db:-0} -ne 0 ] ; then
        $MONGODB --quiet --eval 'db.getSiblingDB("admin").grantRolesToUser("admin",[{role:"readWriteAnyDatabase",db:"admin"}])'
    fi
}
