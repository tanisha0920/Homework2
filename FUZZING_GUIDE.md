# Fuzzing xpdf 3.02 with AFL++ — Manual Guide

This guide walks you through **every step by hand**: building the target,
building an AddressSanitizer version, running AFL++, checking that it is actually
making progress, writing a persistent-mode harness, and reading every fuzzing
metric. You do all of it yourself — `build.sh` only builds the Docker
environment image; there is no script that fuzzes for you.

All commands below run **inside the Linux container** that has AFL++. Get a
shell in it:

```bash
./build.sh
docker run -it -v "$PWD":/work -w /work cs5187-hw2 bash
```

Everything from here is typed inside that shell. Your **repo is mounted at
`/work`** and is your working directory, so `tools/`, `dict/`, `harness/`, and
`results/` are all right there and anything you save into `results/` lands in
your repo for submission. Keep bulky build/fuzz output in `work-out/` (git-
ignored). The xpdf **source** is at `/src/xpdf-3.02` — you compile it yourself in
Step 1. A ready seed is provided at `/opt/hw/seeds/`. Builds live in the
container session; if you exit and re-enter, rebuild (or build under `/work` to
keep them).

---

## 1. Build the target manually

AFL++ ships compiler wrappers (`afl-clang-fast`, `afl-clang-fast++`) that insert
coverage instrumentation at every edge. You build xpdf exactly as normal, but
with those as the compiler.

```bash
cd /src/xpdf-3.02

# Configure with the AFL++ compilers.
CC=afl-clang-fast CXX=afl-clang-fast++ \
  CFLAGS="-fcommon -O2 -g" \
  CXXFLAGS="-fcommon -O2 -g -std=gnu++98 -w" \
  ./configure --enable-a4-paper

make -j"$(nproc)"
```

Notes:

- **`-fcommon`** is required — xpdf 3.02 predates the `-fno-common` default of
  modern compilers and will not link without it.
- **`-std=gnu++98 -w`** keeps this 20-year-old C++ compiling quietly.
- The tools land in `xpdf/pdftotext`, `xpdf/pdftoppm`, `xpdf/pdfimages`, etc.
  We fuzz **`pdftotext`** first: it is fast and exercises the parser, the
  stream/filter decoders, and text extraction.

Confirm it is instrumented (a normal `gcc` build would print `0 tuples`):

```bash
echo hello | afl-showmap -o /dev/null -- ./xpdf/pdftotext work-out/in/seed.pdf /dev/null
# -> "Captured NNNN tuples ..."  (this build: ~1176 edges on the seed)
```

---

## 2. Build with AddressSanitizer (ASAN)

Plain AFL++ only catches bugs that crash the process (SIGSEGV/SIGABRT). ASAN
turns **silent memory errors** — heap/stack overflows, use-after-free — into
loud, immediate aborts with a full report, so you catch far more and get a
diagnosis for free. Build a **separate** ASAN binary (keep the fast one from
Step 1 for raw throughput):

```bash
cd /src/xpdf-3.02
make clean
AFL_USE_ASAN=1 \
CC=afl-clang-fast CXX=afl-clang-fast++ \
  CFLAGS="-fcommon -O1 -g -fsanitize=address" \
  CXXFLAGS="-fcommon -O1 -g -std=gnu++98 -w -fsanitize=address" \
  ./configure --enable-a4-paper
AFL_USE_ASAN=1 make -j"$(nproc)"
cp xpdf/pdftotext work-out/pdftotext.asan   # save it before rebuilding non-ASAN
```

- **`AFL_USE_ASAN=1`** tells the AFL++ wrappers to instrument for ASAN too.
- Use **`-O1`** (not `-O2`): better stack traces, fewer optimized-away bugs.
- ASAN is ~2× slower and uses much more RAM, so the usual workflow is: **fuzz
  with the fast binary, then re-run each saved crash through the ASAN binary**
  to get the report:

```bash
ASAN_OPTIONS=abort_on_error=1:symbolize=1 \
  work-out/pdftotext.asan work-out/repro.pdf /dev/null
```

---

## 3. Prepare a seed corpus

AFL needs at least one valid input to mutate. A ready seed is provided:

