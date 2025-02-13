#ifndef CLI_NTP_H
#define CLI_NTP_H

#include <hex/parse.h>
#include <hex/string_util.h>
#include <hex/cli_util.h>

static const char* LABEL_CONFIG_SERVER = "Enter the new NTP server: ";
static const char* MSG_INVALID_SERVER = "The value entered, %s, is not a valid server.";

class CliNtpChanger {
public:
    bool configure(std::string *server)
    {
        if (!CliReadLine(LABEL_CONFIG_SERVER, *server)) {
            return false;
        }
        return validate(*server);
    }

    bool validate(const std::string &server)
    {
        bool result = true;

        if (server.length() < 1 || server.length() > 255) {
            result = false;
        }
        else {
            // They are composed of labels, separated by '.' characters
            std::vector<std::string> domains = hex_string_util::split(server, '.');
            for (unsigned int idx = 0; idx < domains.size(); ++idx) {
                // The labels have their own validity requirements
                if (!validateServerDomain(domains[idx])) {
                    result = false;
                    break;
                }
            }
        }

        if (!result) {
            CliPrintf(MSG_INVALID_SERVER, server.c_str());
        }

        return result;
    }

private:
    bool validateServerDomain(const std::string &domain)
    {
        // domain cannot be empty and cannot be more than 63 characters
        if (domain.size() < 1 || domain.size() > 63) {
            return false;
        }

        // Valid characters are a-z, A-Z, 0-9 and '-'
        // Note: MS also allows '_' but the standards disallow it, so we'll disallow it too.
        std::string validCharacters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-";
        if (domain.find_first_not_of(validCharacters) != std::string::npos) {
            return false;
        }

        // The first character in a domain cannot be '-'
        if (domain[0] == '-') {
            return false;
        }

        return true;
    }
};

#endif /* endif CLI_NTP_H */

