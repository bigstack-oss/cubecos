// Minimal stand-in for hex/config_tuning.h. The real one reads a settings file
// and drives every module's tunings; all the code under test needs is a string
// it can be handed, a "was it modified" flag, and the two calls it makes.
#pragma once

#include <string>

struct TuningString {
    std::string value;
    bool changed;

    TuningString(int idx);
    operator const std::string&() const { return value; }
    const std::string& newValue() const { return value; }
    bool modified() const { return changed; }
};

// Set by ParseTune, read by IsModifiedTune -- indexed the way the real tuning
// maps are, so a module using index 1 for cubesys behaves as it does in
// production.
TuningString *TuneAt(int idx);
bool ParseTune(const char *name, const char *value, bool isNew, int idx = 0);
bool IsModifiedTune(int idx = 0);

#define CONFIG_TUNING_SPEC_STR(spec)
#define PARSE_TUNING_X_STR(var, spec, idx) static TuningString var(idx)
