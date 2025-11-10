// CUBE SDK

#include "http.hpp"

HttpResponse::HttpResponse()
    : error("")
    , statusCode(0)
    , outputFileName("")
    , errorFileName("")
{
}

bool CleanupHttpResponse(const HttpResponse& r)
{
    bool ret1 = DeleteFile(r.outputFileName);
    bool ret2 = DeleteFile(r.errorFileName);

    return ret1 && ret2;
}

const HttpResponse
HttpGet(const Url& url)
{
    HttpResponse r = HttpResponse();

    // request temporary files for status code, stdout, and stderr
    TempFile statusCodeFile = CreateTempFile();
    if (!statusCodeFile.isValid) {
        r.error = "failed to create a temporary file";
        HexLogError("%s", r.error.c_str());
        return r;
    }
    CloseTempFileFd(statusCodeFile);
    TempFile outputFile = CreateTempFile();
    if (!outputFile.isValid) {
        r.error = "failed to create a temporary file";
        HexLogError("%s", r.error.c_str());
        return r;
    }
    CloseTempFileFd(outputFile);
    TempFile errorFile = CreateTempFile();
    if (!errorFile.isValid) {
        r.error = "failed to create a temporary file";
        HexLogError("%s", r.error.c_str());
        return r;
    }
    CloseTempFileFd(errorFile);

    // send the request via curl
    bool isCurlSuccessful = false;
    if (url.scheme == "http") {
        isCurlSuccessful = HexUtilSystemF(
                               0,
                               0,
                               "curl --silent --show-error --output %s --write-out \"%%{http_code}\" \"%s\" >%s 2>%s",
                               outputFile.fileName.c_str(),
                               url.String().c_str(),
                               statusCodeFile.fileName.c_str(),
                               errorFile.fileName.c_str())
            == 0;
    } else if (url.scheme == "https") {
        isCurlSuccessful = HexUtilSystemF(
                               0,
                               0,
                               "curl --insecure --silent --show-error --output %s --write-out \"%%{http_code}\" \"%s\" >%s 2>%s",
                               outputFile.fileName.c_str(),
                               url.String().c_str(),
                               statusCodeFile.fileName.c_str(),
                               errorFile.fileName.c_str())
            == 0;
    } else {
        r.error = "the url scheme is not supported";
        HexLogError("%s", r.error.c_str());
        return r;
    }

    r.outputFileName = outputFile.fileName;
    r.errorFileName = errorFile.fileName;

    if (!isCurlSuccessful) {
        r.error = "curl is not successful";
        HexLogError("%s", r.error.c_str());
        return r;
    }

    // parse the status code
    std::string fsError;
    const std::string statusCodeString = ReadFile(fsError, statusCodeFile.fileName);
    if (fsError.length() > 0) {
        r.error = "failed to parse the HTTP status code of the response";
        HexLogError("%s", r.error.c_str());
        return r;
    }
    int statusCode = 0;
    try {
        std::size_t pos;
        statusCode = std::stoi(statusCodeString, &pos);
    } catch (const std::exception& e) {
        // failed to convert the output string to an integer
        r.error = "failed to parse the HTTP status code of the response";
        HexLogError("%s", r.error.c_str());
        return r;
    }
    r.statusCode = statusCode;
    DeleteTempFile(statusCodeFile);

    // return the HttpResponse object
    return r;
}
