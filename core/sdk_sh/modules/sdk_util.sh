# CUBE SDK

# PROG must be set before sourcing this file
if [ -z "$PROG" ] ; then
    echo "Error: PROG not set" >&2
    exit 1
fi

util_url_download()
{
    local url=$1
    local local_dir=$2
    local timeout=${3:-60}

    Quiet -n $WGET -q --no-check-certificate $url -P $local_dir
}

CRONTAB_IN_ACTION="/run/crontab_in_action.lock"

util_cron_cleanup_job()
{
    # clean up jobs with a specific feature
    local job_feature="$1"
    if [ -z "$job_feature" ] ; then
        return 0
    fi

    local jobs=""
    local filtered_jobs=""

    (
        # use flock to prevent race conditions
        flock -x -w 10 200 || {
            log_error "crontab lock timeout"
            return 1
        }

        jobs="$(MakeTemp)"
        crontab -l > "$jobs"
        filtered_jobs="$(MakeTemp)"
        grep -v "$job_feature" "$jobs" > "$filtered_jobs"
        rm -f "$jobs"
        crontab "$filtered_jobs"
        rm -f "$filtered_jobs"
    ) 200>"$CRONTAB_IN_ACTION"
}

util_cron_add_job()
{
    # add a job schedule
    local job="$1"
    if [ -z "$job" ] ; then
        return 0
    fi

    local jobs=""

    (
        # use flock to prevent race conditions
        flock -x -w 10 200 || {
            log_error "crontab lock timeout"
            return 1
        }

        jobs="$(MakeTemp)"
        crontab -l > "$jobs"
        echo "$job" >> "$jobs"
        crontab "$jobs"
        rm -f "$jobs"
    ) 200>"$CRONTAB_IN_ACTION"
}
