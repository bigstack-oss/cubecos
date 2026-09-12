// Dispatches to the commands cli_advisor.cpp registers, so the logic test can
// drive them the same way an operator drives hex_cli, plus real
// implementations of the handful of hex_cli/hex_sdk helpers cli_advisor.cpp
// calls -- enough to run the code under test, not to re-implement the CLI.
#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include <sys/wait.h>
#include <unistd.h>

typedef std::vector<std::string> CliList;

// Runs arg0 with the given argv (NULL-terminated, as HexSpawn's callers write
// it) and returns its raw wait status -- same shape as the real HexSpawn, so
// a "!= 0 means it failed" check behaves the same here as it would in
// production.
int
HexSpawn(int /*timeout*/, const char *arg0, ...)
{
    std::vector<char*> argv;
    argv.push_back(const_cast<char*>(arg0));

    va_list ap;
    va_start(ap, arg0);
    for (;;) {
        char *a = va_arg(ap, char*);
        argv.push_back(a);
        if (!a)
            break;
    }
    va_end(ap);

    pid_t pid = fork();
    if (pid < 0)
        return -1;
    if (pid == 0) {
        execv(arg0, argv.data());
        _exit(127);
    }
    int status = 0;
    while (waitpid(pid, &status, 0) == -1 && errno == EINTR)
        ;
    return status;
}

void
CliPrintf(const char *format, ...)
{
    va_list ap;
    va_start(ap, format);
    vprintf(format, ap);
    va_end(ap);
    printf("\n");
}

// Not exercised by any command under test here (only EnrollMain reads a
// prompt), so a fixed "no input" answer is enough to let the file link.
bool
CliReadLine(const char * /*prompt*/, std::string & /*line*/)
{
    return false;
}

bool
CliReadInputStr(int argc, const char **argv, int argidx,
                const char * /*msg*/, std::string *val)
{
    if (argidx >= argc)
        return false;
    *val = argv[argidx];
    return true;
}

int
CliPopulateList(CliList &list, const char *cmd)
{
    list.clear();
    FILE *fp = popen(cmd, "r");
    if (!fp)
        return -1;

    char buf[4096];
    while (fgets(buf, sizeof(buf), fp)) {
        std::string line(buf);
        while (!line.empty() && (line.back() == '\n' || line.back() == '\r'))
            line.pop_back();
        list.push_back(line);
    }

    int status = pclose(fp);
    if (status == -1)
        return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

extern int (*g_TargetsMain)(int, const char**);
extern int (*g_TargetSetMain)(int, const char**);
extern int (*g_TargetUnsetMain)(int, const char**);
extern int (*g_StatusMain)(int, const char**);

int
main(int argc, char **argv)
{
    if (argc < 2)
        return 2;

    // argv[1] onward becomes the command's own argv, argv[0] being the
    // command word -- the same shape hex_cli hands to a Main function.
    const char **subArgv = const_cast<const char**>(argv + 1);
    int subArgc = argc - 1;

    if (strcmp(argv[1], "targets") == 0)
        return g_TargetsMain(subArgc, subArgv);
    if (strcmp(argv[1], "target_set") == 0)
        return g_TargetSetMain(subArgc, subArgv);
    if (strcmp(argv[1], "target_unset") == 0)
        return g_TargetUnsetMain(subArgc, subArgv);
    if (strcmp(argv[1], "status") == 0)
        return g_StatusMain(subArgc, subArgv);
    return 2;
}
