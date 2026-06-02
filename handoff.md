# Handoff — `bash-analyzer`

> **Purpose of this file.** Complete knowledge transfer for the *next* Claude Code
> session (or human) picking up this project. Read it together with
> [`CLAUDE.md`](CLAUDE.md). Everything here is concrete and executable.
>
> **Last updated:** 2026-06-02 · **Branch of record:** `main` (the
> `refactor/hardening` work has been merged and pushed; CI is green).

### Related resources

- **Portfolio page (public):** https://aalopez76.github.io/projects/bash_analyzer/
  — the owner's personal site showcases this project (the *project*, not the
  repo). **Pending non-code task:** enrich that page based on the latest state
  (M6 complete, hardening + CI). It must read as a **professional presentation**
  for a portfolio audience, **not** a technical summary — lead with the problem
  it solves, the value, and a few highlights; keep deep technical detail out.

---

## ⚠️ Read this first: what kind of project this is

This is **NOT a machine-learning / Python project.** There are **no models, no
training, no experiments, no Python, no dependency manager, no DVC, no MLflow,
no served API.** Do not look for `src/train.py`, `configs/base.yaml`,
`requirements.txt`, `poetry.lock`, `models/`, or an MLflow UI — **they do not
exist and should not be created** unless the project's purpose fundamentally
changes.

`bash-analyzer` is a **terminal-based CSV/TSV analysis suite written in pure
Bash** (~1,060 lines) with an interactive `whiptail` UI. Throughout this
document, wherever a typical ML handoff would mention an ML artifact, the
**real Bash equivalent** is given instead, and ML-only concepts are explicitly
marked **N/A** with the reason.

| ML handoff concept | Reality in this repo |
|---|---|
| Language / framework | Bash + `whiptail` + GNU coreutils/awk |
| Dependency manager / lockfile | None. Runtime preflight in [`functions/common.sh`](functions/common.sh) (`require_tools`) |
| Lint | `shellcheck` (see [`.shellcheckrc`](.shellcheckrc), `make lint`) |
| Tests | Bash scripts under [`tests/`](tests/) driven by a `whiptail` mock |
| Task runner | [`Makefile`](Makefile) (`test`/`lint`/`run`/`check`) |
| CI/CD | GitHub Actions ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) |
| DVC (data versioning) | **N/A** — operates on arbitrary user files; no managed dataset |
| MLflow / W&B (tracking) | **N/A** — no models or experiments |
| Trained models / inference | **N/A** — the app produces reports/exports, not predictions |

---

## 1. Project overview

**What it is.** An interactive command-line tool to inspect, audit, search,
join and export tabular data (CSV/TSV) without leaving the terminal. The user
launches it, picks a file through a built-in file explorer, and chooses one of
five analysis modules from a menu.

**Why it exists / business problem.** Data-ops, technical-support and ad-hoc
analysis work often happens on machines where opening Excel/Python/Pandas is
impractical (a server over SSH, a locked-down support box, WSL). This tool gives
non-experts a guided, menu-driven way to answer "what's in this file, is it
clean, can I filter/join/convert it?" using only Bash and standard Unix tools.

**Success metric.** This is a utility, not a model, so success is **functional
and operational**, not statistical:
- The 5 modules produce correct reports/exports on real CSV/TSV files.
- The full test suite is green (currently **8/8 test scripts**).
- CI passes (`make check`) on every push/PR.
- It runs unmodified on Linux and Windows (WSL / Git Bash).

There is **no accuracy/precision/recall metric** — that would be N/A here.

---

## 2. Architecture snapshot

**Stack.** Bash 5.x · `whiptail` (TUI dialogs) · GNU coreutils (`awk`, `grep`,
`sort`, `uniq`, `head`, `tail`, `wc`, `find`, `sha256sum`, `mktemp`, `tr`,
`realpath`). No build step, no compiled artifacts, no external libraries.

