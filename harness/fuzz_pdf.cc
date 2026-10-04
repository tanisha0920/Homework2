// Persistent-mode AFL++ harness for xpdf 3.02.
//
// Instead of fork+exec of pdftotext per input, this stays in one process and
// drives the parser + text extractor over AFL's shared-memory test case, so
// throughput jumps several-fold. The input is fed through an in-memory
// MemStream (no temp files).
//
// Build: see harness/build_harness.sh
#include <aconf.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include "gmem.h"
#include "GString.h"
#include "Object.h"
#include "Stream.h"
#include "GlobalParams.h"
#include "PDFDoc.h"
#include "TextOutputDev.h"

__AFL_FUZZ_INIT();

static void sink(void *stream, char *text, int len) { (void)stream; (void)text; (void)len; }

int main(int argc, char **argv) {
  (void)argc; (void)argv;

  // One-time, expensive init kept OUTSIDE the loop (deferred forkserver).
  globalParams = new GlobalParams((char *)"");

  // Reuse the sample document's first line as a header so the inputs we build
  // are well-formed PDFs; AFL then mutates only the body below it.
  char hdr[128]; int hlen = 0;
  FILE *hf = fopen("/opt/hw/seeds/seed.pdf", "rb");
  if (hf) {
    int c;
    while (hlen < (int)sizeof(hdr) && (c = fgetc(hf)) != EOF) {
      hdr[hlen++] = (char)c;
      if (c == '\n') break;
    }
    fclose(hf);
  }

  __AFL_INIT();
  unsigned char *buf = __AFL_FUZZ_TESTCASE_BUF;

  while (__AFL_LOOP(10000)) {
    int len = __AFL_FUZZ_TESTCASE_LEN;

    int total = hlen + len;
    char *data = (char *)gmalloc(total > 0 ? total : 1);
    if (hlen) memcpy(data, hdr, hlen);
    if (len)  memcpy(data + hlen, buf, len);

    Object dummy;
    dummy.initNull();
    MemStream *mem = new MemStream(data, 0, total, &dummy);

    PDFDoc *doc = new PDFDoc((BaseStream *)mem);
    if (doc->isOk()) {
      TextOutputDev *dev = new TextOutputDev(&sink, NULL, gFalse, gFalse);
      if (dev->isOk()) {
        int n = doc->getNumPages();
        if (n > 50) n = 50;
        doc->displayPages(dev, 1, n, 72, 72, 0, gFalse, gTrue, gFalse);
      }
      delete dev;
    }
    delete doc;
  }

  delete globalParams;
  return 0;
}
