#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${IMAGE_TAG:-mod-dims:hardening-itest}"
SOURCE_PORT="${SOURCE_PORT:-18080}"
SOURCE_BIND_HOST="${SOURCE_BIND_HOST:-0.0.0.0}"
BASE_DIMS_PORT="${BASE_DIMS_PORT:-18000}"
ECB_OFF_DIMS_PORT="${ECB_OFF_DIMS_PORT:-18001}"
ECB_ON_DIMS_PORT="${ECB_ON_DIMS_PORT:-18002}"
STRICT_DIMS4_PORT="${STRICT_DIMS4_PORT:-18003}"
ECB_DEFAULT_DIMS_PORT="${ECB_DEFAULT_DIMS_PORT:-18004}"
SECRET="${SECRET:-integration-secret}"

FIXTURE_PID=""

cleanup() {
  local status=$?
  if [[ -n "${FIXTURE_PID}" ]] && kill -0 "${FIXTURE_PID}" 2>/dev/null; then
    kill "${FIXTURE_PID}" || true
    wait "${FIXTURE_PID}" 2>/dev/null || true
  fi
  docker rm -f dims-itest-base dims-itest-ecb-off dims-itest-ecb-on dims-itest-dims4-strict dims-itest-ecb-default >/dev/null 2>&1 || true
  exit "${status}"
}
trap cleanup EXIT

assert_status() {
  local expected="$1"
  local actual="$2"
  local name="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    echo "FAIL: ${name} expected HTTP ${expected}, got ${actual}" >&2
    return 1
  fi
  echo "ok: ${name} -> ${actual}"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local name="$3"
  if [[ "${haystack}" != *"${needle}"* ]]; then
    echo "FAIL: ${name} missing '${needle}'" >&2
    return 1
  fi
  echo "ok: ${name}"
}

wait_http_ok() {
  local url="$1"
  local max_attempts="${2:-30}"
  local i
  for ((i = 1; i <= max_attempts; i++)); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "Timed out waiting for ${url}" >&2
  return 1
}

run_dims_container() {
  local name="$1"
  local port="$2"
  shift 2

  docker rm -f "${name}" >/dev/null 2>&1 || true
  docker run -d --name "${name}" \
    --add-host host.docker.internal:host-gateway \
    -p "127.0.0.1:${port}:8000" \
    -e DIMS_CLIENT=development \
    -e DIMS_SECRET="${SECRET}" \
    -e DIMS_WHITELIST="host.docker.internal" \
    -e DIMS_DEFAULT_IMAGE_URL="http://host.docker.internal:${SOURCE_PORT}/noimage.png" \
    -e DIMS_NO_IMAGE_URL="http://host.docker.internal:${SOURCE_PORT}/noimage.png" \
    "$@" \
    "${IMAGE_TAG}" >/dev/null

  wait_http_ok "http://127.0.0.1:${port}/dims-status/" 40
}

