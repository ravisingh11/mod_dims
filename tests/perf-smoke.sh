#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_TAG="${IMAGE_TAG:-mod-dims:perf-smoke}"
SOURCE_PORT="${SOURCE_PORT:-18180}"
SOURCE_BIND_HOST="${SOURCE_BIND_HOST:-0.0.0.0}"
DIMS_PORT="${DIMS_PORT:-18100}"
REQUESTS="${REQUESTS:-100}"
P95_LIMIT_MS="${P95_LIMIT_MS:-250}"
SKIP_BUILD="${SKIP_BUILD:-false}"

FIXTURE_PID=""

cleanup() {
  local status=$?
  if [[ -n "${FIXTURE_PID}" ]] && kill -0 "${FIXTURE_PID}" 2>/dev/null; then
    kill "${FIXTURE_PID}" || true
    wait "${FIXTURE_PID}" 2>/dev/null || true
  fi
  docker rm -f dims-perf-smoke >/dev/null 2>&1 || true
  exit "${status}"
}
trap cleanup EXIT

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

urlencode() {
  python3 - "$1" <<'PY'
import sys
import urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
}

if [[ "${SKIP_BUILD}" != "true" ]]; then
  echo "Building performance smoke image: ${IMAGE_TAG}"
  docker build -t "${IMAGE_TAG}" -f "${ROOT_DIR}/docker/Dockerfile" "${ROOT_DIR}" >/dev/null
fi

echo "Starting fixture server on ${SOURCE_BIND_HOST}:${SOURCE_PORT}"
python3 "${ROOT_DIR}/tests/hardening_fixture_server.py" --host "${SOURCE_BIND_HOST}" --port "${SOURCE_PORT}" &
FIXTURE_PID="$!"
wait_http_ok "http://127.0.0.1:${SOURCE_PORT}/healthz"

docker rm -f dims-perf-smoke >/dev/null 2>&1 || true
docker run -d --name dims-perf-smoke \
  --add-host host.docker.internal:host-gateway \
  -p "127.0.0.1:${DIMS_PORT}:8000" \
  -e DIMS_CLIENT=development \
  -e DIMS_SECRET=perf-smoke-secret \
  -e DIMS_WHITELIST=host.docker.internal \
  -e DIMS_DEFAULT_IMAGE_URL="http://host.docker.internal:${SOURCE_PORT}/noimage.png" \
  -e DIMS_NO_IMAGE_URL="http://host.docker.internal:${SOURCE_PORT}/noimage.png" \
  -e DIMS_STATUS_EXTENDED=true \
  "${IMAGE_TAG}" >/dev/null

wait_http_ok "http://127.0.0.1:${DIMS_PORT}/dims-status/" 40

GOOD_URL="$(urlencode "http://host.docker.internal:${SOURCE_PORT}/image.png")"
TARGET_URL="http://127.0.0.1:${DIMS_PORT}/dims3/development/resize/128x128?url=${GOOD_URL}"

times_file="$(mktemp)"
for _ in $(seq 1 "${REQUESTS}"); do
  curl -sS -o /dev/null -w "%{time_total}\n" "${TARGET_URL}" >>"${times_file}"
done

python3 - "${times_file}" "${P95_LIMIT_MS}" <<'PY'
import sys

times = []
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    for line in fh:
        line = line.strip()
        if line:
            times.append(float(line) * 1000.0)

if not times:
    print("No timing samples collected", file=sys.stderr)
    sys.exit(1)

times.sort()
n = len(times)
def pct(p):
    idx = int((p / 100.0) * n + 0.999999) - 1
    idx = max(0, min(idx, n - 1))
    return times[idx]

p50 = pct(50)
p95 = pct(95)
p99 = pct(99)
limit = float(sys.argv[2])

print(f"perf-smoke samples={n} p50={p50:.2f}ms p95={p95:.2f}ms p99={p99:.2f}ms limit_p95={limit:.2f}ms")
if p95 > limit:
    print("P95 threshold exceeded", file=sys.stderr)
    sys.exit(1)
PY

rm -f "${times_file}"
echo "perf-smoke: ok"
