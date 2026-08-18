// CUBE SDK

#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <unistd.h>

#include <string>
#include <vector>

#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/bio.h>
#include <openssl/sha.h>

#include <hex/log.h>
#include <hex/config_module.h>

#include "advisor_key.h"

// Verification of Cube AI Advisor agent releases.
//
// The agent is released by Bigstack as signed per-arch artifacts and must be
// verified before a node executes one. Two decisions from ADR 0003 shape what
// is here:
//
//   * This lives in cubecos, not in the agent's own repository. A verifier must
//     not share a build pipeline with the artifact it verifies, or one
//     compromised pipeline produces both.
//   * The trust anchor belongs to the OS, and is compiled in rather than read
//     from a file -- the same mechanism hex uses for the licence key. A key
//     file on a node can be replaced by any root process, and the failure would
//     be silent: verification would still report success, against the
//     attacker's key. Compiled in, an attacker has to replace hex_config, which
//     is part of the signed OS image.
//
// Verification is here rather than in shell for the same reason it is done this
// way for licences: key and check belong in one place. A shell verifier reads a
// key the image protects, but lives in a file under /usr/lib/hex_sdk that root
// can edit -- so the check could be removed while the key stayed safe.
//
// advisor_pubkey still prints the key, deliberately. The manifest format is
// sha256sum's own, so a customer who does not want to trust this binary can
// extract the key and run the two standard commands themselves:
//
//     hex_config advisor_pubkey > release.pub
//     openssl dgst -sha256 -verify release.pub -signature manifest.txt.sig manifest.txt
//     sha256sum -c manifest.txt
//
// That independent path is a property of the published format, not of what this
// verifier is written in, and it is worth keeping either way.

static const char MANIFEST_NAME[]  = "manifest.txt";
static const char SIGNATURE_NAME[] = "manifest.txt.sig";

// Bounds, so a hostile file cannot be read into memory unbounded. Both are far
// above any real release: a manifest is a few lines per architecture.
static const size_t MAX_MANIFEST_SIZE  = 1024 * 1024;
static const size_t MAX_SIGNATURE_SIZE = 16 * 1024;

// Opens name inside dirFd for reading.
//
// openat rather than building a path, and O_NOFOLLOW rather than trusting the
// name: a release directory entry that is a symlink would otherwise be read
// through, and every check below would then describe a file somewhere else
// entirely. The name is already constrained to a bare file name; this makes
// escaping it impossible rather than merely rejected.
static FILE *
OpenAt(int dirFd, const std::string& name)
{
    int fd = openat(dirFd, name.c_str(), O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0)
        return NULL;
    FILE *fp = fdopen(fd, "rb");
    if (!fp)
        close(fd);
    return fp;
}

// Reads name (relative to dirFd) into out, refusing anything larger than maxSize.
static bool
ReadFileAt(int dirFd, const std::string& name, size_t maxSize, std::string *out)
{
    FILE *fp = OpenAt(dirFd, name);
    if (!fp) {
        fprintf(stderr, "Error: cannot read %s\n", name.c_str());
        return false;
    }

    // fstat on the descriptor we are about to read, not stat on a name that
    // could refer to something else by the time we open it.
    struct stat st;
    if (fstat(fileno(fp), &st) != 0 || !S_ISREG(st.st_mode)) {
        fclose(fp);
        fprintf(stderr, "Error: %s is not a regular file\n", name.c_str());
        return false;
    }

    out->clear();
    char buf[65536];
    size_t n;
    while ((n = fread(buf, 1, sizeof(buf), fp)) > 0) {
        if (out->size() + n > maxSize) {
            fclose(fp);
            fprintf(stderr, "Error: %s is larger than the %zu byte limit\n",
                    name.c_str(), maxSize);
            return false;
        }
        out->append(buf, n);
    }
    bool ok = (ferror(fp) == 0);
    fclose(fp);
    if (!ok)
        fprintf(stderr, "Error: read failed on %s\n", name.c_str());
    return ok;
}

// Verifies sig over data using the compiled-in release public key.
//
// The key is parsed from the embedded PEM on every call rather than cached: it
// is a handful of microseconds, and a cached EVP_PKEY is one more piece of
// mutable process state for something whose whole job is to be immutable.
static bool
VerifySignature(const std::string& data, const std::string& sig)
{
    BIO *bio = BIO_new_mem_buf((void *)ADVISOR_RELEASE_PUBLIC_KEY, -1);
    if (!bio) {
        HexLogError("advisor: cannot allocate key BIO");
        return false;
    }
    EVP_PKEY *pkey = PEM_read_bio_PUBKEY(bio, NULL, NULL, NULL);
    BIO_free(bio);
    if (!pkey) {
        // A build problem, not an input problem: the embedded key is a constant.
        HexLogError("advisor: embedded release public key is unusable");
        fprintf(stderr, "Error: embedded release public key is unusable\n");
        return false;
    }

    bool ok = false;
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    if (ctx) {
        if (EVP_DigestVerifyInit(ctx, NULL, EVP_sha256(), NULL, pkey) == 1 &&
            EVP_DigestVerifyUpdate(ctx, data.data(), data.size()) == 1 &&
            EVP_DigestVerifyFinal(ctx, (const unsigned char *)sig.data(), sig.size()) == 1) {
            ok = true;
        }
        EVP_MD_CTX_free(ctx);
    }
    EVP_PKEY_free(pkey);
    return ok;
}

