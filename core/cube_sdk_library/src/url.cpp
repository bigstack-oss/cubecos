// CUBE SDK

#include "url.hpp"

Url::Url(
    const std::string host,
    const std::string path)
    : host(host)
    , path(path)
{
    this->scheme = "http";
    this->rawPath = path;
    this->omitHost = false;
    this->forceQuery = false;
}

Url::Url(const std::string host,
    const std::string path,
    const std::map<std::string, std::string> queryString)
    : host(host)
    , path(path)
{
    this->scheme = "http";
    this->rawPath = path;
    this->omitHost = false;
    this->forceQuery = false;

    std::stringstream q;
    for (std::map<std::string, std::string>::const_iterator it = queryString.begin();
        it != queryString.end();
        it++) {
        if (it->first.empty()) {
            continue;
        }

        q << it->first << "=" << it->second;
    }
    this->rawQuery = q.str();
}

bool isStartsWith(const std::string& s1, const std::string& s2)
{
    return (s1.compare(0, s2.length(), s2) == 0);
}

const std::string
Url::String() const
{
    std::stringstream output;

    if (this->opaque.length() > 0) {
        // handle non HTTP/FTP urls, scheme:opaque[?query][#fragment]

        if (this->scheme.length() > 0) {
            output << this->scheme << ":";
        }

        output << this->opaque;

        if (this->rawQuery.length() > 0) {
            output << "?" << this->rawQuery;
        } else if (this->forceQuery) {
            output << "?";
        }

        if (this->rawFragment.length() > 0) {
            output << "#" << this->rawFragment;
        }
    } else {
        // handle HTTP/FTP urls, [scheme:][//host][/]path[?query][#fragment]
        if (!this->omitHost) {
            if (this->scheme.length() > 0) {
                output << this->scheme << ":";
            }

            if (this->host.length() > 0) {
                output << "//" << this->host;
            }

            if (!isStartsWith(this->path, "/")) {
                output << "/";
            }
            output << this->rawPath;

            if (this->rawQuery.length() > 0) {
                output << "?" << this->rawQuery;
            } else if (this->forceQuery) {
                output << "?";
            }

            if (this->rawFragment.length() > 0) {
                output << "#" << this->rawFragment;
            }
        } else {
            output << this->rawPath;

            if (this->rawQuery.length() > 0) {
                output << "?" << this->rawQuery;
            } else if (this->forceQuery) {
                output << "?";
            }

            if (this->rawFragment.length() > 0) {
                output << "#" << this->rawFragment;
            }
        }
    }

    return output.str();
}
