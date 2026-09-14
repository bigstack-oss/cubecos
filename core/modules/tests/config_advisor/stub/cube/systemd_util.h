// Minimal stand-in for cube/systemd_util.h. The real one stops and then starts
// a service; driver.cpp records the decision instead, which is what the module
// under test is responsible for.
#pragma once

bool SystemdCommitService(const bool enabled, const char *name, const bool retry = false);