**Component diagram.**

```
                         ┌──────────────────────────────┐
                         │            app.sh             │  entry point
                         │  - checks whiptail            │
                         │  - file picker (navigate_…)   │
                         │  - 6-option main menu loop    │
                         └───────────────┬──────────────┘
                                         │ sources
                                         ▼
                         ┌──────────────────────────────┐
                         │     functions/common.sh       │  shared library
                         │  - require_tools (preflight)  │
                         │  - detect_delimiter           │
                         │  - load_selected_file (CRLF)  │
                         │  - navigate_and_select        │
                         └───────────────┬──────────────┘
              dispatches (bash subshell) │ each module re-sources common.sh
        ┌───────────────┬────────────────┼────────────────┬───────────────┐
        ▼               ▼                ▼                ▼               ▼
 file-scan.sh    data-quality.sh     search.sh      csv-joiner.sh    format.sh
  (Module 1)       (Module 2)        (Module 3)       (Module 4)      (Module 5)
        │               │                │                │               │
        └───────────────┴────────────────┴────────────────┴───────────────┘
                                         │ writes
                                         ▼
                                    output/*.txt,*.csv,*.sql,*.json,*.md
                                         │ on exit
                                         ▼
                              move.sh → archives output/*.txt → history/
```

**Shared state between menu invocations** (small text files, gitignored):

| File | Written by | Read by |
|---|---|---|
| `functions/directory.txt` | `app.sh`, `csv-joiner.sh` | `csv-joiner.sh`, `file-search.sh` |
| `functions/selected_file.txt` | `app.sh`, `csv-joiner.sh` | all analysis modules |

**Key design decisions and their justification** (these are the "model choices"
of a Bash project):

- **One module per responsibility, dispatched as a subshell** (`bash
  "$functions_dir/<module>.sh"`). Keeps each module independently testable and
  prevents one module's `set`/`trap`/variable state from leaking into another.
- **CRLF normalization into a tmpfile** ([`common.sh:load_selected_file`](functions/common.sh)).
  Windows-origin files (`\r\n`) break awk type detection and field comparison
  under WSL. The file is piped through `tr -d '\r'` into a `mktemp`, and
  `$selected_file` points at that copy for the module's lifetime. **The original
  file is never modified** — this is a hard invariant (see §9).
- **Delimiter detection from line 2, not line 1** ([`common.sh:detect_delimiter`](functions/common.sh)).
  Line 1 is the header and may not represent the data's delimiter reliably; the
  function tests tab → semicolon → comma on the first data row.
- **Safe awk: user input passed via `-v`, never interpolated as code.** The
  column-filter (`search.sh` action 2) and regex search build awk *variables*,
  not awk *programs*, from user input — this prevents awk-injection. There is a
  regression test guarding this property (`integration_test.sh` TEST 4).
- **`set -uo pipefail` everywhere, but NOT `-e`.** `errexit` is deliberately
  omitted because these interactive scripts rely on legitimate non-zero exits
  (whiptail "Cancel", `grep` with no match, post-decrement arithmetic). Adding
  `-e` would abort them mid-flow. This rationale is commented at the top of
  every module — **do not "fix" it by adding `-e`** (see §9).

**Data pipeline.** There is no training pipeline. The "pipeline" is: *pick file
→ normalize CRLF → detect delimiter → run one module's awk/coreutils logic →
preview → optionally save to `output/` → archive on exit.*

---

## 3. Completed work (the hardening effort)

The original tool worked but had no safety nets. A full audit + refactor was
done on branch `refactor/hardening`. (This maps to "Fases 1–3" in the prompt;
here the phases are the hardening phases, since there are no ML phases.)

