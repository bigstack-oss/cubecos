#
# TEST - config_lachesis renders the agent config and gates on node role
#   compute / control-converged -> rendered + started
#   control / undef             -> not rendered + stopped
#
# SHARED_ID is stubbed to 10.99.99.99 in config_dummies.cpp, so asserting on that
# literal proves the module substituted @CONTROL_VIP@ rather than just running sed.
# Asserts start/stop, not is-enabled: nothing in cubecos is systemd-enabled.
#

CONF=/etc/cube/lachesis/lachesis.yaml

fail() { echo "FAIL: $1"; exit 1; }

run_role() {
    rm -f $CONF
    systemctl stop lachesis >/dev/null 2>&1
    # reset committed settings: CommitCheck short-circuits when the role is
    # unchanged, which looks identical to a broken module
    : > /etc/settings.txt
    cat >/tmp/settings.txt <<EOF
cubesys.role=$1
cubesys.controller=mydomain
cubesys.controller.ip=1.2.3.4
cubesys.control.hosts=node0,node4
cubesys.management=IF.1
net.hostname=node4
EOF
    # non-zero exit is not a failure here: only the module under test is linked
    ./hex_config -vvve commit /tmp/settings.txt >/tmp/commit_$1.log 2>&1 || true
}

# ---- 1. compute: renders + starts ----
run_role compute
[ -f $CONF ] || fail "compute: config was not written"
grep -q "10.99.99.99:9095" $CONF \
    || fail "compute: @CONTROL_VIP@ not substituted with SHARED_ID"
grep -q "@CONTROL_VIP@" $CONF \
    && fail "compute: placeholder survived into the rendered config"
grep -q "credentials_file: /etc/admin-openrc.sh" $CONF \
    || fail "compute: neutron credentials_file missing from rendered config"
[ "$(systemctl is-active lachesis 2>/dev/null)" = "active" ] \
    || fail "compute: service not started (is-active=$(systemctl is-active lachesis 2>&1))"
echo "  ok  compute            -> rendered + started"

# ---- 2. control: no render, stopped ----
run_role control
[ -f $CONF ] && fail "control: config written on a non-compute node"
[ "$(systemctl is-active lachesis 2>/dev/null)" = "active" ] \
    && fail "control: service left running on a non-compute node"
echo "  ok  control            -> not rendered + stopped"

# ---- 3. control-converged: the bitmask case ----
run_role control-converged
[ -f $CONF ] \
    || fail "control-converged: config not written (IsCompute bitmask regression)"
grep -q "10.99.99.99:9095" $CONF || fail "control-converged: VIP not substituted"
[ "$(systemctl is-active lachesis 2>/dev/null)" = "active" ] \
    || fail "control-converged: service not started"
echo "  ok  control-converged  -> rendered + started"

# ---- 4. undef: inert, and no static-init/null-string abort ----
run_role undef
[ -f $CONF ] && fail "undef: config written for an undefined role"
grep -qiE "_M_construct null not valid|Segmentation fault" /tmp/commit_undef.log \
    && fail "undef: hex_config aborted (static-init order?)"
echo "  ok  undef              -> inert, no abort"

echo "config_lachesis: all role cases passed"
