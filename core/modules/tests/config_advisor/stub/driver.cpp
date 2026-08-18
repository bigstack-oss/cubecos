// Dispatches to the commands config_advisor.cpp registers, so the logic test
// can drive them the same way an operator drives hex_config.
#include <string.h>

const char *HexLogProgramName() { return "hex_config"; }

extern int (*g_advisor_pubkey)(int, char **);
extern int (*g_advisor_verify_release)(int, char **);

int
main(int argc, char **argv)
{
    if (argc < 2)
        return 2;
    if (strcmp(argv[1], "advisor_pubkey") == 0)
        return g_advisor_pubkey(argc - 1, argv + 1);
    if (strcmp(argv[1], "advisor_verify_release") == 0)
        return g_advisor_verify_release(argc - 1, argv + 1);
    return 2;
}