**Phase 1 — Safety net (no logic changes)**
- [`Makefile`](Makefile): `lint`, `test`, `run`, `check`, `help`.
- [`tests/run_tests.sh`](tests/run_tests.sh): aggregate runner, returns non-zero if any script fails.
- [`.github/workflows/ci.yml`](.github/workflows/ci.yml): installs `whiptail`+`shellcheck` on `ubuntu-latest`, runs `make check` on every push/PR.
- [`.shellcheckrc`](.shellcheckrc): `external-sources=true`, silences SC1091 for the dynamic `source common.sh`.

**Phase 2 — Robustness**
- `set -uo pipefail` added to `app.sh`, `move.sh` and all modules.
- Input validation: `file-scan.sh` now validates `num_lines` is numeric.
- `-u` safety guards on associative-array lookups.

**Phase 3 — Test coverage**
- Coverage went from **3 → 8 test scripts**. Added: CSV Joiner (INNER/LEFT),
  Data Quality, Format (Clean CSV / JSON / Markdown), Search sort/unique, and a
  dependency-preflight test, using deterministic fixtures in
  [`tests/fixtures/`](tests/fixtures/).
- Plus: dependency preflight (`require_tools`), README platform honesty
  (Linux/WSL/Git Bash; macOS + CSV-quoting documented as limitations), and a
  de-duplication refactor in `search.sh`.

**Artifacts produced** (where things live):
- **Reports/exports at runtime:** `output/` (gitignored), archived to `history/`
  (gitignored) on exit. These are **not** committed.
- **Audit & plan:** [`docs/AUDIT.md`](docs/AUDIT.md), [`docs/REFACTOR_PLAN.md`](docs/REFACTOR_PLAN.md) (includes an execution-status table).
- **Example dataset:** [`data_sets/data.csv`](data_sets/data.csv) (50 data rows, employee data — used by some tests).
- **Test fixtures:** [`tests/fixtures/`](tests/fixtures/) (`employees.csv`, `departments.csv`, `quality.csv`, `malformed.csv`).

> **No DVC remote, no MLflow runs, no model registry** — there is nothing of
> that kind to pull. (N/A, by design.)

---

## 4. Current status

> **The project is considered COMPLETE for its current purpose (2026-06-02).**
> All high-value safety and correctness work is done; the remaining backlog is
> new capability / polish, gated on a real driver (see §11). Reopen only with a
> concrete need.

**What works:** all 5 modules; full suite **9/9 green**; CI **green on `main`**
(lint + test); strict-mode + preflight active; CRLF-safe; awk-injection-safe;
**CSV-quoting-aware across all 5 modules (M6 complete)**.

**What is NOT done / known issues / technical debt:**
- ✅ **Branch merged and pushed (2026-06-02).** `refactor/hardening` was merged
  into `main` and pushed. CI ran for the first time, surfaced ~48 shellcheck
  findings (all warning/style), which were resolved in commit `fa6dc90`; CI is
  now green. `shellcheck` was installed locally via winget (0.11.0) for the fix.
- 🟡 **macOS / BSD unsupported.** Code relies on GNU behaviour: `sha256sum`,
  `mktemp --suffix`, `realpath`, GNU `awk` regex flag `/i`. On macOS these
  differ (`shasum`, no `--suffix`). README documents this; not yet fixed.
- ✅ **CSV quoting (M6) — COMPLETE (all 5 modules, 2026-06-02).** A quoting-aware
  splitter lives in `common.sh` (`csv_fpat` builds a gawk `FPAT`; `AWK_UNQUOTE`
  is an injectable awk `unq()` function). All modules now split fields with
  `-v FPAT="$(csv_fpat "$delimiter")"` (or `patsplit()` in `csv-joiner.sh`, which
  uses per-file `split()` rather than `FS`) and `unq()` values where they are
  compared/displayed; JOIN keys are unquoted so a quoted `"30"` matches `30`.
  Covered by `tests/test_csv_quoting.sh` (23 assertions across all 5 modules)
  with fixtures `quoted.csv`, `qjoin_left.csv`, `qjoin_right.csv`. **Still out of
  scope:** embedded *newlines* inside quoted fields (the row-count and
  duplicate-detection idioms are line-based); the joiner still emits comma-CSV
  regardless of input delimiter (a pre-existing, separate concern).
