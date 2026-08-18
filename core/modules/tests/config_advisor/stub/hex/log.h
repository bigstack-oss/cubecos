// Minimal stand-in for hex/log.h, so config_advisor.cpp can be compiled in
// isolation by test_config_advisor_02.sh. See that script for why.
#pragma once
#include <stdio.h>
#include <stdlib.h>
const char *HexLogProgramName();
#define HexLogError(fmt, ...) do { fprintf(stderr, "syslog: Error: " fmt "\n", ## __VA_ARGS__); } while (0)
