// CUBE SDK

#include <string>
#include <string.h>

#include <hex/log.h>
#include <hex/process.h>

//FIXME: change to use mysql C library
const static char MYSQL[] = "/usr/bin/mysql";

bool
MysqlUtilIsDbExist(const char* dbname)
{
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "%s -sNe \""
                               "SELECT schema_name "
                               "FROM information_schema.schemata "
                               "WHERE schema_name = '%s'\"", MYSQL, dbname);
    std::string out;
    int rc = -1;

    if (!(HexRunCommand(rc, out, cmd) && rc == 0)) {
        HexLogError("failed to check db exist via %s", cmd);
        return false;
    }

    if (strncmp(dbname, out.c_str(), strlen(dbname)) != 0) {
        HexLogDebug("db %s does not exist", dbname);
        return false;
    }

    return true;
}

bool
MysqlUtilRunSQL(const char* sql)
{
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "%s -sNe \"%s\"", MYSQL, sql);
    std::string out;
    int rc = -1;

    if (!(HexRunCommand(rc, out, cmd) && rc == 0)) {
        HexLogError("failed to run %s", cmd);
        return false;
    }

    return true;
}

bool
MysqlUtilUpdateDbPass(const char* user, const char* pass)
{
    HexLogInfo("Updating %s database password", user);

    char sqla[256], sqlb[256];
    snprintf(sqla, sizeof(sqla),
             "SET PASSWORD FOR '%s'@'localhost' = PASSWORD('%s');",
             user, pass);
    snprintf(sqlb, sizeof(sqlb),
             "SET PASSWORD FOR '%s'@'%%' = PASSWORD('%s');",
             user, pass);
    if (!MysqlUtilRunSQL(sqla) || !MysqlUtilRunSQL(sqlb) || !MysqlUtilRunSQL("FLUSH PRIVILEGES")) {
        HexLogError("failed to update %s database password", user);
        return false;
    }

    return true;
}

