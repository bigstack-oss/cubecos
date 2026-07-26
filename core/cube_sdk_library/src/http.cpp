// CUBE SDK

#include "http.hpp"

HttpResponse::HttpResponse()
    : error("")
    , statusCode(0)
    , outputFileName("")
    , errorFileName("")
{
}

bool isHttpResponseSuccessful(const HttpResponse& r)
{
    return (r.statusCode >= 200 && r.statusCode <= 299);
}

bool CleanupHttpResponse(const HttpResponse& r)
{
    bool ret1 = DeleteFile(r.outputFileName);
    bool ret2 = DeleteFile(r.errorFileName);

    return ret1 && ret2;
}

/**
 * Prepare temporary files for HTTP requests.
 */
static bool
prepareTempFiles(
    std::string& error,
    TempFile& statusCodeFile,
    TempFile& outputFile,
    TempFile& errorFile)
{
    statusCodeFile = CreateTempFile();
    if (!statusCodeFile.isValid) {
        error = "failed to create a temporary file";
        HexLogError("%s", error.c_str());
        return false;
    }
    CloseTempFileFd(statusCodeFile);

    outputFile = CreateTempFile();
    if (!outputFile.isValid) {
        error = "failed to create a temporary file";
        HexLogError("%s", error.c_str());
        return false;
    }
    CloseTempFileFd(outputFile);

    errorFile = CreateTempFile();
    if (!errorFile.isValid) {
        error = "failed to create a temporary file";
        HexLogError("%s", error.c_str());
        return false;
    }
    CloseTempFileFd(errorFile);

    return true;
}

/**
 * Parse the status code from the status code file.
 *
 * @return HTTP status code. If failed, 0.
 */
static int
parseStatusCode(
    std::string& error,
    const TempFile& statusCodeFile)
{
    std::string fsError;
    const std::string statusCodeString = ReadFile(fsError, statusCodeFile.fileName);
    if (fsError.length() > 0) {
        error = "failed to parse the HTTP status code of the response";
        HexLogError("%s", error.c_str());
        return 0;
    }

    int statusCode = 0;
    try {
        std::size_t pos;
        statusCode = std::stoi(statusCodeString, &pos);
    } catch (const std::exception& e) {
        // failed to convert the output string to an integer
        error = "failed to parse the HTTP status code of the response";
        HexLogError("%s", error.c_str());
        return 0;
    }

    return statusCode;
}

const HttpResponse
DoHttp(const HttpRequest& req)
{
    HttpResponse res = HttpResponse();

    // request temporary files for status code, stdout, and stderr
    TempFile statusCodeFile, outputFile, errorFile;
    std::string tmpError;
    if (!prepareTempFiles(tmpError, statusCodeFile, outputFile, errorFile)) {
        res.error = tmpError;
        return res;
    }

    // form the header string
    std::stringstream headerString;
    bool isFirst = true;
    for (std::map<std::string, std::string>::const_iterator it = req.header.begin();
        it != req.header.end();
        it++) {
        if (it->first.empty()) {
            continue;
        }

        if (isFirst) {
            isFirst = false;
        } else {
            headerString << " ";
        }

        headerString << "-H \"" << it->first << ": " << it->second << "\"";
    }

    // form the body string
    std::string bodyString;
    if (!req.body.empty()) {
        bodyString = "-d '" + req.body + "'";
    }

    // form the time-bound string; empty keeps curl's default (unbounded)
    std::stringstream timeoutString;
    if (req.connectTimeoutSecs > 0) {
        timeoutString << "--connect-timeout " << req.connectTimeoutSecs << " ";
    }
    if (req.maxTimeSecs > 0) {
        timeoutString << "--max-time " << req.maxTimeSecs << " ";
    }

    // send the request via curl
    bool isCurlSuccessful = false;
    if (req.url.scheme == "http") {
        isCurlSuccessful = HexUtilSystemF(
                               0,
                               0,
                               "curl --silent --show-error %s"
                               "--output %s --write-out \"%%{http_code}\" "
                               "--request %s \"%s\" "
                               "%s %s >%s 2>%s",
                               timeoutString.str().c_str(),
                               outputFile.fileName.c_str(),
                               req.method.c_str(),
                               req.url.String().c_str(),
                               headerString.str().c_str(),
                               bodyString.c_str(),
                               statusCodeFile.fileName.c_str(),
                               errorFile.fileName.c_str())
            == 0;
    } else if (req.url.scheme == "https") {
        isCurlSuccessful = HexUtilSystemF(
                               0,
                               0,
                               "curl --insecure --silent --show-error %s"
                               "--output %s --write-out \"%%{http_code}\" "
                               "--request %s \"%s\" "
                               "%s %s >%s 2>%s",
                               timeoutString.str().c_str(),
                               outputFile.fileName.c_str(),
                               req.method.c_str(),
                               req.url.String().c_str(),
                               headerString.str().c_str(),
                               bodyString.c_str(),
                               statusCodeFile.fileName.c_str(),
                               errorFile.fileName.c_str())
            == 0;
    } else {
        res.error = "the url scheme is not supported";
        HexLogError("%s", res.error.c_str());

        DeleteTempFile(statusCodeFile);
        DeleteTempFile(outputFile);
        DeleteTempFile(errorFile);
        return res;
    }

    res.outputFileName = outputFile.fileName;
    res.errorFileName = errorFile.fileName;

    if (!isCurlSuccessful) {
        res.error = "curl is not successful";
        HexLogError("%s", res.error.c_str());

        DeleteTempFile(statusCodeFile);
        return res;
    }

    // parse the status code
    std::string parseStatusCodeError;
    res.statusCode = parseStatusCode(parseStatusCodeError, statusCodeFile);
    if (parseStatusCodeError.length() > 0) {
        res.error = parseStatusCodeError;
    }
    DeleteTempFile(statusCodeFile);

    // return the HttpResponse object
    return res;
}

