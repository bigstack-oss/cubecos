# CUBE SDK
# thanos object storage

# Object storage for thanos: a native RGW user, its bucket, and the objstore config
# thanos reads.
#
# Deliberately a NATIVE radosgw user rather than a keystone EC2 credential. The
# admin EC2 credential is contested: sdk_health's log-upload path runs
# `ec2 credentials delete admin` and recreates it, while cube-cos-api recreates a
# deterministic one of its own -- so each rotates the other out, and anything caching
# the pair breaks. A native user is invisible to both and cannot be rotated out from
# under thanos. os_s3_bucket_quota already drives radosgw-admin directly, so native
# users alongside keystone-mapped ones are an established arrangement here.
#
# The endpoint is supplied by the caller rather than discovered here.
# os_endpoint.snapshot is the obvious source and the wrong one twice over: it is not
# written until cube_last, six commit levels after prometheus, and a master's first
# bootstrap skips it entirely, so at commit time it is routinely absent. Its "public"
# row also resolves to EXTERNAL, the wrong side of the appliance for a control-plane
# upload. config_prometheus already holds the control vip, so it passes <vip>:8888 --
# the same internal endpoint config_swift publishes -- and this stays a single source
# of truth instead of re-deriving it from a tuning.
#
# Idempotent: safe to run on every commit. A node whose file is already exactly what
# this would write returns without touching RGW; see the fast path below.
thanos_objstore_setup()
{
    local ep=$1
    local bucket=${2:-thanos}
    local uid=thanos
    local conf=/etc/thanos/objstore.yml
    local ak sk host

    if [ "x$ep" = "x" ] ; then
        log_error "thanos_objstore_setup: usage: thanos_objstore_setup <host:port> [bucket]"
        return 1
    fi

    # Fast path: the file is already what this would write. Everything below needs RGW --
    # the user and the bucket live there, not on this node -- and on a cold power cycle of
    # a cluster whose OSDs sit on the compute nodes RGW cannot answer yet: those OSDs start
    # only in the computes' own bootstrap, which waits for this commit. So every such power
    # cycle spent the caller's whole timeout here re-deriving a file the node already had,
    # 120s on each control of QA 10.32.36.10. A missing or different file -- a first
    # bootstrap, a joining control, a new VIP -- still goes to RGW.
    if [ -s $conf ] ; then
        ak=$(awk '$1 == "access_key:" {print $2}' $conf)
        sk=$(awk '$1 == "secret_key:" {print $2}' $conf)
        if [ -n "$ak" -a "x$ak" != "xnull" -a -n "$sk" -a "x$sk" != "xnull" ] && \
           [ "$(_thanos_objstore_conf $bucket $ep $ak $sk)" = "$(cat $conf)" ] ; then
            chown prometheus:prometheus $conf
            chmod 0640 $conf
            return 0
        fi
    fi

    if ! radosgw-admin user info --uid=$uid >/dev/null 2>&1 ; then
        log_info "thanos_objstore_setup: creating native rgw user $uid"
        radosgw-admin user create --uid=$uid --display-name="Thanos object storage" >/dev/null 2>&1
    fi
    ak=$(radosgw-admin user info --uid=$uid 2>/dev/null | jq -r '.keys[0].access_key')
    sk=$(radosgw-admin user info --uid=$uid 2>/dev/null | jq -r '.keys[0].secret_key')
    if [ "x$ak" = "x" -o "x$ak" = "xnull" ] ; then
        log_error "thanos_objstore_setup: no access key for rgw user $uid"
        return 1
    fi

    host=$(echo $ep | cut -d':' -f1)

    if ! /usr/bin/s3cmd --no-ssl --host=$ep --host-bucket=$host \
            --access_key=$ak --secret_key=$sk ls "s3://$bucket" >/dev/null 2>&1 ; then
        log_info "thanos_objstore_setup: creating bucket $bucket"
        /usr/bin/s3cmd --no-ssl --host=$ep --host-bucket=$host \
            --access_key=$ak --secret_key=$sk mb "s3://$bucket" >/dev/null 2>&1
    fi

    mkdir -p /etc/thanos
    # written whole then moved, so a reader never sees a half-written credential file
    _thanos_objstore_conf $bucket $ep $ak $sk > $conf.tmp
    chown prometheus:prometheus $conf.tmp
    chmod 0640 $conf.tmp
    mv -f $conf.tmp $conf
    return 0
}

# thanos_objstore_setup for a node whose thanos units are already running: config_prometheus
# runs this from node_start, after the boot commit started them. Thanos reads its objstore
# config only at start, so a file this rewrote is picked up only by a restart; one that was
# missing needs none, as the units have been exiting and coming back every 5s (Restart=always)
# and start properly once it exists. try-restart leaves a stopped unit stopped.
thanos_objstore_refresh()
{
    local conf=/etc/thanos/objstore.yml
    local before rc

    before=$(md5sum $conf 2>/dev/null)
    thanos_objstore_setup "$@"
    rc=$?
    [ $rc -eq 0 ] || return $rc
    [ -n "$before" ] || return 0
    [ "$(md5sum $conf 2>/dev/null)" = "$before" ] && return 0
    log_info "thanos_objstore_refresh: $conf changed, restarting the thanos units"
    systemctl try-restart thanos-sidecar thanos-store thanos-query
}

# The objstore config thanos reads. One writer for the file and for the fast path's
# check that it is already current, so the two cannot drift apart.
_thanos_objstore_conf()
{
    local bucket=$1 ep=$2 ak=$3 sk=$4
    cat <<EOF
type: S3
config:
  bucket: $bucket
  endpoint: $ep
  access_key: $ak
  secret_key: $sk
  insecure: true
  signature_version2: false
EOF
}
