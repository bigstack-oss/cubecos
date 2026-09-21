// CUBE SDK

#include <hex/test.h>

#include <cluster.hpp>

// Every OpenStack service that talks to RabbitMQ writes its client settings
// through SetMqClientConfig(). These tests pin the exact key set each of the
// fourteen call sites must produce, so a later change to the helper cannot
// silently drop a key for one service -- a loss that stays invisible until the
// broker stops accepting the connection shape that service still uses.
//
// The ssl argument multiplies that shape by two, and the two dimensions are
// independent: TLS is a property of the broker, cluster shape is a property of
// the deployment. The cases below cover both axes because the combination that
// is easiest to get wrong -- non-HA with TLS -- is the one a single-node
// cluster actually runs.

static const char CTRL[] = "10.1.0.1";
static const char PASS[] = "s3cret";
static const char GROUP[] = "10.1.0.1,10.1.0.2,10.1.0.3";

// Deliberately not config[section][key] -- operator[] would create the very
// section an absence check is trying to prove is missing.
static bool
HasSection(Configs& config, const char* section)
{
    return config.find(section) != config.end();
}

static bool
HasKey(Configs& config, const char* section, const char* key)
{
    Configs::iterator s = config.find(section);
    if (s == config.end())
        return false;

    return s->second.find(key) != s->second.end();
}

static size_t
KeyCount(Configs& config, const char* section)
{
    Configs::iterator s = config.find(section);

    return (s == config.end()) ? 0 : s->second.size();
}

