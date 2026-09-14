// Dispatches to the commands and the commit hook config_advisor.cpp registers,
// and reads back the paths it registers for migration, so the logic test can
// drive the module the same way hex_config does.
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <cube/systemd_util.h>
#include <hex/config_module.h>
#include <hex/config_tuning.h>

const char *HexLogProgramName() { return "hex_config"; }

// Records what the module decided the service should do, rather than doing it:
// whether the advisor module asks for the agent to run is the thing under test,
// and a real "systemctl stop" on a build host is not. The wording matches what
// the real SystemdCommitService would go on to run.
bool
SystemdCommitService(const bool enabled, const char *name, const bool /*retry*/)
{
    const char *path = getenv("SYSTEMD_COMMIT_LOG");
    if (path) {
        FILE *fp = fopen(path, "a");
        if (fp) {
            fprintf(fp, "%s %s\n", enabled ? "start" : "stop", name);
            fclose(fp);
        }
    }
    return true;
}

// Every path the module registers for migration, in the order it declares them.
// What an upgrade carries across is the whole of this module's answer to it, so
// the test reads the list back rather than trusting the source.
static const char *s_migratePaths[32];
static int s_migratePathCount;

StubMigratePath::StubMigratePath(const char *path)
{
    if (s_migratePathCount < (int)(sizeof(s_migratePaths) / sizeof(s_migratePaths[0])))
        s_migratePaths[s_migratePathCount++] = path;
}

// hex_config's bootstrap pass is what runs on every boot, so a test says which
// kind of commit it is running.
bool
IsBootstrap()
{
    return getenv("HEX_BOOTSTRAP") != NULL;
}

// The tuning the module observes. One slot per index is all this needs -- the
// module under test uses index 1 for cubesys, as production does.
static TuningString *s_tunes[8];

TuningString::TuningString(int idx)
    : changed(false)
{
    if (idx >= 0 && idx < (int)(sizeof(s_tunes) / sizeof(s_tunes[0])))
        s_tunes[idx] = this;
}

TuningString *
TuneAt(int idx)
{
    if (idx < 0 || idx >= (int)(sizeof(s_tunes) / sizeof(s_tunes[0])))
        return NULL;
    return s_tunes[idx];
}

bool
ParseTune(const char * /*name*/, const char *value, bool /*isNew*/, int idx)
{
    TuningString *t = TuneAt(idx);
    if (!t)
        return false;
    t->value = value ? value : "";
    t->changed = true;
    return true;
}

bool
IsModifiedTune(int idx)
{
    TuningString *t = TuneAt(idx);
    return t ? t->changed : false;
}

extern int (*g_advisor_pubkey)(int, char **);
extern int (*g_advisor_verify_release)(int, char **);
extern bool (*g_commit_advisor)(bool, int);
extern bool (*g_parse_advisor)(const char *, const char *, bool);
extern void (*g_notify_advisor)(bool);

int
main(int argc, char **argv)
{
    if (argc < 2)
        return 2;
    if (strcmp(argv[1], "advisor_pubkey") == 0)
        return g_advisor_pubkey(argc - 1, argv + 1);
    if (strcmp(argv[1], "advisor_verify_release") == 0)
        return g_advisor_verify_release(argc - 1, argv + 1);
    // commit [<cubesys.role>] [<dry level>], as hex would call it: the role
    // arrives through the same observer hex uses, so an absent one leaves the
    // module exactly where an unconfigured node leaves it.
    if (strcmp(argv[1], "commit") == 0) {
        if (argc > 2 && argv[2][0]) {
            g_parse_advisor("cubesys.role", argv[2], true);
            g_notify_advisor(true);
        }
        int dryLevel = (argc > 3) ? atoi(argv[3]) : 0;
        return g_commit_advisor(false, dryLevel) ? 0 : 1;
    }
    // The registered migrate paths, in declaration order.
    if (strcmp(argv[1], "migrate_paths") == 0) {
        for (int i = 0; i < s_migratePathCount; ++i)
            printf("%s\n", s_migratePaths[i]);
        return 0;
    }
    return 2;
}
