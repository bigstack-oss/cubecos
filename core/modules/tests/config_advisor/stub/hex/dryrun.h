// Minimal stand-in for hex/dryrun.h, with the real barrier's semantics: only a
// full dry run stops the commit.
#pragma once

enum DryRunLevel_e {
    DRYLEVEL_NONE = 0,
    DRYLEVEL_PARTIAL,
    DRYLEVEL_FULL
};

#define HEX_DRYRUN_BARRIER(lvl, ret) do { if (lvl == DRYLEVEL_FULL) return ret; } while (0)
