#!/usr/bin/env bash
set -euo pipefail

grep -Eq "^DimsSignatureAlgorithm[[:space:]]+legacy-md5$" examples/dims.conf
grep -Eq "^DimsStrictValidation[[:space:]]+false$" examples/dims.conf
grep -Eq "^DimsEncryptionAlgorithm[[:space:]]+AES/ECB/PKCS5Padding$" examples/dims.conf
grep -Eq "^DimsAllowLegacyEcb[[:space:]]+true$" examples/dims.conf
grep -Eq "^DimsAllowedFetchSchemes[[:space:]]+all$" examples/dims.conf
grep -Eq "^DimsMaxDownloadBytes[[:space:]]+0$" examples/dims.conf
grep -Eq "^DimsMaxRedirects[[:space:]]+-1$" examples/dims.conf
grep -Eq "^DimsStatusExtended[[:space:]]+false$" examples/dims.conf
grep -Eq "^DimsEnableOpCache[[:space:]]+true$" examples/dims.conf
grep -Eq "^DimsOpCacheSize[[:space:]]+10000$" examples/dims.conf
grep -Eq "^DimsFetchConnectionReuse[[:space:]]+true$" examples/dims.conf
grep -Eq "^DimsMaxConcurrentFetchesPerChild[[:space:]]+32$" examples/dims.conf
grep -Eq "^DimsSignatureAlgorithm[[:space:]]+\\$\\{DIMS_SIGNATURE_ALGORITHM\\}$" docker/dims.conf
grep -Eq "^DimsStrictValidation[[:space:]]+\\$\\{DIMS_STRICT_VALIDATION\\}$" docker/dims.conf
grep -Eq "^DimsEncryptionAlgorithm[[:space:]]+\\$\\{DIMS_ENCRYPTION_ALGORITHM\\}$" docker/dims.conf
grep -Eq "^DimsAllowLegacyEcb[[:space:]]+\\$\\{DIMS_ALLOW_LEGACY_ECB\\}$" docker/dims.conf
grep -Eq "^DimsAllowedFetchSchemes[[:space:]]+\\$\\{DIMS_ALLOWED_FETCH_SCHEMES\\}$" docker/dims.conf
grep -Eq "^DimsStatusExtended[[:space:]]+\\$\\{DIMS_STATUS_EXTENDED\\}$" docker/dims.conf
grep -Eq "^DimsEnableOpCache[[:space:]]+\\$\\{DIMS_ENABLE_OP_CACHE\\}$" docker/dims.conf
grep -Eq "^DimsOpCacheSize[[:space:]]+\\$\\{DIMS_OP_CACHE_SIZE\\}$" docker/dims.conf
grep -Eq "^DimsFetchConnectionReuse[[:space:]]+\\$\\{DIMS_FETCH_CONNECTION_REUSE\\}$" docker/dims.conf
grep -Eq "^DimsMaxConcurrentFetchesPerChild[[:space:]]+\\$\\{DIMS_MAX_CONCURRENT_FETCHES_PER_CHILD\\}$" docker/dims.conf
grep -Eq "^ARG IMAGEMAGICK_VERSION=[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+$" docker/Dockerfile
grep -Eq "^ARG IMAGEMAGICK_SHA256=[a-f0-9]{64}$" docker/Dockerfile
grep -Eq "^ARG IMAGEMAGICK_VERSION=[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+$" .devcontainer/Dockerfile
grep -Eq "^ARG IMAGEMAGICK_SHA256=[a-f0-9]{64}$" .devcontainer/Dockerfile
grep -Eq "^ENV DIMS_MAX_DOWNLOAD_BYTES=0$" docker/Dockerfile
grep -Eq "^ENV DIMS_MAX_REDIRECTS=-1$" docker/Dockerfile
grep -Eq "^ENV DIMS_ALLOWED_FETCH_SCHEMES=\"all\"$" docker/Dockerfile
grep -Eq "^ENV DIMS_ALLOW_LEGACY_ECB=\"true\"$" docker/Dockerfile
grep -Eq "^ENV DIMS_ENCRYPTION_ALGORITHM=\"AES/ECB/PKCS5Padding\"$" docker/Dockerfile

echo "config-smoke: ok"
