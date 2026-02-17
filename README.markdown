Dependencies
============

* Apache 2.4+
* ImageMagick 6.9+ or 7.x (Docker/devcontainer builds fetch the latest release tarball at build time)
* libcurl 8+

Testing
=======

Run config-level checks:

    ./tests/config-smoke.sh

Run end-to-end hardening integration tests (requires Docker, Python 3, OpenSSL, curl):

    ./tests/hardening-integration.sh

Run performance smoke benchmark (quick p95 guardrail):

    ./tests/perf-smoke.sh

Run the full wired test suite via automake:

    make check

QA: Test with Custom JPG/PNG/WebP Files
=======================================

Use this flow to test real image files from a local folder.

1. Start a local file server from your image directory:

       cd /path/to/qa-images
       python3 -m http.server 19090

2. Run mod_dims in Docker and allow that source host:

       docker run --rm -p 8000:8000 \
         --add-host host.docker.internal:host-gateway \
         -e DIMS_CLIENT=development \
         -e DIMS_SECRET=mysecret \
         -e DIMS_WHITELIST=host.docker.internal \
         mod-dims:qa

3. In another terminal, URL-encode your source image and request a dims URL:

       ENCODED_URL="$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "http://host.docker.internal:19090/sample.jpg")"
       curl -i "http://127.0.0.1:8000/dims3/development/resize/400x400?url=${ENCODED_URL}"

Suggested QA checks per file:

* resize: `/resize/400x400`
* crop: `/crop/200x200+0+0`
* format conversion: add `/format/webp` or `/format/jpeg`
* quality: add `/quality/80`

Compiling
=========

Run a local build:

    ./autorun.sh
    ./configure
    make -j"$(nproc)"

Use centralized developer/sanitizer build profiles:

    make dev-build
    make dev-check
    make sanitize-build
    make sanitize-check

If Apache/ImageMagick are installed in non-default prefixes, pass them to `./configure`:

    ./configure --with-imagemagick=/path/to/imagemagick --with-apache=/path/to/apache
    make -j"$(nproc)"

The paths provided above are prefix paths used to install those dependencies. If you installed
ImageMagick and Apache (including APR) in /usr/local you would run:

    ./configure --with-imagemagick=/usr/local --with-apache=/usr/local
    make -j"$(nproc)"

Installation
============

Add the following to the Apache configuration:

    <IfModule !mod_dims.c>
        LoadModule dims_module modules/libmod_dims.so
    </IfModule>

    AddHandler dims-local .gif .jpg .png

    <Location /dims/>
        SetHandler dims
    </Location>

    <Location /dims3/>
        SetHandler dims3
    </Location>

    <Location /dims4/>
        SetHandler dims4
    </Location>

    <Location /dims-status/>
        SetHandler dims-status
    </Location>

    # Optional hardening.
    # DimsSignatureAlgorithm hmac-sha256
    # DimsStrictValidation true
    # DimsAllowedFetchSchemes http,https
    # DimsMaxDownloadBytes 67108864
    # DimsMaxRedirects 5
    # DimsConnectTimeout 1000
    # DimsLogSensitiveData false
    # DimsEncryptionAlgorithm AES/GCM/NoPadding
    # DimsAllowLegacyEcb false
    # DimsStatusExtended true
    # DimsEnableOpCache true
    # DimsOpCacheSize 10000
    # DimsFetchConnectionReuse true
    # DimsMaxConcurrentFetchesPerChild 32

This assumes `libmod_dims.so` has been installed in `$HTTP_ROOT/modules`.

Security Modes
==============

`/dims4/` supports two signature algorithms:

* `legacy-md5` (default for backward compatibility)
* `hmac-sha256` (recommended for new integrations)

To enforce stronger validation and full-length signatures, enable:

    DimsStrictValidation true

Remote Fetch Hardening
======================

Recommended defaults for safer upstream fetch behavior:

    DimsAllowedFetchSchemes http,https
    DimsMaxDownloadBytes 67108864
    DimsMaxRedirects 5
    DimsConnectTimeout 1000
    DimsLogSensitiveData false
    DimsFetchConnectionReuse true
    DimsMaxConcurrentFetchesPerChild 32

Performance & Scale Controls
============================

Performance-oriented directives:

    DimsEnableOpCache true
    DimsOpCacheSize 10000
    DimsFetchConnectionReuse true
    DimsMaxConcurrentFetchesPerChild 32