urlencode() {
  python3 - "$1" <<'PY'
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

request_code() {
  local url="$1"
  curl -sS -o /tmp/mod_dims_itest_body.bin -w "%{http_code}" "${url}"
}

dims4_hash() {
  local algorithm="$1"
  local secret="$2"
  local expires="$3"
  local commands="$4"
  local image_url="$5"
  local signed_values_csv="${6:-}"

  python3 - "$algorithm" "$secret" "$expires" "$commands" "$image_url" "$signed_values_csv" <<'PY'
import hashlib
import hmac
import sys

algorithm, secret, expires, commands, image_url, signed_values_csv = sys.argv[1:]
payload = f"{expires}{secret}{commands}{image_url}"
if signed_values_csv:
    for value in signed_values_csv.split(","):
        payload += value

if algorithm == "hmac-sha256":
    print(hmac.new(secret.encode("utf-8"), payload.encode("utf-8"), hashlib.sha256).hexdigest())
elif algorithm == "legacy-md5":
    print(hashlib.md5(payload.encode("utf-8")).hexdigest())
else:
    raise SystemExit(f"unsupported algorithm: {algorithm}")
PY
}

echo "Building integration test image: ${IMAGE_TAG}"
docker build -t "${IMAGE_TAG}" -f "${ROOT_DIR}/docker/Dockerfile" "${ROOT_DIR}" >/dev/null

echo "Starting fixture server on ${SOURCE_BIND_HOST}:${SOURCE_PORT}"
python3 "${ROOT_DIR}/tests/hardening_fixture_server.py" --host "${SOURCE_BIND_HOST}" --port "${SOURCE_PORT}" &
FIXTURE_PID="$!"
wait_http_ok "http://127.0.0.1:${SOURCE_PORT}/healthz"

echo "Running hardening integration tests (base policy)"
run_dims_container "dims-itest-base" "${BASE_DIMS_PORT}" \
  -e DIMS_MAX_DOWNLOAD_BYTES=1024 \
  -e DIMS_MAX_REDIRECTS=1 \
  -e DIMS_ALLOWED_FETCH_SCHEMES="http,https"

GOOD_URL="$(urlencode "http://host.docker.internal:${SOURCE_PORT}/image.png")"
BAD_SCHEME_URL="$(urlencode "file:///etc/passwd")"
LARGE_URL="$(urlencode "http://host.docker.internal:${SOURCE_PORT}/big.bin")"
REDIRECT_URL="$(urlencode "http://host.docker.internal:${SOURCE_PORT}/redirect/3")"

code="$(request_code "http://127.0.0.1:${BASE_DIMS_PORT}/dims3/development/resize/1x1?url=${GOOD_URL}")"
assert_status 200 "${code}" "baseline small image fetch"

code="$(request_code "http://127.0.0.1:${BASE_DIMS_PORT}/dims3/development/resize/1x1?url=${BAD_SCHEME_URL}")"
assert_status 400 "${code}" "disallowed URL scheme"

code="$(request_code "http://127.0.0.1:${BASE_DIMS_PORT}/dims3/development/resize/1x1?url=${LARGE_URL}")"
assert_status 500 "${code}" "max download bytes enforcement"

code="$(request_code "http://127.0.0.1:${BASE_DIMS_PORT}/dims3/development/resize/1x1?url=${REDIRECT_URL}")"
assert_status 500 "${code}" "max redirects enforcement"

echo "Running parser edge-case tests"
code="$(request_code "http://127.0.0.1:${BASE_DIMS_PORT}/dims3/development/resize/?url=${GOOD_URL}")"
assert_status 200 "${code}" "empty resize args tolerated"

code="$(request_code "http://127.0.0.1:${BASE_DIMS_PORT}/dims3/development/format/?url=${GOOD_URL}")"
assert_status 400 "${code}" "empty format args rejected"

echo "Running dims4 signature tests (legacy-md5 relaxed)"
DIMS4_EXPIRES="$(python3 - <<'PY'
import time
print(int(time.time()) + 3600)
PY
)"
DIMS4_COMMANDS="resize/1x1"
DIMS4_IMAGE_URL="http://host.docker.internal:${SOURCE_PORT}/image.png"
DIMS4_IMAGE_URL_ESCAPED="$(urlencode "${DIMS4_IMAGE_URL}")"

LEGACY_MD5_FULL_HASH="$(dims4_hash legacy-md5 "${SECRET}" "${DIMS4_EXPIRES}" "${DIMS4_COMMANDS}" "${DIMS4_IMAGE_URL}")"
LEGACY_MD5_SHORT_HASH="${LEGACY_MD5_FULL_HASH:0:6}"
LEGACY_MD5_BAD_HASH="deadbe"

code="$(request_code "http://127.0.0.1:${BASE_DIMS_PORT}/dims4/development/${LEGACY_MD5_SHORT_HASH}/${DIMS4_EXPIRES}/${DIMS4_COMMANDS}?url=${DIMS4_IMAGE_URL_ESCAPED}")"
assert_status 200 "${code}" "dims4 legacy-md5 short signature accepted in non-strict mode"

code="$(request_code "http://127.0.0.1:${BASE_DIMS_PORT}/dims4/development/${LEGACY_MD5_BAD_HASH}/${DIMS4_EXPIRES}/${DIMS4_COMMANDS}?url=${DIMS4_IMAGE_URL_ESCAPED}")"
assert_status 400 "${code}" "dims4 legacy-md5 bad signature rejected"

echo "Running dims4 signature tests (hmac-sha256 strict)"
run_dims_container "dims-itest-dims4-strict" "${STRICT_DIMS4_PORT}" \
  -e DIMS_SIGNATURE_ALGORITHM=hmac-sha256 \
  -e DIMS_STRICT_VALIDATION=true

HMAC_FULL_HASH="$(dims4_hash hmac-sha256 "${SECRET}" "${DIMS4_EXPIRES}" "${DIMS4_COMMANDS}" "${DIMS4_IMAGE_URL}")"
HMAC_SHORT_HASH="${HMAC_FULL_HASH:0:12}"

code="$(request_code "http://127.0.0.1:${STRICT_DIMS4_PORT}/dims4/development/${HMAC_FULL_HASH}/${DIMS4_EXPIRES}/${DIMS4_COMMANDS}?url=${DIMS4_IMAGE_URL_ESCAPED}")"
assert_status 200 "${code}" "dims4 hmac-sha256 full signature accepted in strict mode"

