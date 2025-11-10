// CUBE SDK

#ifndef CUBE_HTTP_H
#define CUBE_HTTP_H

#include "filesystem.hpp"
#include "url.hpp"

#include <hex/log.h>
#include <hex/process_util.h>

struct HttpRequest {
    std::string method;
    Url url;
    std::map<std::string, std::string> header;
    std::string body;
};

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
 * Check if the HTTP response status code is 200 ~ 299.
 */
bool isHttpResponseSuccessful(const HttpResponse& r);

/**
 * Clean up temporary files used by the HttpResponse object.
 */
bool CleanupHttpResponse(const HttpResponse& r);

/**
 * Send an HTTP request.
 *
 * The deletion of both outputFile and errorFile is the responsibility of the caller function.
 *
 * @return HttpResponse object.
 */
const HttpResponse
DoHttp(const HttpRequest& req);

/**
 * Send an HTTP GET request.
 *
 * The deletion of both outputFile and errorFile is the responsibility of the caller function.
 *
 * @return HttpResponse object.
 */
const HttpResponse
GetHttp(const HttpRequest& req);

/**
 * Send an HTTP POST request with a form body.
 *
 * The deletion of both outputFile and errorFile is the responsibility of the caller function.
 *
 * @return HttpResponse object.
 */
const HttpResponse
PostFormHttp(const Url& url, const std::vector<std::string> formBody);

#endif /* endif CUBE_HTTP_H */
