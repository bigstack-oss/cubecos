// Minimal stand-in for hex/process.h. HexSpawn is a real fork/exec in
// cli_driver.cpp, so a test can point HEX_SDK at a fake helper and see
// exactly what cli_advisor.cpp would have run and what it printed.
//
// HEX_SDK itself is supplied by the test script's compile line (-DHEX_SDK=...)
// rather than fixed here, since each test run needs it to name that run's own
// fake helper.
#pragma once

// The real header defines this; a test that needs its own helper overrides it
// on the compile line.
#ifndef HEX_SDK
#define HEX_SDK "/usr/sbin/hex_sdk"
#endif

int HexSpawn(int timeout, const char *arg0, ...);
int HexSystemF(int timeout, const char *fmt, ...) __attribute__ ((format (printf, 2, 3)));