// Hex-encoded SHA-256 of a file, streamed so artifact size does not bound memory.
static bool
FileDigestAt(int dirFd, const std::string& name, std::string *hexOut)
{
    // Whether an absent file is an error depends on what the caller asked, so
    // the caller reports it -- an install fetches one architecture and leaves
    // its siblings legitimately missing.
    FILE *fp = OpenAt(dirFd, name);
    if (!fp)
        return false;

    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    if (!ctx) {
        fclose(fp);
        return false;
    }

    bool ok = (EVP_DigestInit_ex(ctx, EVP_sha256(), NULL) == 1);
    unsigned char buf[65536];
    size_t n;
    while (ok && (n = fread(buf, 1, sizeof(buf), fp)) > 0)
        ok = (EVP_DigestUpdate(ctx, buf, n) == 1);
    if (ferror(fp))
        ok = false;
    fclose(fp);

    unsigned char md[EVP_MAX_MD_SIZE];
    unsigned int mdLen = 0;
    if (ok)
        ok = (EVP_DigestFinal_ex(ctx, md, &mdLen) == 1);
    EVP_MD_CTX_free(ctx);
    if (!ok)
        return false;

    static const char HEXDIGITS[] = "0123456789abcdef";
    hexOut->clear();
    for (unsigned int i = 0; i < mdLen; ++i) {
        hexOut->push_back(HEXDIGITS[md[i] >> 4]);
        hexOut->push_back(HEXDIGITS[md[i] & 0x0f]);
    }
    return true;
}

static bool
IsLowerHex(const std::string& s)
{
    for (size_t i = 0; i < s.size(); ++i) {
        char c = s[i];
        if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')))
            return false;
    }
    return true;
}

// An artifact name is a bare file name in the release directory and nothing
// else. Rejecting separators and dot entries here is what stops a signed
// manifest -- or a manifest an attacker hopes we check before the signature --
// from naming a path outside the directory being verified.
static bool
IsSafeArtifactName(const std::string& name)
{
    if (name.empty() || name == "." || name == "..")
        return false;
    if (name.find('/') != std::string::npos || name.find('\\') != std::string::npos)
        return false;
    if (name[0] == '-')
        return false;
    for (size_t i = 0; i < name.size(); ++i) {
        unsigned char c = (unsigned char)name[i];
        if (c < 0x21 || c > 0x7e)
            return false;
    }
    return true;
}

struct Entry {
    std::string digest;
    std::string name;
};

// Parses the manifest.
//
// The format is fixed by pkg/release.Render in the agent repository: comment
// lines carrying metadata, then "<64 lowercase hex>  <name>" per artifact. It is
// parsed strictly. Our own tooling is the only thing that produces a manifest,
// so anything that does not match exactly is not a manifest we should act on.
static bool
ParseManifest(const std::string& text, std::vector<Entry> *out)
{
    size_t pos = 0;
    while (pos <= text.size()) {
        size_t eol = text.find('\n', pos);
        std::string line = (eol == std::string::npos)
            ? text.substr(pos) : text.substr(pos, eol - pos);
        pos = (eol == std::string::npos) ? text.size() + 1 : eol + 1;

        if (!line.empty() && line[line.size() - 1] == '\r')
            line.erase(line.size() - 1);
        if (line.empty() || line[0] == '#')
            continue;

        if (line.size() < 67 || line.compare(64, 2, "  ") != 0) {
            fprintf(stderr, "Error: unparseable manifest line: %s\n", line.c_str());
            return false;
        }
        Entry e;
        e.digest = line.substr(0, 64);
        e.name = line.substr(66);
        if (!IsLowerHex(e.digest)) {
            fprintf(stderr, "Error: manifest line does not begin with a sha256 digest: %s\n",
                    line.c_str());
            return false;
        }
        if (!IsSafeArtifactName(e.name)) {
            fprintf(stderr, "Error: manifest names an unacceptable artifact: %s\n", e.name.c_str());
            return false;
        }
        out->push_back(e);
    }

    if (out->empty()) {
        fprintf(stderr, "Error: manifest lists no artifacts\n");
        return false;
    }
    return true;
}