- 🟢 **No non-interactive/CLI mode.** The app is whiptail-only; automation is
  only possible via the test mock.
- 🟢 **`shellcheck` now installed locally** (winget `koalaman.shellcheck`,
  0.11.0). CI uses Ubuntu's apt version; lint locally if convenient, but trust
  CI as the source of truth. The binary lives under
  `…/WinGet/Packages/koalaman.shellcheck_*/shellcheck.exe` (not on the Git Bash
  PATH unless you re-source the profile).
- ✅ **`tests/debug_hash.sh` deleted (2026-06-02).** It was a leftover debug
  helper with a hardcoded path, not part of the `run_tests.sh` suite.

"Model limitations" → **N/A** (no model).

---

## 5. Reproducibility quick-start (from zero)

No virtualenv/conda/poetry — it's Bash. Steps to go from nothing to a verified
working checkout:

```bash
# 1. Clone
git clone https://github.com/aalopez76/bash-analyzer.git
cd bash-analyzer

# 2. Use the hardened branch (until it is merged to main)
git checkout refactor/hardening

# 3. Install dependencies (Debian/Ubuntu/WSL example)
sudo apt-get update
sudo apt-get install -y whiptail shellcheck make
#   coreutils/awk/grep/sort/etc. are already present on any Linux/WSL/Git Bash.

# 4. Smoke test — this is the "does everything work?" check
make test
#   Expect: "AGGREGATE RESULT  passed=8  failed=0" and "ALL SUITES PASSED".
#   Equivalent without make:  bash tests/run_tests.sh

# 5. (Optional) Lint — needs shellcheck installed
make lint

# 6. Launch the app
./app.sh        # or: make run
```

**Environment notes (important):**
- **There is no `dvc pull`, no data/model download.** (N/A.) The only data is
  the small committed `data_sets/data.csv` and `tests/fixtures/*` — already in
  the repo.
- **Windows / Git Bash quirks** (the current dev machine): `make` is
  `/c/Program Files/Git/mingw64/bin/make`; the [`Makefile`](Makefile) sets
  `SHELL := /usr/bin/bash` precisely so recipes don't get launched via cmd.exe
  and fail. `shellcheck` is typically not installed there; rely on CI for lint.
  Symlinks (`ln -s`) don't work in Git Bash, so tests avoid them.

---

## 6. How to invoke Claude Code effectively (next session)

Paste/start the next session with intent like this:

> "Read [`CLAUDE.md`](CLAUDE.md) first, then [`handoff.md`](handoff.md). This is a
> **Bash** CSV-analysis tool — there is no Python/ML/DVC/MLflow, so don't look
> for or create those. The working branch is `refactor/hardening`. Before
> changing any code, run `make test` and confirm 8/8 green. Tell me the concrete
> task; don't run anything outside the repo, and don't push/merge or install
> global packages without my explicit confirmation."

Rules for the agent:
1. **`CLAUDE.md` → `handoff.md` → ask for the concrete task.** In that order.
2. **Never assume ML.** If a request implies models/training, stop and confirm
   scope — it would be a fundamental change to the project.
3. **Respect the invariants in §9** (original files immutable, no `-e`, awk via
   `-v`).
4. **Test-first on fragile modules.** Joiner and Format are the trickiest; run
   their tests before and after any change to them.
5. **Confirm before irreversible/outward actions:** `git push`, `git merge`,
   `apt-get install`, deleting files.

---

## 7. Critical paths (most important files)

