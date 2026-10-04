#!/usr/bin/env bash
# Build the persistent-mode harness against an already-built xpdf 3.02 tree.
# Run this INSIDE the container, after xpdf has been compiled once.
#   XPDF=/src/xpdf-3.02 ./build_harness.sh          # normal instrumented build
#   AFL_USE_ASAN=1 XPDF=/src/xpdf-3.02 ./build_harness.sh   # + AddressSanitizer
set -euo pipefail
XPDF="${XPDF:-/src/xpdf-3.02}"
HERE="$(cd "$(dirname "$0")" && pwd)"

# All xpdf object files EXCEPT the tool main()s (they each define their own main).
OBJS=$(ls "$XPDF"/xpdf/*.o | grep -vE '/(pdf(totext|topng|toppm|tops|tohtml|images|info|fonts|detach))\.o$')

SAN=""; [ "${AFL_USE_ASAN:-0}" = "1" ] && SAN="-fsanitize=address"

afl-clang-fast++ -fcommon -O2 -g -std=gnu++98 -w $SAN \
  -I"$XPDF" -I"$XPDF/goo" -I"$XPDF/fofi" -I"$XPDF/splash" -I"$XPDF/xpdf" \
  "$HERE/fuzz_pdf.cc" $OBJS \
  -L"$XPDF/goo" -lGoo -L"$XPDF/fofi" -lfofi -L"$XPDF/splash" -lsplash -lm \
  -o "$HERE/fuzz_pdf"
echo "built $HERE/fuzz_pdf"
