# CS-5187 HW-2: Coverage-Guided Fuzzing of xpdf


You will systematically fuzz-test the **xpdf 3.02** PDF toolchain with
**AFL++** to discover real security vulnerabilities, measure how much of the code
your fuzzing exercises, and report on what you found and why.

## Learning outcomes

- Build and instrument a real C/C++ target for coverage-guided fuzzing.
- Drive AFL++, confirm it is making progress, and read fuzzing telemetry.
- Measure and improve **source-level line/branch coverage** (gcov + gcovr).
- Write a **persistent-mode harness** and reason about throughput.
- Triage, de-duplicate, and root-cause crashes; map them to CWEs/CVEs.

## Getting started

1. Accept the Classroom 50 assignment and clone your repo.
2. Read **`README.md`** (setup) and **`FUZZING_GUIDE.md`** (the manual how-to for
   every command used below).
3. Install Docker. All builds/fuzzing run in the provided container image.

---

## Task 1 — Fuzzing setup and a healthy run (5 marks)

1. Build the **AFL-instrumented** `pdftotext` manually (FUZZING_GUIDE §1) and
   confirm instrumentation with `afl-showmap` (non-zero tuples).
2. Build a **separate ASAN** binary (FUZZING_GUIDE §2).
3. Prepare a seed corpus and run AFL++ (FUZZING_GUIDE §3–4).
4. Demonstrate the run is **making progress**: corpus count rising, coverage
   climbing, `stability` near 100% (FUZZING_GUIDE §5).

**Submit:** `results/fuzzer_stats.txt` (a copy of your `fuzzer_stats`) and
`results/plot/` (afl-plot PNGs) showing coverage over time.

---

## Task 2 — Code coverage (5 marks)

Measure **source-level** coverage with a gcov build and `gcovr`, over the **core
parser/decoder files**: `XRef.cc`, `Parser.cc`, `Lexer.cc`, `Stream.cc`,
`Object.cc`, `Dict.cc`, `Array.cc`, `PDFDoc.cc`.

```bash
# inside the container, after fuzzing has produced work-out/out/default/queue
tools/coverage.sh work-out/out/default/queue work-out/in
```

This builds the gcov binary, replays your corpus, and prints line/branch/function
coverage plus writes `/work/coverage.html`.

Then **improve** coverage by:
- expanding and minimizing your **seed corpus** (`afl-cmin`), and
- developing a **PDF dictionary** (start from `dict/pdf.dict`; `afl-fuzz -x`).

**Reference baseline:** replaying a 2-minute, single-core, no-dictionary run
gives ≈ **26.5% line / 23% branch** on the core files. You are expected to beat
this substantially.

**Marking (core files, line coverage; branch used as a tie-breaker/quality
signal):**

| Coverage achieved | Marks |
|---|---|
| < 35% line | 0–1 (must beat the naive baseline) |
| ≥ 35% line | 2 |
| ≥ 45% line and ≥ 30% branch | 3 |
| ≥ 55% line and ≥ 38% branch | 4 |
| ≥ 55% line, ≥ 38% branch, **and** a clearly improved dictionary + minimized corpus | 5 |

> Thresholds are provisional pending the instructor's reference-solution
> calibration; see INSTRUCTOR notes.

**Submit:** `results/coverage.html`, your final `results/corpus/`, and
`results/dictionary.dict`.

---

## Task 3 — Vulnerability discovery (9 marks)

Find **at least three unique** vulnerabilities in xpdf via fuzzing. Focus on:

- **Denial of service** — crashes or hangs (e.g. uncontrolled recursion,
  CWE-674; NULL-pointer dereference, CWE-476).
- **Memory-safety faults** — stack/heap buffer overflow (CWE-121/122),
  use-after-free / double-free (CWE-416/415), out-of-bounds read (CWE-125).

For **each** vulnerability:

1. Provide the **crashing input** in `results/crashes/` (de-duplicated — see
   below). For harness-found crashes this is the PDF body; reassemble a full PDF
   to reproduce (FUZZING_GUIDE §10).
2. Give **reproduction steps** using the **ASAN** binary, and paste the ASAN
   report (or the signal, e.g. SIGSEGV/exit 139) in your report.
3. **Classify** it with a CWE and describe the root cause (which function, why).

**De-duplicate** before submitting (many crash files are the same bug):

```bash
afl-cmin -C -i /work/out/default/crashes -o results/crashes -- <your target> ...
```

**At least one** of your three must be mapped to a **documented CVE** affecting
this code. xpdf 3.02 has many; start from the authoritative list
(<https://www.cvedetails.com/vulnerability-list/vendor_id-539/Xpdf.html> / NVD).
Well-known examples: the `Parser::getObj` uncontrolled-recursion DoS
(CVE-2019-13288, present in this code path) and the `StreamPredictor` integer
overflow (CVE-2007-3387). Justify your mapping with the CWE and code location.

**Marking:** 3 marks per verified, unique, correctly-classified vulnerability
(3 × 3 = 9). **Bonus:** +1.5 per additional verified unique vulnerability, up to
the assignment cap.

---

## Task 4 — Report (6 marks)

Submit a **PDF report** (`results/report.pdf`) covering:

- **Methodology** — how you built, seeded, and ran the fuzzer; dictionary and
  corpus decisions; how you used the persistent harness and what speedup you
  measured.
- **Coverage** — your coverage-over-time curve and final numbers; what code
  remained uncovered and why; what you did to improve it.
- **Findings** — each vulnerability: input, repro, ASAN evidence, CWE, root
  cause, and (for the CVE one) the mapping.
- **Reflection** — answer explicitly:
  1. Which parts of xpdf were hardest to reach, and what limited coverage?
  2. How did the persistent harness change throughput and the bugs you found?
  3. What are AFL++'s strengths and limitations you observed on this target?
  4. How would generational/structure-aware fuzzing compare to the mutational
     approach you used?

**Policy:** you may use AI tools for coding help, but the **report prose must be
your own** (grammar/spell-check is fine). State any tools used.

---

## Deliverables (in your repo)

```
results/
  fuzzer_stats.txt      # Task 1
  plot/                 # Task 1 (afl-plot PNGs)
  coverage.html         # Task 2
  corpus/               # Task 2 (final minimized seeds)
  dictionary.dict       # Task 2
  crashes/              # Task 3 (unique crashing inputs)
  report.pdf            # Task 4
```

Do **not** commit `work/` build trees or multi-GB `out/` directories — only the
distilled artifacts above. `.gitignore` already excludes them.

## Rubric (25 marks)

| Component | Marks |
|---|---|
| Task 1 — workable, healthy fuzzing setup | 5 |
| Task 2 — code coverage (+ dictionary/corpus quality) | 5 |
| Task 3 — 3 unique vulnerabilities (CWE + repro; ≥1 CVE) | 9 |
| Task 4 — report quality and reflection | 6 |
| **Total** | **25** |
| Bonus — extra verified unique vulnerabilities | +1.5 each |

## Academic integrity

Submit only work you did yourself. Sharing or copying crashing inputs, seed
corpora, harnesses, or reports between students is an academic-integrity
violation. Do your own fuzzing.