const HttpResponse
GetHttp(const HttpRequest& req)
{
    HttpRequest getReq = req;
    getReq.method = "GET";

    return DoHttp(getReq);
}

const HttpResponse
PostFormHttp(const Url& url, const std::vector<std::string> formBody)
{
    HttpResponse r = HttpResponse();

    TempFile statusCodeFile, outputFile, errorFile;
    std::string tmpError;
    if (!prepareTempFiles(tmpError, statusCodeFile, outputFile, errorFile)) {
        r.error = tmpError;
        return r;
    }

    // form the body string
    std::stringstream bodyString;
    bool isFirst = true;
    for (std::vector<std::string>::const_iterator it = formBody.begin(); it != formBody.end(); it++) {
        if (it->empty()) {
            continue;
        }

        if (isFirst) {
            isFirst = false;
        } else {
            bodyString << " ";
        }

        bodyString << "-d \"" << *it << "\"";
    }

    // send the request via curl
    bool isCurlSuccessful = false;
    if (url.scheme == "http") {
        isCurlSuccessful = HexUtilSystemF(
                               0,
                               0,
                               "curl --silent --show-error "
                               "--output %s --write-out \"%%{http_code}\" "
                               "--request POST \"%s\" "
                               "--header \"Content-Type: application/x-www-form-urlencoded\" %s "
                               ">%s 2>%s",
                               outputFile.fileName.c_str(),
                               url.String().c_str(),
                               bodyString.str().c_str(),
                               statusCodeFile.fileName.c_str(),
                               errorFile.fileName.c_str())
            == 0;
    } else if (url.scheme == "https") {
        isCurlSuccessful = HexUtilSystemF(
                               0,
                               0,
                               "curl --insecure --silent --show-error "
                               "--output %s --write-out \"%%{http_code}\" "
                               "--request POST \"%s\" "
                               "--header \"Content-Type: application/x-www-form-urlencoded\" %s "
                               ">%s 2>%s",
                               outputFile.fileName.c_str(),
                               url.String().c_str(),
                               bodyString.str().c_str(),
                               statusCodeFile.fileName.c_str(),
                               errorFile.fileName.c_str())
            == 0;
    } else {
        r.error = "the url scheme is not supported";
        HexLogError("%s", r.error.c_str());

        DeleteTempFile(statusCodeFile);
        DeleteTempFile(outputFile);
        DeleteTempFile(errorFile);
        return r;
    }

    r.outputFileName = outputFile.fileName;
    r.errorFileName = errorFile.fileName;

    if (!isCurlSuccessful) {
        r.error = "curl is not successful";
        HexLogError("%s", r.error.c_str());

        DeleteTempFile(statusCodeFile);
        return r;
    }

    // parse the status code
    std::string parseStatusCodeError;
    r.statusCode = parseStatusCode(parseStatusCodeError, statusCodeFile);
    if (parseStatusCodeError.length() > 0) {
        r.error = parseStatusCodeError;
    }
    DeleteTempFile(statusCodeFile);

    // return the HttpResponse object
    return r;
}