| File | What it does | Why it's critical |
|---|---|---|
| [`app.sh`](app.sh) | Entry point: checks `whiptail`, runs the file picker, shows the 6-option menu, dispatches modules, calls `move.sh` on exit. | The only thing a user runs. Owns the menu loop and shared-state seeding. |
| [`functions/common.sh`](functions/common.sh) | Shared library: `require_tools` (preflight), `detect_delimiter`, `load_selected_file` (CRLF norm + validation + `trap` cleanup), `load_directory`, `navigate_and_select` (file explorer), path vars. | **Sourced by everything.** A bug here breaks all 5 modules. Holds the CRLF and delimiter invariants. |
| [`functions/csv-joiner.sh`](functions/csv-joiner.sh) | SQL-style JOIN (INNER/LEFT/RIGHT/FULL) in a single two-pass awk program; excludes the secondary key from output; can re-run sub-modules on the joined result. | **Most complex / most fragile module.** The awk join logic is subtle (SUBSEP-keyed arrays, placeholder rows). Touch with tests running. |
| [`functions/format.sh`](functions/format.sh) | Integrity check, type inference, exports: Clean CSV (drop malformed, fill nulls), SQL INSERTs, JSON, Markdown. | Multiple output formats = multiple correctness surfaces; quoting/escaping bugs live here. |
| [`functions/search.sh`](functions/search.sh) | Regex search (all/column/multi), multi-condition column filter, numeric-aware sort, unique values. | Holds the **awk-injection-safe** pattern; the `save_result` preview→save UX flow. |
| [`functions/file-scan.sh`](functions/file-scan.sh) | Structure, row/col counts, head/tail preview, content-hash duplicate detection. | Module 1, the most-used entry analysis; the `num_lines` input validation lives here. |
| [`functions/data-quality.sh`](functions/data-quality.sh) | Per-column null map, type-anomaly count, whitespace issues, duplicate rows. | The "is this data trustworthy?" module; its awk aggregation is the quality contract. |
| [`tests/run_tests.sh`](tests/run_tests.sh) | Aggregate test runner consumed by `make test` and CI. | The single source of truth for "is the project healthy?". |
| [`tests/mock_whiptail.sh`](tests/mock_whiptail.sh) | Drop-in `whiptail` replacement reading scripted responses from a queue, logging every call. | Makes the whole interactive app testable non-interactively. Understand it before writing a new test. |
| [`Makefile`](Makefile) · [`.github/workflows/ci.yml`](.github/workflows/ci.yml) · [`.shellcheckrc`](.shellcheckrc) | Task runner, CI, lint config. | The automation contract — what CI runs is exactly `make check`. |

"Training/inference/experiment-config entry points" → **N/A** (no model).

---

## 8. Common tasks (exact commands)

```bash
# Run the full test suite (smoke test) — preferred
make test
#   or, without make:
bash tests/run_tests.sh

# Run ONE test (fast feedback while editing a module)
bash tests/test_joiner.sh
bash tests/test_format.sh
bash tests/test_data_quality.sh
bash tests/test_search_sort_unique.sh
bash tests/test_preflight.sh
bash tests/integration_test.sh        # File Scan + Regex + security checks
bash tests/test_duplicates.sh
bash tests/test_sql_export.sh

# Lint (needs shellcheck; CI does this automatically)
make lint

# Lint + test together (exactly what CI runs)
make check

# Launch the app
./app.sh          # or: make run

# List available make targets
make              # or: make help
```

**Add a new test for a module** (the closest thing to "add a new experiment"):
1. Add a deterministic fixture under `tests/fixtures/` if needed; document it in
   [`tests/fixtures/README.md`](tests/fixtures/README.md).
2. Copy an existing test (e.g. `tests/test_data_quality.sh`) as a template — it
   shows how to set up the `whiptail` mock, the response queue, and seed
   `functions/selected_file.txt`.
3. Register the new script in the `TESTS=( … )` array in
   [`tests/run_tests.sh`](tests/run_tests.sh).
4. Run `make test`; ensure the aggregate count went up and is green.

