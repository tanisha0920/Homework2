#!/usr/bin/env bash
# Measure source-level line/branch coverage of a corpus (Task 2).
# Runs INSIDE the container. Builds a SEPARATE gcov-instrumented xpdf (leaving
# your AFL build untouched), replays every input in a corpus dir through it, and
# reports coverage of the core parser/decoder files plus the whole xpdf/ tree.
#
#   tools/coverage.sh <corpus-dir> [<corpus-dir> ...]
# e.g.
#   tools/coverage.sh work-out/out/default/queue
#   tools/coverage.sh work-out/out/default/queue work-out/in
set -euo pipefail
[ "$#" -ge 1 ] || { echo "usage: coverage.sh <corpus-dir> [more dirs...]"; exit 2; }

SRC=/src/xpdf-3.02
GCOVDIR=/tmp/gcov-build          # ephemeral build tree, never touches your repo
OUT="${OUT:-results}"            # where coverage.html is written (in your repo)
CORE='(XRef|Parser|Lexer|Stream|Object|Dict|Array|PDFDoc)\.cc'
mkdir -p "$OUT"; HTML="$(cd "$OUT" && pwd)/coverage.html"

# Build the gcov binary once, into a private copy of the source tree.
if [ ! -x "$GCOVDIR/xpdf/pdftotext" ]; then
  echo "[*] building gcov-instrumented xpdf (one time)..."
  rm -rf "$GCOVDIR"; mkdir -p "$(dirname "$GCOVDIR")"
  cp -a "$SRC" "$GCOVDIR"
  ( cd "$GCOVDIR"
    make clean >/dev/null 2>&1 || true
    CC=gcc CXX=g++ \
      CFLAGS="-fcommon -O0 -g --coverage" \
      CXXFLAGS="-fcommon -O0 -g -std=gnu++98 -w --coverage" \
      LDFLAGS="--coverage" ./configure --enable-a4-paper >/dev/null 2>&1
    make -j"$(nproc)" >/dev/null 2>&1 )
fi

# Reset counters, then replay every input.
find "$GCOVDIR" -name '*.gcda' -delete
n=0
for dir in "$@"; do
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    "$GCOVDIR/xpdf/pdftotext" "$f" /dev/null >/dev/null 2>&1 || true
    n=$((n+1))
  done
done
echo "[*] replayed $n inputs"

cd "$GCOVDIR/xpdf"
echo
echo "=== CORE PARSER/DECODER FILES (graded) ==="
gcovr . --filter "$CORE" --print-summary 2>/dev/null | grep -iE 'lines:|branches:|functions:'
echo
echo "=== WHOLE xpdf/ TREE (for reference) ==="
gcovr . --print-summary 2>/dev/null | grep -iE 'lines:|branches:|functions:'
echo
echo "[*] writing HTML report to $HTML"
gcovr . --filter "$CORE" --html --html-details -o "$HTML" 2>/dev/null || \
  gcovr . --filter "$CORE" --html -o "$HTML" 2>/dev/null || true