// VerifyRelease checks the release in dir, and -- when requiredArtifact is not
// empty -- that the manifest lists that artifact.
//
// Order is load-bearing. The signature is checked FIRST, because the digest
// list is only worth applying once we know Bigstack wrote it. Checking digests
// first would mean deciding a file is "the right file" according to a list an
// attacker may have supplied; the list is the thing being attacked.
static bool
VerifyRelease(const std::string& dir, const std::string& requiredArtifact)
{
    // Caller-supplied, and hex_config opens it as root (config_main.cpp
    // setuid(0)): require an absolute path with no "..".
    if (dir.empty() || dir[0] != '/' || dir.size() >= PATH_MAX ||
        strstr(dir.c_str(), "..") != NULL) {
        fprintf(stderr, "Error: release directory must be an absolute path "
                        "without \"..\"\n");
        return false;
    }

    // Everything below is read relative to this descriptor, so no artifact name
    // is ever concatenated into a path.
    int dirFd = open(dir.c_str(), O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (dirFd < 0) {
        fprintf(stderr, "Error: cannot open release directory %s\n", dir.c_str());
        return false;
    }

    std::string manifest, signature;
    if (!ReadFileAt(dirFd, MANIFEST_NAME, MAX_MANIFEST_SIZE, &manifest) ||
        !ReadFileAt(dirFd, SIGNATURE_NAME, MAX_SIGNATURE_SIZE, &signature)) {
        close(dirFd);
        return false;
    }

    // 1. Is this manifest Bigstack's?
    if (!VerifySignature(manifest, signature)) {
        HexLogError("advisor: release manifest signature does not verify in %s", dir.c_str());
        fprintf(stderr, "Error: release manifest signature does not verify against the "
                        "release key in this image\n");
        close(dirFd);
        return false;
    }

    std::vector<Entry> entries;
    if (!ParseManifest(manifest, &entries)) {
        HexLogError("advisor: signed manifest in %s did not parse", dir.c_str());
        close(dirFd);
        return false;
    }

    // 2. Are the artifacts the ones it describes?
    //
    // A release is signed for every architecture at once, but an install fetches
    // only the one this node runs, so naming an artifact means "is this one
    // genuine" and the siblings are legitimately absent. Naming none means "is
    // this whole release intact" -- offline media, an audit -- and then every
    // entry must be there. The required artifact is tracked rather than merely
    // looked up: it is the file about to be executed, so being listed is not
    // enough, it has to have been digested here.
    bool requiredDigested = false;
    for (size_t i = 0; i < entries.size(); ++i) {
        std::string actual;
        if (!FileDigestAt(dirFd, entries[i].name, &actual)) {
            if (!requiredArtifact.empty() && entries[i].name != requiredArtifact) {
                continue;
            }
            HexLogError("advisor: cannot digest %s listed in the signed manifest",
                        entries[i].name.c_str());
            fprintf(stderr, "Error: cannot read %s, which the signed manifest lists\n",
                    entries[i].name.c_str());
            close(dirFd);
            return false;
        }
        if (actual != entries[i].digest) {
            HexLogError("advisor: %s does not match the signed manifest in %s",
                        entries[i].name.c_str(), dir.c_str());
            fprintf(stderr, "Error: %s does not match the signed manifest\n",
                    entries[i].name.c_str());
            close(dirFd);
            return false;
        }
        if (entries[i].name == requiredArtifact) {
            requiredDigested = true;
        }
    }

    // 3. Is the artifact we were asked about one the manifest covers, and did we
    //    just check it? A file that happens to sit in a verified directory is
    //    not itself verified.
    if (!requiredArtifact.empty() && !requiredDigested) {
        fprintf(stderr, "Error: %s is not listed in the signed manifest\n",
                requiredArtifact.c_str());
        close(dirFd);
        return false;
    }

    close(dirFd);
    return true;
}

static void
PubkeyUsage(void)
{
    fprintf(stderr, "Usage: %s advisor_pubkey\n", HexLogProgramName());
}

static int
PubkeyMain(int argc, char **argv)
{
    if (argc != 1) {
        PubkeyUsage();
        return EXIT_FAILURE;
    }

    // stdout, so a caller can consume it through a pipe; nothing here writes a file.
    fputs(ADVISOR_RELEASE_PUBLIC_KEY, stdout);
    return EXIT_SUCCESS;
}

static void
VerifyReleaseUsage(void)
{
    fprintf(stderr, "Usage: %s advisor_verify_release <dir> [artifact]\n", HexLogProgramName());
}

static int
VerifyReleaseMain(int argc, char **argv)
{
    if (argc != 2 && argc != 3) {
        VerifyReleaseUsage();
        return EXIT_FAILURE;
    }

    const std::string dir = argv[1];
    const std::string artifact = (argc == 3) ? argv[2] : "";

    if (!artifact.empty() && !IsSafeArtifactName(artifact)) {
        fprintf(stderr, "Error: %s is not an acceptable artifact name\n", artifact.c_str());
        return EXIT_FAILURE;
    }

    return VerifyRelease(dir, artifact) ? EXIT_SUCCESS : EXIT_FAILURE;
}

CONFIG_MODULE(advisor, 0, 0, 0, 0, 0);

CONFIG_COMMAND(advisor_pubkey, PubkeyMain, PubkeyUsage);
CONFIG_COMMAND(advisor_verify_release, VerifyReleaseMain, VerifyReleaseUsage);