**The following are N/A** (no such capability exists; do not fabricate):
- Train: ~~`make train` / `python src/train.py`~~ — **N/A**
- Evaluate: ~~`make evaluate`~~ — **N/A**
- Serve API: ~~`uvicorn src.api:app`~~ — **N/A**
- Deploy / Docker: ~~`docker build`~~ — **N/A** (a future packaging step is in §11)

---

## 9. Business rules & invariants (must respect)

These are non-obvious rules baked into the code. Breaking one is a regression
even if tests happen to pass:

1. **Never modify the user's original file.** All processing happens on a
   CRLF-normalized `mktemp` copy created by `load_selected_file`. Any new code
   must read from `$selected_file` (the temp copy) and only show the original's
   *name/path* via `$selected_file_original`.
2. **Pass user input to awk via `-v`, never interpolate it into the awk
   program.** This is the awk-injection guard; `integration_test.sh` TEST 4
   enforces it. Build awk *variables*, compare inside the script.
3. **Use `set -uo pipefail`, never add `-e`.** Interactive non-zero exits
   (whiptail Cancel, grep no-match, `((x++))`) are normal control flow here.
4. **Count data rows as `awk 'NF' "$file" | tail -n +2 | wc -l`**, not `wc -l`.
   `wc -l` miscounts blank trailing lines and includes the header. Stay
   consistent so reports agree with each other.
5. **Delimiter is detected from line 2** (first data row), not the header.
6. **CSV with quoted delimiters is out of scope (current limitation).** Don't
   write tests that depend on `"a,b"` parsing correctly until a quoting-aware
   parser exists — document the limitation instead.
7. **Generated output is disposable.** `output/` and `history/` are gitignored;
   never commit their contents.

Statistical rules (precision@k, training windows, imputation order, etc.) →
**N/A** — no model, no imputation pipeline.

---

## 10. Troubleshooting

| Symptom | Cause & fix |
|---|---|
| `make` fails with `/c/Program: No such file or directory` | Git-for-Windows `make` ran the recipe via cmd.exe. Already mitigated by `SHELL := /usr/bin/bash` in the [`Makefile`](Makefile). If you see it elsewhere, invoke recipes with an absolute bash path. |
| `make lint` → "shellcheck not found" (exit 1) | `shellcheck` isn't installed locally (common on Windows). This is expected; CI runs the real lint. To lint locally, install shellcheck. |
| `make test` can't run / "whiptail not found" when launching the app | Tests **don't** need real `whiptail` (they use the mock). The *app* does: `sudo apt-get install -y whiptail` (or `apt install whiptail`). |
| A module shows "required tool(s) not found: …" | `require_tools` preflight in `common.sh` caught a missing coreutil. Install the named tool(s). |
| A test using `ln -s` fails on Windows | Symlinks don't work in Git Bash. Rewrite the test to avoid symlinks (see how `tests/test_preflight.sh` exercises `require_tools` directly). |
| Reports show wrong column counts / split mid-field | Almost certainly the **CSV-quoting limitation** (a quoted field contains the delimiter). Pre-clean the file or keep delimiters out of values. |
| Garbled accents / fields off by one on a Windows file | CRLF not stripped — confirm the module reads `$selected_file` (the normalized copy), not the raw path. |
| "Selected file no longer exists" | `functions/selected_file.txt` points at a moved/deleted file. Re-pick via the app's file explorer, or re-seed it (tests do `echo "$path" > functions/selected_file.txt`). |
| OOM / training crash | **N/A** — there is no training. |

---

## 11. Next steps (prioritized)

> **Assessment (2026-06-02): the project is considered COMPLETE for its current
> purpose.** All high-value safety and correctness work is done — hardening + CI
> (green), and M6 (CSV quoting) across all 5 modules. What remains below is
> *new capability or polish, not critical debt.* The recommendation is **not to
> implement these reflexively (YAGNI)**: each is gated on a real driver. The
> main risk now is over-engineering a tool that already meets its goal.

