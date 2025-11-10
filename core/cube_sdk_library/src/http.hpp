// CUBE SDK

#ifndef CUBE_HTTP_H
#define CUBE_HTTP_H

#include "filesystem.hpp"
#include "url.hpp"

#include <hex/log.h>
#include <hex/process_util.h>

struct HttpResponse {
    /**
     * Extra error messages.
     */
    std::string error;
    /**
     * HTTP response status code.
     */
    int statusCode;
    /**
     * Name of the file containing the stdout of the curl command.
     */
    std::string outputFileName;
    /**
     * Name of the file containing the stderr of the curl command.
     */
    std::string errorFileName;

    HttpResponse();
};

/**
 * Clean up temporary files used by the HttpResponse object.
 */
bool CleanupHttpResponse(const HttpResponse& r);

/**
 * Send a HTTP GET request.
 *
 * The deletion of both outputFile and errorFile is the responsibility of the caller function.
 *
 * @return HttpResponse object.
 */
const HttpResponse
HttpGet(const Url& url);

#endif /* endif CUBE_HTTP_H */