Extended status metrics:

    DimsStatusExtended true

When enabled, `/dims-status/` includes approximate latency percentiles, op-cache hit ratio, and fetch-handle reuse ratio.

Encrypted `eurl` recommendations:

    DimsEncryptionAlgorithm AES/GCM/NoPadding
    DimsAllowLegacyEcb false

Backward Compatibility & Migration
==================================

Are the behavior changes good?

Yes for security. The stricter defaults reduce risk from weak crypto usage, unsafe URL handling, oversized downloads, and redirect abuse.

What remains backward compatible:

* `/dims3/` and `/dims4/` URL formats.
* `dims4` signature verification using `legacy-md5` by default.

What can break older clients:

* Legacy encrypted URLs (`eurl`) that rely on ECB now fail unless explicitly enabled.
* Remote fetches now enforce scheme allowlist, download size limits, and redirect limits.

Legacy compatibility profile (temporary migration mode):

    DimsSignatureAlgorithm legacy-md5
    DimsStrictValidation false
    DimsEncryptionAlgorithm AES/ECB/PKCS5Padding
    DimsAllowLegacyEcb true
    DimsAllowedFetchSchemes http,https
    DimsMaxDownloadBytes 268435456
    DimsMaxRedirects 10

Recommended hardened profile:

    DimsSignatureAlgorithm hmac-sha256
    DimsStrictValidation true
    DimsEncryptionAlgorithm AES/GCM/NoPadding
    DimsAllowLegacyEcb false
    DimsAllowedFetchSchemes http,https
    DimsMaxDownloadBytes 67108864
    DimsMaxRedirects 5
    DimsConnectTimeout 1000
    DimsLogSensitiveData false

Suggested rollout:

1. Start with legacy profile to keep traffic stable.
2. Migrate clients from ECB `eurl` to AES-GCM.
3. Move `dims4` callers to `hmac-sha256`.
4. Enable strict validation.
5. Switch to hardened profile and remove legacy ECB support.

Errors
======

There are three classes of errors in mod_dims; 

- Errors caused during downloading of a source image.  These
  come directly from libcurl and are logged as-is.

- Errors caused during an ImageMagick operation. These
  come directly from ImageMagick and are logged as-is.

- Errors caused during processing of a request by mod_dims.  These
  fall into the category of bad input checking, bad config, etc.

ImageMagick Timeout Error Format:
---------------------------------

[client <client ip address>] ImageMagick operation, '<operation>', timed out after 4 ms

<operation> would be something like "Resize/Image" or "Save/Image".

General Error Format:
---------------------

Errors will be in the following format in Apache's error log:

[client <client ip address>] <source> error, '<source error message>', on request: <request uri>

For example:

[client 10.181.182.244] ImageMagick error, 'no decode delegate for this image
format `'', on request: /20080803WI55426251_WI.jpg/TEST/thumbnail/78x100/

Common libcurl Error Messages:
------------------------------

These messages are usually self-explanatory, so no additional explanation is provided. The
URL that failed will be logged along with this message.

* Couldn't connect to server
* Couldn't resolve DNS
* Timeout was reached

Common mod_dims Error Messages:
--------------------------------

* Requested URL has hostname that is not in the whitelist. (aaolcdn.com)
* Application ID is not valid
* Parsing thumbnail geometry failed
* Parsing crop geometry failed
* Failed to read image
    This occurs if ImageMagick had trouble reading the image.
* Unable to stat image file
    This occurs when a local request is unable to find the image to resize.

Common ImageMagick Error Messages:
---------------------------------

* Memory allocation failed
    This should rarely occur, if ever, but usually when it does it's the result
    of an ImageMagick timeout.

* unrecognized image format
* no decode delegate for this image format
>    This happens when ImageMagick doesn't know how to read a source image.

* zero-length blob not permitted
>    This may occur if there was a failure to download the source image.

* Unsupported marker type 0x03
    This may occur if the image is corrupted.  The "0x03" may be different
    depending on the corruption.

Other more serious errors:
--------------------------

Any errors that have "Assertion failed" are results of bugs in the code and
can be considered serious.

- Assertion failed: (wand->signature == WandSignature), 
  function MagickGetImageFormat, file wand/magick-image.c, line 4137.
