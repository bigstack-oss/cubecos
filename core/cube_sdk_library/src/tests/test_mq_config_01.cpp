// CUBE SDK

#include <hex/test.h>

#include <cluster.hpp>

// Every OpenStack service that talks to RabbitMQ writes its client settings
// through SetMqClientConfig(). These tests pin the exact key set each of the
// fourteen call sites must produce, so a later change to the helper cannot
// silently drop a key for one service -- a loss that stays invisible until the
// broker stops accepting the connection shape that service still uses.

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
    // CASE1: non-HA with the rpc timeout -- what thirteen of the fourteen call
    // sites produce on a single-node cluster. The HA keys must be absent
    // entirely, not present and empty.
    {
        Configs config;
        SetMqClientConfig(config, false, CTRL, PASS, GROUP);

        HEX_TEST(config["DEFAULT"]["transport_url"] == RabbitMqServers(false, CTRL, PASS, GROUP));
        HEX_TEST(config["DEFAULT"]["rpc_response_timeout"] == "1200");
        HEX_TEST(KeyCount(config, "DEFAULT") == 2);
        HEX_TEST(!HasSection(config, "oslo_messaging_rabbit"));
    }

    // CASE2: HA with the rpc timeout -- the six-key shape. Every key is
    // asserted by value; a wrong value is as broken as a missing one.
    {
        Configs config;
        SetMqClientConfig(config, true, CTRL, PASS, GROUP);

        HEX_TEST(config["DEFAULT"]["transport_url"] == RabbitMqServers(true, CTRL, PASS, GROUP));
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
        SetMqClientConfig(config, false, CTRL, PASS, GROUP, false);

        HEX_TEST(config["DEFAULT"]["transport_url"] == RabbitMqServers(false, CTRL, PASS, GROUP));
        HEX_TEST(!HasKey(config, "DEFAULT", "rpc_response_timeout"));
        HEX_TEST(KeyCount(config, "DEFAULT") == 1);
        HEX_TEST(!HasSection(config, "oslo_messaging_rabbit"));
    }

    // CASE4: HA without the rpc timeout -- the VPN agent on an HA cluster. The
    // HA keys are still written; only rpc_response_timeout is suppressed.
    {
        Configs config;
        SetMqClientConfig(config, true, CTRL, PASS, GROUP, false);

        HEX_TEST(config["DEFAULT"]["transport_url"] == RabbitMqServers(true, CTRL, PASS, GROUP));
        HEX_TEST(!HasKey(config, "DEFAULT", "rpc_response_timeout"));
        HEX_TEST(KeyCount(config, "DEFAULT") == 1);
        HEX_TEST(KeyCount(config, "oslo_messaging_rabbit") == 4);
    }

    // CASE5: the helper writes nothing outside the two sections it owns, so a
    // service's other managed sections survive it untouched.
    {
        Configs config;
        config["keystone_authtoken"]["auth_type"] = "password";
        SetMqClientConfig(config, true, CTRL, PASS, GROUP);

        HEX_TEST(config["keystone_authtoken"]["auth_type"] == "password");
        HEX_TEST(KeyCount(config, "keystone_authtoken") == 1);
        HEX_TEST(config.size() == 3);
    }

    // CASE6: the HA transport_url names every control node, not the VIP. This
    // is the property the certificate work in #1421 depends on.
    {
        Configs config;
        SetMqClientConfig(config, true, CTRL, PASS, GROUP);

        const std::string url = config["DEFAULT"]["transport_url"];
        HEX_TEST(url.find("10.1.0.1:5672") != std::string::npos);
        HEX_TEST(url.find("10.1.0.2:5672") != std::string::npos);
        HEX_TEST(url.find("10.1.0.3:5672") != std::string::npos);
    }

    return HexTestResult;
}
