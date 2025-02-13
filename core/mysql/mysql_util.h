// CUBE SDK

#ifndef MYSQL_UTIL_H
#define MYSQL_UTIL_H

bool MysqlUtilIsDbExist(const char* dbname);
bool MysqlUtilRunSQL(const char* sql);
bool MysqlUtilUpdateDbPass(const char* user, const char* pass);

#endif /* ndef MYSQL_UTIL_H */