code="$(request_code "http://127.0.0.1:${STRICT_DIMS4_PORT}/dims4/development/${HMAC_SHORT_HASH}/${DIMS4_EXPIRES}/${DIMS4_COMMANDS}?url=${DIMS4_IMAGE_URL_ESCAPED}")"
assert_status 400 "${code}" "dims4 hmac-sha256 short signature rejected in strict mode"

# Signed query parameters: strict mode requires every _keys entry to be present.
code="$(request_code "http://127.0.0.1:${STRICT_DIMS4_PORT}/dims4/development/${HMAC_FULL_HASH}/${DIMS4_EXPIRES}/${DIMS4_COMMANDS}?url=${DIMS4_IMAGE_URL_ESCAPED}&_keys=download,optimizeResize&download=1")"
assert_status 400 "${code}" "strict mode rejects missing signed query parameter listed in _keys"

HMAC_WITH_KEYS="$(dims4_hash hmac-sha256 "${SECRET}" "${DIMS4_EXPIRES}" "${DIMS4_COMMANDS}" "${DIMS4_IMAGE_URL}" "1,2")"
code="$(request_code "http://127.0.0.1:${STRICT_DIMS4_PORT}/dims4/development/${HMAC_WITH_KEYS}/${DIMS4_EXPIRES}/${DIMS4_COMMANDS}?url=${DIMS4_IMAGE_URL_ESCAPED}&_keys=download,optimizeResize&download=1&optimizeResize=2")"
assert_status 200 "${code}" "strict mode accepts valid signed _keys parameters"

KEY_HEX="$(python3 - "${SECRET}" <<'PY'
import hashlib
import sys
print(hashlib.sha256(sys.argv[1].encode("utf-8")).hexdigest()[:32])
PY
)"

ECB_PLAINTEXT="http://host.docker.internal:${SOURCE_PORT}/image.png"
ECB_ENCRYPTED="$(printf '%s' "${ECB_PLAINTEXT}" | openssl enc -aes-128-ecb -K "${KEY_HEX}" -nosalt -base64 | tr -d '\n')"
ECB_ENCRYPTED_ESCAPED="$(urlencode "${ECB_ENCRYPTED}")"

echo "Running hardening integration tests (legacy ECB default compatibility)"
run_dims_container "dims-itest-ecb-default" "${ECB_DEFAULT_DIMS_PORT}"

code="$(request_code "http://127.0.0.1:${ECB_DEFAULT_DIMS_PORT}/dims3/development/resize/1x1?url=${REDIRECT_URL}")"
assert_status 200 "${code}" "redirect chain allowed by default compatibility policy"

status_body="$(curl -fsS "http://127.0.0.1:${ECB_DEFAULT_DIMS_PORT}/dims-status/")"
assert_contains "${status_body}" "Allow legacy ECB: true" "default status reports legacy ECB allowed"
assert_contains "${status_body}" "Max download bytes: 0" "default status reports download cap disabled"
assert_contains "${status_body}" "Max redirects: -1" "default status reports redirect cap disabled"
assert_contains "${status_body}" "Allowed fetch schemes: all" "default status reports unrestricted fetch schemes"

code="$(request_code "http://127.0.0.1:${ECB_DEFAULT_DIMS_PORT}/dims3/development/resize/1x1?eurl=${ECB_ENCRYPTED_ESCAPED}")"
assert_status 200 "${code}" "legacy ECB allowed by default for compatibility"

echo "Running hardening integration tests (legacy ECB disabled)"
run_dims_container "dims-itest-ecb-off" "${ECB_OFF_DIMS_PORT}" \
  -e DIMS_ENCRYPTION_ALGORITHM="AES/ECB/PKCS5Padding" \
  -e DIMS_ALLOW_LEGACY_ECB=false

code="$(request_code "http://127.0.0.1:${ECB_OFF_DIMS_PORT}/dims3/development/resize/1x1?eurl=${ECB_ENCRYPTED_ESCAPED}")"
assert_status 500 "${code}" "legacy ECB blocked by policy"

echo "Running hardening integration tests (legacy ECB allowed)"
run_dims_container "dims-itest-ecb-on" "${ECB_ON_DIMS_PORT}" \
  -e DIMS_ENCRYPTION_ALGORITHM="AES/ECB/PKCS5Padding" \
  -e DIMS_ALLOW_LEGACY_ECB=true

code="$(request_code "http://127.0.0.1:${ECB_ON_DIMS_PORT}/dims3/development/resize/1x1?eurl=${ECB_ENCRYPTED_ESCAPED}")"
assert_status 200 "${code}" "legacy ECB allowed for compatibility"

echo "hardening-integration: ok"
