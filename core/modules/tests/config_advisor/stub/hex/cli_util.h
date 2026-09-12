// Minimal stand-in for hex/cli_util.h -- just the calls cli_advisor.cpp makes.
// Definitions live in cli_driver.cpp.
#pragma once
#include <string>
#include <vector>

typedef std::vector<std::string> CliList;

bool CliReadLine(const char *prompt, std::string& line);
bool CliReadInputStr(int argc, const char** argv, int argidx,
                     const char* msg, std::string* val);
void CliPrintf(const char* format, ...);
int CliPopulateList(CliList& list, const char *cmd);
