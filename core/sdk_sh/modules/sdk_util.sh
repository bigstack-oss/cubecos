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
        grep -v -F "$job_feature" "$jobs" > "$filtered_jobs"
        rm -f "$jobs"
        crontab "$filtered_jobs"
        rm -f "$filtered_jobs"
    ) 200>"$CRONTAB_IN_ACTION"
}

util_cron_add_job()
{
    # add a job schedule
    local job="$1"
    # ensure job_feature to be unique in the cron file
    # skip adding if not unique
    # do not check if empty
    local job_feature="$2"
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

        if [ -n "$job_feature" ] ; then
            if grep -q -F "$job_feature" "$jobs" ; then
                log_info "job ${job} has duplicated job feature ${job_feature} in the cron file, skip adding"
                rm -f "$jobs"
                return 0
            fi
        fi

        echo "$job" >> "$jobs"
        crontab "$jobs"
        rm -f "$jobs"
    ) 200>"$CRONTAB_IN_ACTION"
}

CRON_EVERY_MINUTE_JOBS="/etc/cube/cos/cron/every_minute_jobs.sh"
CRON_EVERY_MINUTE_JOBS_IN_ACTION="/run/every_minute_jobs.lock"

util_cron_run_every_minute_jobs()
{
    # deregister itself if has nothing to run
    if [ ! -f "$CRON_EVERY_MINUTE_JOBS" ] ; then
        util_cron_cleanup_job "$HEX_SDK util_cron_run_every_minute_jobs"
        return 0
    fi
    if [ "$(cat "$CRON_EVERY_MINUTE_JOBS" | tr -d '[:space:]' | wc -m)" -eq 0 ] ; then
        util_cron_cleanup_job "$HEX_SDK util_cron_run_every_minute_jobs"
        return 0
    fi

    # run jobs
    /usr/bin/bash "$CRON_EVERY_MINUTE_JOBS"
}

util_cron_add_every_minute_job()
{
    # add an every minute job
    local job="$1"
    # ensure job_feature to be unique in the every minute job file
    # skip adding if not unique
    # do not check if empty
    local job_feature="$2"
    if [ -z "$job" ] ; then
        return 0
    fi

    (
        # use flock to prevent race conditions
        flock -x -w 10 200 || {
            log_error "every minute job lock timeout"
            return 1
        }

        if [ -n "$job_feature" ] && [ -f "$CRON_EVERY_MINUTE_JOBS" ] ; then
            if grep -q -F "$job_feature" "$CRON_EVERY_MINUTE_JOBS" ; then
                log_info "every minute job ${job} has duplicated job feature ${job_feature} in ${CRON_EVERY_MINUTE_JOBS}, skip adding"
                return 0
            fi
        fi

        echo "$job" >> "$CRON_EVERY_MINUTE_JOBS"
        util_cron_add_job \
            "* * * * * $HEX_SDK util_cron_run_every_minute_jobs" \
            "$HEX_SDK util_cron_run_every_minute_jobs"
    ) 200>"$CRON_EVERY_MINUTE_JOBS_IN_ACTION"
}

util_cron_delete_every_minute_job()
{
    # delete every minute jobs with a specific feature
    local job_feature="$1"
    if [ -z "$job_feature" ] ; then
        return 0
    fi

    local current_cron_every_minute_jobs=""

    (
        # use flock to prevent race conditions
        flock -x -w 10 200 || {
            log_error "every minute job lock timeout"
            return 1
        }

        if [ -f "$CRON_EVERY_MINUTE_JOBS" ] ; then
            if ! grep -q -F "$job_feature" "$CRON_EVERY_MINUTE_JOBS" ; then
                # the job feature does not exist
                return 0
            fi
        fi

        current_cron_every_minute_jobs="$(MakeTemp)"
        cp -f "$CRON_EVERY_MINUTE_JOBS" "$current_cron_every_minute_jobs"
        grep -v -F "$job_feature" "$current_cron_every_minute_jobs" > "$CRON_EVERY_MINUTE_JOBS"
        rm -f "$current_cron_every_minute_jobs"
    ) 200>"$CRON_EVERY_MINUTE_JOBS_IN_ACTION"
}
