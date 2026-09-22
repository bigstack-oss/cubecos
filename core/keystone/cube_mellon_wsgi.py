# Cube SDK
"""Put mod_auth_mellon's SAML assertion back into keystone's WSGI environ.

mellon publishes the assertion as httpd environment variables -- MELLON_IDP,
MELLON_username, MELLON_groups. Those reach the application only while httpd hosts
it in process, which stopped being true when keystone moved to gunicorn behind
ProxyPass: mod_proxy forwards headers, not httpd's request environment. Federated
login therefore arrived at keystone carrying no assertion at all, and every WebSSO
attempt -- horizon's "Cube Account" button and skyline's alike -- failed with a
bare 401 while keystone logged only "Authorization failed".

v3_mellon_keycloak_master.conf carries the three values across the socket as
X-Mellon-* request headers instead, and this shim restores the environ keys
keystone looks for: federation.utils.get_assertion_params_from_env() harvests them
out of flask.request.environ, and CONF.federation.remote_id_attribute names
MELLON_IDP.

Only these headers are honoured, and that same config unsets all of them at server
scope before mellon repopulates them, so a client cannot present its own.
"""

import keystone.conf
from keystone.server import wsgi as keystone_wsgi

# Advisor console origins to trust for WebSSO, one URL per line, written by
# config_advisor.cpp from what the node was told at enrolment. Absent on a node
# that was never enrolled, which is why nothing here treats that as an error.
_ADVISOR_ORIGINS = '/etc/keystone/cube-advisor-origins'

# Exactly what idp_mapping_rules.json and remote_id_attribute consume, no more:
# this is a header channel into an authentication decision, so it stays minimal.
# Adding a remote attribute to the mapping means adding it here *and* in
# v3_mellon_keycloak_master.conf.def -- httpd cannot forward the set generically.
#
# X-Mellon-Groups arrives ";"-merged, courtesy of MellonMergeEnvVars, which is the
# form the mapping's any_one_of rules already expect.
_ASSERTION_HEADERS = {
    'HTTP_X_MELLON_IDP': 'MELLON_IDP',
    'HTTP_X_MELLON_USERNAME': 'MELLON_username',
    'HTTP_X_MELLON_GROUPS': 'MELLON_groups',
}

def _trust_advisor_origins():
    """Add the Advisor's console origins to keystone's trusted_dashboard list.

    Skyline's WebSSO callback runs on the Advisor's virtual origin, not on the
    cluster address keystone.conf names, so keystone refuses the assertion
    unless that origin is trusted too. It cannot go in keystone.conf:
    config_keystone.cpp owns [federation] and rewrites it on every commit,
    while this list is enrolment-time knowledge that changes without keystone
    changing.

    Once, at import, rather than per request: set_override on a live CONF from
    a request handler is a write every worker thread shares.
    """
    try:
        with open(_ADVISOR_ORIGINS) as f:
            extra = [line.strip() for line in f
                     if line.strip() and not line.startswith('#')]
    except OSError:
        return
    if not extra:
        return
    conf = keystone.conf.CONF
    conf.set_override('trusted_dashboard',
                      list(conf.federation.trusted_dashboard) + extra,
                      group='federation')


_application = keystone_wsgi.initialize_public_application()
# After initialize_public_application: that call is what configures CONF.
_trust_advisor_origins()


def application(environ, start_response):
    for header, key in _ASSERTION_HEADERS.items():
        # pop rather than copy: get_assertion_params_from_env() yields every environ
        # key, because assertion_prefix is empty, and the mapping engine should see
        # the MELLON_* name it was written against and not two spellings of it.
        value = environ.pop(header, None)
        if value:
            environ[key] = value
    return _application(environ, start_response)
