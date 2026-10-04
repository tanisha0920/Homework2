# results/ — your submission artifacts

Put your fuzzing evidence here (committed to your repo):

- `crashes/` — your **unique** crashing inputs (after de-duplication). For
  harness-found crashes this is the PDF **body**; reassemble a full PDF to
  reproduce (see FUZZING_GUIDE.md §10).
- `corpus/` — your final minimized seed corpus (`afl-cmin` output) and any seeds
  you added.
- `coverage.html` — the gcovr report from `tools/coverage.sh`.
- `plot/` — the `afl-plot` PNGs (coverage over time).
- `fuzzer_stats.txt` — a copy of your run's `fuzzer_stats`.
- `dictionary.dict` — your improved PDF dictionary (start from `dict/pdf.dict`).

Do NOT commit `work/` build trees or the multi-GB `out/` directory — only the
distilled artifacts above.
