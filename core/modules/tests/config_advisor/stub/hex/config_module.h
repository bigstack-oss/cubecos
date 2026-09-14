// Minimal stand-in for hex/config_module.h. The registration macros become
// plain function pointers the driver can call, which is all the logic test
// needs; the real registration path is covered by test_config_advisor_01.sh
// against a properly linked hex_config.
#pragma once
// The commit hook becomes a pointer the driver can call; the rest of the
// registration is hex's business and there is nothing here to test.
#define CONFIG_MODULE(name, init, parse, validate, prepare, commit) \
    bool (*g_commit_##name)(bool, int) = commit;
#define CONFIG_COMMAND(name, mainf, usagef) int (*g_##name)(int, char **) = mainf;

// Ordering and observation are hex's to honour; the test only needs the
// registration to compile, and the observer's two functions to be callable so
// it can hand the module a role the way hex would.
#define CONFIG_REQUIRES(module, other)
#define CONFIG_OBSERVES(module, other, parse, notify) \
    bool (*g_parse_##module)(const char *, const char *, bool) = parse; \
    void (*g_notify_##module)(bool) = notify;

// Whether hex_config is in its bootstrap pass. The driver answers from the
// environment, so a test can run a commit as a boot or as a settings change.
bool IsBootstrap();

// hex does the copying, so there is no logic in a path registration to test --
// but which paths are registered is the whole of what this module says about
// an upgrade, so each one is recorded for the test to read back.
struct StubMigratePath {
    StubMigratePath(const char *path);
};

#define HEX_STUB_CAT_(a, b) a##b
#define HEX_STUB_CAT(a, b) HEX_STUB_CAT_(a, b)
#define CONFIG_MIGRATE(module, path) \
    static StubMigratePath HEX_STUB_CAT(s_stub_migrate_, __LINE__)(path);
