// Minimal stand-in for hex/cli_module.h. CLI_MODE is discarded (its enabled
// expression is never evaluated); CLI_MODE_COMMAND becomes a plain function
// pointer keyed on the handler's own name, which the driver calls directly --
// the real registration path is covered by the CLI test suite against a
// properly linked hex_cli.
#pragma once

// Same values as hex/cli_impl.h.
enum CommandResult {
    CLI_SUCCESS = 0,
    CLI_INVALID_ARGS,
    CLI_UNEXPECTED_ERROR,
    CLI_FAILURE,
};

#define CLI_TOP_MODE "top"
#define CLI_MODE(parent, name, description, isEnabled)
#define CLI_MODE_COMMAND(mode, name, main, completion, description, usage) \
    int (*g_##main)(int, const char**) = main;
