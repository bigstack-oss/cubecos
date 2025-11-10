// CUBE SDK

#ifndef CUBE_URL_H
#define CUBE_URL_H

#include <map>
#include <sstream>
#include <string>

/**
 * The URL object type.
 *
 * Some limitations:
 * - Do not support user info.
 * - Do not support URI encoding.
 * - Only support HTTP URL object.
 */
class Url {
public:
    std::string scheme;
    /**
     * encoded opaque data
     */
    std::string opaque;
    /**
     * host or host:port
     */
    std::string host;
    /**
     * path (relative paths may omit leading slash)
     */
    std::string path;
    /**
     * encoded path hint
     */
    std::string rawPath;
    /**
     * do not emit empty host (authority)
     */
    bool omitHost;
    /**
     * append a query ('?') even if RawQuery is empty
     */
    bool forceQuery;
    /**
     * encoded query values, without '?'
     */
    std::string rawQuery;
    /**
     * fragment for references, without '#'
     */
    std::string fragment;
    /**
     * encoded fragment hint
     */
    std::string rawFragment;

    /**
     * Construct an HTTP URL object.
     */
    Url(const std::string host, const std::string path);
    /**
     * Construct an HTTP URL object with a query string.
     */
    Url(const std::string host,
        const std::string path,
        const std::map<std::string, std::string> queryString);
    /**
     * Generate a full URL string.
     */
    const std::string String() const;
};

#endif /* endif CUBE_URL_H */
