#!/usr/bin/env bash
# STUDENT: build the Docker environment image. Run this once, then open a shell
# in it and work through FUZZING_GUIDE.md. It does not build or run xpdf for you.
#
#   ./build.sh
set -euo pipefail
cd "$(dirname "$0")"

# Identify this checkout from its git remote (falls back to the folder name).
url="$(git config --get remote.origin.url 2>/dev/null || true)"
if [ -n "$url" ]; then
  REPO="$(printf '%s' "$url" | sed -E 's#^.*[:/]([^/]+/[^/]+)$#\1#; s#\.git$##')"
else
  REPO="$(basename "$(pwd)")"
fi

# Portable MD5 (md5sum on Linux, md5 on macOS).
md5hex() { if command -v md5sum >/dev/null 2>&1; then md5sum | cut -d' ' -f1; else md5 -q; fi; }
H="$(printf '%s' "$REPO" | md5hex | cut -c1-16)"
TAG='%XPDF'

docker build \
  --build-arg STUDENT_TAG="$TAG" \
  --build-arg STUDENT_REPO="$REPO" \
  --build-arg HDR="${TAG}${H}" \
  -t cs5187-hw2 .
echo
echo "built image cs5187-hw2"
echo "next: open a shell and follow FUZZING_GUIDE.md:"
echo "  docker run -it -v \"\$PWD\":/work -w /work cs5187-hw2 bash"
