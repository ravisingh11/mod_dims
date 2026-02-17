#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

INDEX_URL="https://download.imagemagick.org/archive/releases/"

LATEST_VERSION="$(
  curl -fsSL "${INDEX_URL}" \
    | grep -oE 'ImageMagick-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.tar\.xz' \
    | sed -E 's/^ImageMagick-([0-9]+\.[0-9]+\.[0-9]+-[0-9]+)\.tar\.xz$/\1/' \
    | sort -uV \
    | tail -n 1
)"

if [[ -z "${LATEST_VERSION}" ]]; then
  echo "Unable to determine latest ImageMagick version from ${INDEX_URL}" >&2
  exit 1
fi

CURRENT_VERSION="$(sed -n 's/^ARG IMAGEMAGICK_VERSION=//p' docker/Dockerfile | head -n 1)"
if [[ -z "${CURRENT_VERSION}" ]]; then
  echo "Unable to read current IMAGEMAGICK_VERSION from docker/Dockerfile" >&2
  exit 1
fi

if [[ "${LATEST_VERSION}" == "${CURRENT_VERSION}" ]]; then
  echo "ImageMagick already up to date at ${CURRENT_VERSION}"
  exit 0
fi

TARBALL_URL="https://download.imagemagick.org/archive/releases/ImageMagick-${LATEST_VERSION}.tar.xz"
TMP_TARBALL="$(mktemp /tmp/imagemagick-update-XXXXXX.tar.xz)"
trap 'rm -f "${TMP_TARBALL}"' EXIT

curl --retry 3 --retry-all-errors -fsSL "${TARBALL_URL}" -o "${TMP_TARBALL}"
LATEST_SHA256="$(sha256sum "${TMP_TARBALL}" | awk '{print $1}')"

python3 - "${LATEST_VERSION}" "${LATEST_SHA256}" <<'PY'
import pathlib
import re
import sys

version = sys.argv[1]
sha256 = sys.argv[2]

files = ["docker/Dockerfile", ".devcontainer/Dockerfile"]
for rel in files:
    path = pathlib.Path(rel)
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"^ARG IMAGEMAGICK_VERSION=.*$", f"ARG IMAGEMAGICK_VERSION={version}", text, flags=re.MULTILINE, count=1)
    text = re.sub(r"^ARG IMAGEMAGICK_SHA256=.*$", f"ARG IMAGEMAGICK_SHA256={sha256}", text, flags=re.MULTILINE, count=1)
    path.write_text(text, encoding="utf-8")
PY

echo "Updated ImageMagick pin: ${CURRENT_VERSION} -> ${LATEST_VERSION}"