int main()
{
    // CASE1: non-HA, plaintext, with the rpc timeout -- what thirteen of the
    // fourteen call sites produce on a single-node cluster. The HA keys must be
    // absent entirely, not present and empty.
    {
        Configs config;
        SetMqClientConfig(config, false, CTRL, PASS, GROUP, false);

        HEX_TEST(config["DEFAULT"]["transport_url"] == RabbitMqServers(false, CTRL, PASS, GROUP, false));
        HEX_TEST(config["DEFAULT"]["rpc_response_timeout"] == "1200");
        HEX_TEST(KeyCount(config, "DEFAULT") == 2);
        HEX_TEST(!HasSection(config, "oslo_messaging_rabbit"));
    }

    // CASE2: HA, plaintext, with the rpc timeout -- the six-key shape. Every
    // key is asserted by value; a wrong value is as broken as a missing one.
    {
        Configs config;
        SetMqClientConfig(config, true, CTRL, PASS, GROUP, false);

        HEX_TEST(config["DEFAULT"]["transport_url"] == RabbitMqServers(true, CTRL, PASS, GROUP, false));
        HEX_TEST(config["DEFAULT"]["rpc_response_timeout"] == "1200");
        HEX_TEST(KeyCount(config, "DEFAULT") == 2);

        HEX_TEST(config["oslo_messaging_rabbit"]["rabbit_retry_interval"] == "1");
        HEX_TEST(config["oslo_messaging_rabbit"]["rabbit_retry_backoff"] == "2");
        HEX_TEST(config["oslo_messaging_rabbit"]["amqp_durable_queues"] == "true");
        HEX_TEST(config["oslo_messaging_rabbit"]["rabbit_ha_queues"] == "true");
        HEX_TEST(KeyCount(config, "oslo_messaging_rabbit") == 4);
    }

    // CASE3: non-HA without the rpc timeout -- neutron's VPN agent, the one
    // call site that has never carried rpc_response_timeout.
    {
        Configs config;
        SetMqClientConfig(config, false, CTRL, PASS, GROUP, false, false);

        HEX_TEST(config["DEFAULT"]["transport_url"] == RabbitMqServers(false, CTRL, PASS, GROUP, false));
        HEX_TEST(!HasKey(config, "DEFAULT", "rpc_response_timeout"));
        HEX_TEST(KeyCount(config, "DEFAULT") == 1);
        HEX_TEST(!HasSection(config, "oslo_messaging_rabbit"));
    }

    // CASE4: HA without the rpc timeout -- the VPN agent on an HA cluster. The
    // HA keys are still written; only rpc_response_timeout is suppressed.
    {
        Configs config;
        SetMqClientConfig(config, true, CTRL, PASS, GROUP, false, false);

        HEX_TEST(config["DEFAULT"]["transport_url"] == RabbitMqServers(true, CTRL, PASS, GROUP, false));
        HEX_TEST(!HasKey(config, "DEFAULT", "rpc_response_timeout"));
        HEX_TEST(KeyCount(config, "DEFAULT") == 1);
        HEX_TEST(KeyCount(config, "oslo_messaging_rabbit") == 4);
    }

    // CASE5: the helper writes nothing outside the two sections it owns, so a
    // service's other managed sections survive it untouched.
    {
        Configs config;
        config["keystone_authtoken"]["auth_type"] = "password";
        SetMqClientConfig(config, true, CTRL, PASS, GROUP, false);

        HEX_TEST(config["keystone_authtoken"]["auth_type"] == "password");
        HEX_TEST(KeyCount(config, "keystone_authtoken") == 1);
        HEX_TEST(config.size() == 3);
    }

    // CASE6: the HA transport_url names every control node, not the VIP. This
    // is the property the certificate work in #1421 depends on.
    {
        Configs config;
        SetMqClientConfig(config, true, CTRL, PASS, GROUP, false);

        const std::string url = config["DEFAULT"]["transport_url"];
        HEX_TEST(url.find("10.1.0.1:5672") != std::string::npos);
        HEX_TEST(url.find("10.1.0.2:5672") != std::string::npos);
        HEX_TEST(url.find("10.1.0.3:5672") != std::string::npos);
    }

    // CASE7: non-HA with TLS. This is the case CASE1 used to forbid outright,
    // and the reason the ssl keys sit outside the HA gate: a single-node
    // cluster pointed at 5671 needs them just as much as a three-node one. The
    // HA keys must still be absent -- turning on TLS must not smuggle in
    // failover settings that have no peer to fail over to.
    {
        Configs config;
        SetMqClientConfig(config, false, CTRL, PASS, GROUP, true);

        HEX_TEST(config["DEFAULT"]["transport_url"] == RabbitMqServers(false, CTRL, PASS, GROUP, true));
        HEX_TEST(config["oslo_messaging_rabbit"]["ssl"] == "true");
        HEX_TEST(config["oslo_messaging_rabbit"]["ssl_ca_file"] == ClusterCaCertFile());
        HEX_TEST(KeyCount(config, "oslo_messaging_rabbit") == 2);

        // Mutual TLS is deferred: the client presents no certificate of its own.
        HEX_TEST(!HasKey(config, "oslo_messaging_rabbit", "ssl_cert_file"));
        HEX_TEST(!HasKey(config, "oslo_messaging_rabbit", "ssl_key_file"));

        // ssl_ca_file is what makes oslo set cert_reqs=CERT_REQUIRED; without
        // it the connection is encrypted but unauthenticated.
        HEX_TEST(!config["oslo_messaging_rabbit"]["ssl_ca_file"].empty());
    }

    // CASE8: HA with TLS -- both axes on, six keys in the section.
    {
        Configs config;
        SetMqClientConfig(config, true, CTRL, PASS, GROUP, true);

        HEX_TEST(config["oslo_messaging_rabbit"]["ssl"] == "true");
        HEX_TEST(config["oslo_messaging_rabbit"]["ssl_ca_file"] == ClusterCaCertFile());
        HEX_TEST(config["oslo_messaging_rabbit"]["rabbit_retry_interval"] == "1");
        HEX_TEST(config["oslo_messaging_rabbit"]["rabbit_retry_backoff"] == "2");
        HEX_TEST(config["oslo_messaging_rabbit"]["amqp_durable_queues"] == "true");
        HEX_TEST(config["oslo_messaging_rabbit"]["rabbit_ha_queues"] == "true");
        HEX_TEST(KeyCount(config, "oslo_messaging_rabbit") == 6);
    }

    // CASE9: ssl selects the port and nothing else. oslo.messaging registers no
    // "rabbit+ssl" driver -- its entry points are amqp/fake/kafka/kombu/rabbit
    // -- so a scheme change here would make every service fail to load its
    // transport. TLS is turned on by the ssl key asserted above, never by the
    // URL.
    {
        const std::string plain = RabbitMqServers(false, CTRL, PASS, GROUP, false);
        const std::string tls = RabbitMqServers(false, CTRL, PASS, GROUP, true);

        HEX_TEST(plain == "rabbit://openstack:s3cret@10.1.0.1:5672");
        HEX_TEST(tls == "rabbit://openstack:s3cret@10.1.0.1:5671");

        const std::string haPlain = RabbitMqServers(true, CTRL, PASS, GROUP, false);
        const std::string haTls = RabbitMqServers(true, CTRL, PASS, GROUP, true);

        HEX_TEST(haPlain.find("10.1.0.1:5672") != std::string::npos);
        HEX_TEST(haPlain.find("10.1.0.3:5672") != std::string::npos);
        HEX_TEST(haTls.find("10.1.0.1:5671") != std::string::npos);
        HEX_TEST(haTls.find("10.1.0.3:5671") != std::string::npos);
        HEX_TEST(haTls.find(":5672") == std::string::npos);
        HEX_TEST(haTls.compare(0, 9, "rabbit://") == 0);
    }

    return HexTestResult;
}