```bash
mkdir -p work-out/in
cp /opt/hw/seeds/seed.pdf work-out/in/
```

Keep seeds **small and valid**. A few tiny, structurally different PDFs beat one
big one. AFL will grow this corpus itself as it discovers new paths.

---

## 4. Run AFL++ manually

First, one-time host/kernel prep (AFL will refuse to start otherwise):

```bash
# inside the container these are usually already handled; on a native Linux host:
echo core | sudo tee /proc/sys/kernel/core_pattern     # so crashes aren't sent to a handler
# if AFL complains about CPU scaling:
export AFL_SKIP_CPUFREQ=1
```

Then launch the fuzzer:

```bash
afl-fuzz -i work-out/in -o work-out/out -- ./xpdf/pdftotext @@ /dev/null
```

- **`-i work-out/in`** — seed directory. **`-o work-out/out`** — where AFL writes the
  queue, crashes, hangs, and stats.
- **`@@`** — AFL replaces this with the path to each generated test file. (If a
  target reads stdin instead, you omit `@@`.) Here `pdftotext <file> <txt-out>`
  — we send the text output to `/dev/null`.
- Add **`-x`** with a PDF dictionary to find deeper bugs faster, and **`-M`/`-S`**
  to run multiple synchronized instances (one per core).

You should see the AFL++ status screen appear within a few seconds. Leave it
running. `Ctrl-C` stops it; re-running the same command **resumes** from
`work-out/out` (use `-i -` to force resume).

---

## 5. Is it actually making progress?

Watch the status screen — these are the signs of a **healthy** run:

| Look at | Healthy | Trouble |
|---|---|---|
| `exec speed` | hundreds–thousands/sec | < 100/sec → target too slow, add a harness (Step 9) |
| `corpus count` / `total paths` | **rising** | flat from the start → seed not valid (use the provided seed) |
| `map density` / `count coverage` | slowly climbing | stuck at the seed's value → no new coverage |
| `stability` | ~100% | < 90% → nondeterminism (uninit memory, time/PID use) |
| `last new find` | recent | "none seen yet" after minutes → check seeds/`@@` |

Quick out-of-band checks (run in a second shell):

```bash
afl-whatsup work-out/out          # summary across all instances
cat work-out/out/default/fuzzer_stats     # the raw numbers (see Step 6)
```

**First thing to verify:** the corpus grows past 1. If it never leaves the seed
count, AFL isn't reaching new code. Confirm your seed parses:

```bash
./xpdf/pdftotext work-out/in/seed.pdf /dev/null; echo "exit=$?"   # want 0
```

If it is non-zero, start from the provided seed at `/opt/hw/seeds/seed.pdf`.

---

## 6. Every fuzzing metric, explained

`work-out/out/default/fuzzer_stats` is the ground truth. Real values from a **80 s**
run of `pdftotext @@` on a single seed, one core, no dictionary:

```
execs_per_sec     : 2707.99      # throughput. THE number to optimize.
execs_done        : 216691       # total inputs run so far
corpus_count      : 865          # inputs kept because each hit new coverage
corpus_favored    : 140          # the minimal subset covering all known edges
pending_favs      : 68           # favored inputs not yet fuzzed (drains to 0)
pending_total     : 776          # all inputs not yet fuzzed this cycle
cycles_done       : 0            # full passes over the queue (0 = still exploring)
max_depth         : 6            # mutation "generations" deep from a seed
stability         : 100.00%      # same input -> same coverage. want ~100%.
bitmap_cvg        : 9.25%        # fraction of the coverage map touched
edges_found       : 1823         # distinct control-flow edges reached
total_edges       : 19706        # edges the compiler instrumented in this binary
saved_crashes     : 0            # UNIQUE crashing inputs found
saved_hangs       : 0            # inputs exceeding the timeout
last_find         : <ts>         # wall-clock of the last new-coverage input
slowest_exec_ms   : ...          # worst-case single execution
```

How to read them:

- **Coverage = `edges_found` / `total_edges`.** Here 1823 / 19706 ≈ **9.25%**.
  This is the single best measure of "how much of the program have we tested."
  It rises fast at first, then logarithmically slows.
