#!/bin/bash
#
# power_cpu_profile: performance turns deep idle states off and sets the performance
# governor; balanced restores the kernel's idle defaults and schedutil (powersave
# where the driver has no schedutil).
#
#   Run: bash test_power_cpu_profile.sh
#
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
SRC=$(dirname "${BASH_SOURCE[0]}")/../modules/sdk_power.sh
sed -n "/^power_cpu_profile()/,/^}/p" $SRC > $T/fn.sh
source $T/fn.sh
Error(){ echo "ERROR: $*"; exit 1; }   # the SDK's Error exits

pass=0 fail=0
chk(){ # description actual expected
    if [ "$2" = "$3" ] ; then
        pass=$((pass+1)); printf 'PASS %-46s -> %s\n' "$1" "$2"
    else
        fail=$((fail+1)); printf 'FAIL %-46s -> got "%s", want "%s"\n' "$1" "$2" "$3"
    fi
}

# two CPUs with cube4510's idle table: POLL 0us, C1 2us, C1E 10us, C3 40us (kernel default off), C6 133us
CPU_SYSFS=$T/cpu
for c in 0 1 ; do
    mkdir -p $CPU_SYSFS/cpu$c/cpufreq
    echo schedutil > $CPU_SYSFS/cpu$c/cpufreq/scaling_governor
    echo "performance schedutil" > $CPU_SYSFS/cpu$c/cpufreq/scaling_available_governors
    i=0
    for st in "POLL 0 enabled" "C1 2 enabled" "C1E 10 enabled" "C3 40 disabled" "C6 133 enabled" ; do
        set -- $st
        d=$CPU_SYSFS/cpu$c/cpuidle/state$i ; mkdir -p $d
        echo $1 > $d/name ; echo $2 > $d/latency ; echo $3 > $d/default_status
        [ $3 = disabled ] && echo 1 > $d/disable || echo 0 > $d/disable
        i=$((i+1))
    done
done
state(){ cat $CPU_SYSFS/cpu$1/cpuidle/state*/disable | tr -d '\n'; }   # POLL C1 C1E C3 C6
gov(){ cat $CPU_SYSFS/cpu$1/cpufreq/scaling_governor; }

chk "kernel defaults before"                  "$(state 0)" "00010"
power_cpu_profile performance
chk "performance: governor cpu0"              "$(gov 0)" "performance"
chk "performance: governor cpu1"              "$(gov 1)" "performance"
chk "performance: only POLL and C1 left on"   "$(state 0)$(state 1)" "0011100111"
power_cpu_profile performance
chk "performance again is idempotent"         "$(state 0)" "00111"
power_cpu_profile balanced
chk "balanced: governor"                      "$(gov 0)" "schedutil"
chk "balanced: kernel defaults (C3 stays off)" "$(state 0)$(state 1)" "0001000010"
# intel_pstate / amd-pstate active mode: no schedutil
echo "performance powersave" > $CPU_SYSFS/cpu1/cpufreq/scaling_available_governors
power_cpu_profile performance
power_cpu_profile balanced
chk "balanced without schedutil: powersave"   "$(gov 0)$(gov 1)" "schedutilpowersave"
chk "bad profile rejected"                    "$( (power_cpu_profile turbo >/dev/null); echo $?)" "1"
chk "bad profile changes nothing"             "$(state 0)" "00010"

echo "pass=$pass fail=$fail"
[ $fail -eq 0 ]
