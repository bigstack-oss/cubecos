// Minimal stand-in for hex/process.h. HexSpawn is a real fork/exec in
// cli_driver.cpp, so a test can point HEX_SDK at a fake helper and see
// exactly what cli_advisor.cpp would have run and what it printed.
//
// HEX_SDK itself is supplied by the test script's compile line (-DHEX_SDK=...)
// rather than fixed here, since each test run needs it to name that run's own
// fake helper.
#pragma once

int HexSpawn(int timeout, const char *arg0, ...);