- **`cycles_done`** low/zero means AFL is still finding new paths — good, keep
  going. Once it climbs and coverage flatlines, you have hit a plateau: add a
  dictionary, better seeds, or a harness.
- **`stability` < 100%** means the same input sometimes takes different paths.
  Common causes here: uninitialized memory, use of time/PID/addresses. Below
  ~90% it degrades AFL's signal.
- **`saved_crashes`** is what you submit. Each is a **unique** crash (distinct
  coverage), stored under `work-out/out/default/crashes/`.

---

## 7. Coverage over time

AFL logs a time series to `work-out/out/default/plot_data`. Columns:

```
relative_time, cycles_done, cur_item, corpus_count, pending_total,
pending_favs, map_size, saved_crashes, saved_hangs, max_depth,
execs_per_sec, total_execs, edges_found
```

Plot it into PNGs (needs gnuplot):

```bash
afl-plot work-out/out/default work-out/plot && ls work-out/plot   # -> *.png you can open
```

`edges_found` and `map_size` (the coverage %) versus `relative_time` is the
curve to put in your writeup. Expect a **steep rise in the first minutes, then a
long slow climb**. If the curve is flat from t=0, your seeds or `@@` are wrong.
Compare corpus/coverage across configurations (with vs. without a dictionary,
argv vs. harness) by overlaying their `plot_data`.

To measure coverage of an arbitrary corpus at any time:

```bash
afl-cmin -i work-out/out/default/queue -o work-out/min -- ./xpdf/pdftotext @@ /dev/null
# -> the minimal set of inputs preserving all edges; its size ≈ your real coverage
```

---

## 8. Source-level coverage with gcov + gcovr

AFL's `edges_found` measures the *instrumented map*. For the assignment you also
report **source line/branch coverage** with a **separate gcov build** (do not mix
it with your AFL build). The idea: compile with `--coverage`, replay your corpus
through that binary, then summarize with `gcovr`.

Manual build:

```bash
cd /src/xpdf-3.02
make clean
CC=gcc CXX=g++ \
  CFLAGS="-fcommon -O0 -g --coverage" \
  CXXFLAGS="-fcommon -O0 -g -std=gnu++98 -w --coverage" \
  LDFLAGS="--coverage" ./configure --enable-a4-paper
make -j"$(nproc)"
```

Replay a corpus and summarize the **core parser files** (the graded set):

```bash
for f in work-out/out/default/queue/id* work-out/in/*; do
  ./xpdf/pdftotext "$f" /dev/null >/dev/null 2>&1 || true
done
cd xpdf
gcovr . --filter '(XRef|Parser|Lexer|Stream|Object|Dict|Array|PDFDoc)\.cc' \
       --print-summary
gcovr . --filter '(XRef|Parser|Lexer|Stream|Object|Dict|Array|PDFDoc)\.cc' \
       --html --html-details -o results/coverage.html
```

Or just run the helper, which does the build + replay + report for you:

```bash
tools/coverage.sh work-out/out/default/queue work-out/in   # -> results/coverage.html
```

**What to expect:** a 2-minute, single-core, no-dictionary run reaches ≈ **26.5%
line / 23% branch** on the core files. Beat that with a better dictionary
(`-x dict/pdf.dict`), more/varied seeds, a longer run, and the persistent harness
(next section) — then re-measure. `gcov` counters are cumulative across runs;
delete the `*.gcda` files to reset.

## 9. The harness you should develop

`pdftotext @@` re-launches the whole process for **every** input (~2,700 exec/s
here). Most of that time is process startup and `GlobalParams` init, not
parsing. A **persistent-mode harness** stays in one process and loops over
AFL's shared-memory test case, so throughput jumps roughly **10×**.

A complete, working harness is in **`harness/fuzz_pdf.cc`**. Its shape:

```cpp
__AFL_FUZZ_INIT();
int main() {
  globalParams = new GlobalParams("");     // expensive init: do it ONCE, outside the loop
  __AFL_INIT();                            // deferred forkserver starts here
  unsigned char *buf = __AFL_FUZZ_TESTCASE_BUF;
  while (__AFL_LOOP(10000)) {              // reuse the process 10k times, then respawn
    int len = __AFL_FUZZ_TESTCASE_LEN;
    // prepend the sample document's header line, wrap it in a MemStream
    // (no temp file), parse + extract text, then free everything.
    ...
    PDFDoc *doc = new PDFDoc((BaseStream *)mem);
    if (doc->isOk()) { /* TextOutputDev + displayPages */ }
    delete doc;
  }
}
```

