// CUBE SDK

#include <stdlib.h>
#include <string.h>

char *s_env = 0;
const char* s_openstack = "/usr/bin/openstack";

// Free s_programName to avoid errors from valgrind
static void __attribute__ ((destructor))
Fini()
{
    if (s_env)
        free(s_env);
}

void OpenstackInit(const char* env)
{
    if (s_env)
        free(s_env);

    s_env = strdup(env);
}

