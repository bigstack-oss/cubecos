#!/bin/bash
#
# Unit test for ../modules/sdk_os.sh:
#   os_device_profile_name_for -- must map BOTH model strings the product has
#                                 onto the same Cyborg device profile name.
#
# Why this matters (#818): the name is derived twice, from two unrelated
# sources, and the two must agree or the UI shows a profile name that does not
# exist.
#
#   creation path  cyborg's `model`, via `openstack accelerator device show`
#                  "NVIDIA Corporation GB202GL [RTX PRO 6000 Blackwell Server Edition]"
#   lookup path    hex's own `name`, from gpu_device_list / config.json
#                  "NVIDIA RTX PRO 6000 Blackwell Server Edition"
#
# The lookup path cannot use cyborg's string: a card carved to pgpu takes up to
# one cyborg agent period (periodic_interval, default 60s) to appear in the
# accelerator inventory, so right after the carve it is not there at all.
#
# The expected values below are the golden output of the pre-#818 inline
# derivation in os_device_profile_create (origin/develop at 2026-09-11), so a
# regression here means an existing customer's profile name would change.
#
# Self-contained: extracts just that function, needs no GPU and no Openstack.
#   Run: bash test_device_profile_name.sh
#
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$DIR/../modules/sdk_os.sh"
eval "$(awk '/^os_device_profile_name_for\(\)/{f=1} f{print} f&&/^}/{exit}' "$SRC")"
[ "$(type -t os_device_profile_name_for)" = function ] || { echo "FAIL: function not extracted"; exit 1; }

pass=0 fail=0
ck() { [ "$1" = "$2" ] && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: $3 -> got '$1' want '$2'"; }; }

# --- 1. cyborg's model: golden values from the pre-#818 derivation ------------
ck "$(os_device_profile_name_for 'NVIDIA Corporation GB202GL [RTX PRO 6000 Blackwell Server Edition]')" \
   "rtx_pro_6000_blackwell_server_edition_1" "cyborg model, Blackwell"
ck "$(os_device_profile_name_for 'NVIDIA Corporation GA106 [RTX A2000]')" \
   "rtx_a2000_1" "cyborg model, A2000"
ck "$(os_device_profile_name_for 'NVIDIA Corporation TU104GL [Tesla T4]')" \
   "tesla_t4_1" "cyborg model, T4"

# --- 2. hex's name: must land on the very same string -------------------------
ck "$(os_device_profile_name_for 'NVIDIA RTX PRO 6000 Blackwell Server Edition')" \
   "$(os_device_profile_name_for 'NVIDIA Corporation GB202GL [RTX PRO 6000 Blackwell Server Edition]')" \
   "hex name agrees with cyborg model, Blackwell"
ck "$(os_device_profile_name_for 'NVIDIA RTX A2000')" \
   "$(os_device_profile_name_for 'NVIDIA Corporation GA106 [RTX A2000]')" \
   "hex name agrees with cyborg model, A2000"

# --- 3. units ----------------------------------------------------------------
ck "$(os_device_profile_name_for 'NVIDIA RTX A2000' 4)" "rtx_a2000_4" "units=4"
ck "$(os_device_profile_name_for 'NVIDIA Corporation GA106 [RTX A2000]' 2)" "rtx_a2000_2" "units=2 via cyborg model"

# --- 4. refuses to invent a name ---------------------------------------------
# An empty name would make the caller create/look up a profile literally called
# "_1", which would then be shared by every unnamed card. Fail instead.
os_device_profile_name_for '' >/dev/null 2>&1
ck "$?" "1" "empty input returns non-zero"
os_device_profile_name_for 'NVIDIA Corporation []' >/dev/null 2>&1
ck "$?" "1" "empty brackets return non-zero"

# --- 5. a model with neither brackets nor the NVIDIA prefix --------------------
ck "$(os_device_profile_name_for 'Quadro P400')" "quadro_p400_1" "bare model name"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