Key design points (why it is written this way):

- **`__AFL_INIT()` after the heavy setup** = *deferred forkserver*: AFL forks
  from a snapshot taken *after* `GlobalParams` is built, skipping that cost every
  iteration.
- **`__AFL_LOOP(10000)`** = *persistent mode*: one process handles 10 000 inputs
  before restarting, amortizing fork cost. Lower the number if state leaks
  between iterations hurt `stability`.
- **In-memory `MemStream`, no temp files** — file I/O would erase the speed win.
- **The harness reuses the sample document's header line** and mutates only the
  body below it. Your seed for the harness is therefore that body, provided at
  `/opt/hw/seeds/hseed`.

Build and run it:

```bash
XPDF=/src/xpdf-3.02 bash harness/build_harness.sh      # -> harness/fuzz_pdf
mkdir -p work-out/hin; cp /opt/hw/seeds/hseed work-out/hin/
afl-fuzz -i work-out/hin -o work-out/hout -- harness/fuzz_pdf
# ASAN harness: AFL_USE_ASAN=1 XPDF=/src/xpdf-3.02 bash harness/build_harness.sh
```

The build links the harness against all xpdf object files **except** the tools'
own `main()`s, plus `libGoo`, `libfofi`, and `libsplash`.

### What to expect

Measured on this setup, same seed, 50–80 s each:

| Mode | exec/s | edges (of total) | unique crashes |
|---|---|---|---|
| `pdftotext @@` (argv) | ~2,700 | 1,823 / 19,706 | 0 in 80 s |
| persistent harness | **~27,500** (~10×) | ~1,700 / 25,154 | **14 in 50 s** |

The harness both runs ~10× faster **and** links more code (it calls
`displayPages`, so `total_edges` is higher), which is why crashes appear so much
sooner. The status screen will show `target_mode : persistent shmem_testcase
deferred` when it is working.

---

## 10. Triage and reproduce a crash

Harness crash files are *bodies*. To reproduce through the normal tool,
reassemble a full PDF by prepending the sample's header line, then run the
**ASAN** binary for a diagnosis:

```bash
cf=work-out/hout/default/crashes/id:000000*        # pick a crash
( head -n1 /opt/hw/seeds/seed.pdf; cat "$cf" ) > work-out/repro.pdf
work-out/pdftotext.asan work-out/repro.pdf /dev/null  # ASAN prints the bug + stack
echo "exit=$?"                                    # 139=SIGSEGV, 134=SIGABRT
```

A verified example from this setup reproduced as a **SIGSEGV (exit 139)** in
`pdftotext` on a 593-byte input — a genuine xpdf bug, not a harness artifact.

De-duplicate before you submit (many crash files are the same bug):

```bash
afl-cmin -C -i work-out/hout/default/crashes -o results/crashes -- harness/fuzz_pdf
```

Then bucket by the top few stack frames from the ASAN reports. Submit the unique
crashing inputs plus your writeup (coverage curve, exec/s, crash count, and a
root-cause guess for one — look at the `Parser`/`XRef`/`Stream` call chain).

---

## 11. Quick troubleshooting

- **Corpus never grows / instant "0 tuples"** → not instrumented; you used plain
  `gcc`/`clang`. Rebuild with `afl-clang-fast`.
- **Inputs rejected / corpus stuck at the seed** → start from the provided seed
  (`/opt/hw/seeds/seed.pdf`, and `/opt/hw/seeds/hseed` for the harness) rather
  than an arbitrary PDF.
- **`exec speed` very low** → build and use the persistent harness (Step 9).
- **`stability` low** → lower `__AFL_LOOP` count; suspect uninitialized memory.
- **AFL refuses to start** (`core_pattern`, CPU governor) → see Step 4.
- **ASAN out-of-memory** → add `-m none` to `afl-fuzz` (disable the memory cap).
