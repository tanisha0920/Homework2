# CS-5187 HW-2: Fuzzing xpdf 3.02

You will fuzz **xpdf 3.02** with **AFL++**.
You run everything locally with **Docker** — install Docker, nothing else.

> **Read [`ASSIGNMENT.md`](ASSIGNMENT.md) for the graded tasks, rubric, and
> deliverables**, and [`FUZZING_GUIDE.md`](FUZZING_GUIDE.md) for the manual
> how-to behind every step. You do all the work by hand — there is no
> one-command fuzzing shortcut.

**Repo layout**

| Path | What it is |
|---|---|
| `ASSIGNMENT.md` | The graded assignment: tasks, thresholds, rubric (25 marks) |
| `FUZZING_GUIDE.md` | Manual how-to: build, ASAN, run AFL++, coverage, harness, triage |
| `build.sh` | Builds the Docker *environment* image (toolchain + source). That's all it does. |
| `tools/` | Helpers (`coverage.sh`) |
| `harness/` | Persistent-mode harness (`fuzz_pdf.cc`) + build script |
| `dict/pdf.dict` | Starter PDF dictionary for AFL (`-x`) |
| `results/` | **Your submission artifacts go here** (see `results/README.md`) |

(A ready-to-use seed is provided inside the image at `/opt/hw/seeds/`.)

## Get the assignment (Classroom 50)

Accept the assignment link; Classroom 50 creates your private GitHub repo.
Clone it and build:

```bash
git clone <your-assignment-repo-url> hw-2-fuzzing
cd hw-2-fuzzing
./build.sh
```

That's it for setup — no credentials, no configuration. `build.sh` only builds
the Docker image (AFL++ toolchain + the xpdf source); it does **not** build or
run xpdf for you.

## Do the assignment

Open a shell in the image and work through the tasks **by hand** — building
`pdftotext`, the ASAN build, running AFL++, writing the harness, measuring
coverage, and triaging crashes. Every command is in
[`FUZZING_GUIDE.md`](FUZZING_GUIDE.md); the graded tasks and deliverables are in
[`ASSIGNMENT.md`](ASSIGNMENT.md).

## Notes

- Start fuzzing from the provided seed at `/opt/hw/seeds/` (inside the image).
- Submit crashes you found yourself.
- Requires Docker. First build downloads the AFL++ image (~5 GB) once.