**Done (high-value, completed):**
1. ✅ **(2026-06-02) Merge & push the hardening branch.** Merged into `main`;
   CI ran for the first time.
2. ✅ **(2026-06-02) CI green; shellcheck findings resolved.** First CI run
   failed on ~48 warnings; fixed in `fa6dc90` (genuine fixes + justified
   `# shellcheck disable=`/`source=` directives).
3. ✅ **(2026-06-02) CSV quoting-aware parser (M6), all 5 modules.** Shared
   helper (`common.sh:csv_fpat` + `AWK_UNQUOTE`); `csv-joiner` via `patsplit()`;
   23 assertions in `tests/test_csv_quoting.sh`.

**Cheap win worth doing now:**
4. **`pre-commit` hook running `make check`.** ~10 min, high leverage: stops
   red pushes before they reach CI. The only backlog item recommended
   unconditionally.

**Conditional — do ONLY when a concrete driver appears (otherwise leave as
documented limitations):**
5. **Real macOS/BSD support** — *only if a real macOS user exists.* Replace
   `sha256sum`→`shasum -a 256`, `mktemp --suffix`→portable form, audit
   `realpath` and gawk `/i`, add macOS to the CI matrix. Target today is
   Linux/WSL/Git Bash; this is speculative until someone needs it.
6. **Non-interactive CLI mode (`--file`, `--action`, `--out`)** — *only if
   automation/pipeline use is actually wanted.* It expands the product to a
   different audience (scripting) vs. today's guided-menu tool for non-experts.
7. **Migrate tests to [`bats-core`](https://github.com/bats-core/bats-core)** —
   **not recommended.** The current harness is green, CI-gated and readable;
   migrating is churn for aesthetics with regression risk.

**If "correctness" is ever revisited, these two residual warts outrank #5–#7**
(both currently documented, neither urgent):
- **`csv-joiner` always emits comma-CSV** regardless of input delimiter and does
  not re-quote values: joining a `;`-file whose field contains a literal comma
  corrupts the output.
- **Embedded newlines inside quoted fields** break the line-based row-count /
  duplicate-detection idioms.

There is no `TODO.md` or issue tracker yet. The authoritative backlog is the
"Diferido (backlog)" section of [`docs/REFACTOR_PLAN.md`](docs/REFACTOR_PLAN.md)
and [`docs/AUDIT.md`](docs/AUDIT.md) §3 (🟢 items). If you want tracking, create
GitHub issues from #4–#7 above — but only #4 is recommended without a driver.

---

## ✅ Checklist — before you start modifying code

Run through this every session, in order:

- [ ] **Read [`CLAUDE.md`](CLAUDE.md)** (architecture + key patterns) and **this
      `handoff.md`**.
- [ ] **Internalize that this is Bash, not ML.** No Python/DVC/MLflow/models —
      don't search for or create them.
- [ ] **Check the branch:** `git branch --show-current` → expect
      `refactor/hardening` (until merged). Confirm a clean tree: `git status`.
- [ ] **Run the smoke test:** `make test` → expect `passed=8 failed=0`,
      `ALL SUITES PASSED`. If red, fix or report **before** making changes.
- [ ] **(If touching Joiner or Format)** run that module's specific test first to
      capture the baseline (`bash tests/test_joiner.sh` / `test_format.sh`).
- [ ] **Re-read the invariants in §9** — original files immutable, awk via `-v`,
      no `-e`, row-count idiom, delimiter from line 2.
- [ ] **Confirm scope with the user** for the concrete task. Don't push, merge,
      install globally, or delete files without explicit confirmation.
- [ ] **MLflow logs / experiment tracking review:** **N/A** — none exist.
- [ ] **After changes:** `make test` (and `make lint` / rely on CI) before
      committing. Use Conventional Commits.

