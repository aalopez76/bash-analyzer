# Bash Data Analyzer

A Bash-based command-line suite for analyzing CSV/TSV datasets. Inspired by the original `bash-data-analysis-tool` project, this fork modernizes the UI with an interactive file explorer and ships five independent analysis modules covering inspection, quality auditing, search, joining, and multi-format export — practical for data operations, technical support, and ad-hoc data work in a terminal.

## Key Features

* **Interactive UI** powered by `whiptail` (no flags or piping needed)
* **Built-in file explorer** — pick any CSV/TSV file from any drive without typing a path
* **CRLF-safe** — normalizes Windows line endings into a temp copy so AWK and field comparisons work correctly under WSL
* **Auto delimiter detection** — comma, semicolon, or tab; inspected from the data row, not the header
* **Five analysis modules** accessible from a single menu:

  * **File Scan** — file structure, headers, delimiter, row/column counts, head/tail preview with adjustable line limits, and a duplicate-row report based on content hashing
  * **Data Quality** — per-column null map, type anomaly count, whitespace issues, and duplicate-row detection across the full dataset
  * **Search & Filter** — regex search (globally or by column), multi-condition column filtering with comparison operators, numeric-aware sorting on any column, and unique-value listing
  * **CSV Joiner** — SQL-style JOIN between two files supporting `INNER`, `LEFT`, `RIGHT`, and `FULL OUTER`; the result becomes the active dataset, ready for any other module
  * **Format & Export** — structural integrity check, type inference, and exports to **Clean CSV** (malformed rows removed, nulls filled), **SQL INSERTs** (with configurable table name), **JSON** array, or **Markdown** table

* **Result-preview workflow** — every operation shows a preview first, then asks whether to save to `output/`
* **Automatic archiving** — on exit, all `.txt` reports in `output/` are moved into `history/` so the next session starts clean
* **Integration test suite** under `tests/` with a `whiptail` mock for fully scripted, repeatable runs

![App](img/app.png)

## Requirements

* Bash (Bourne Again SHell)
* `whiptail` (`apt install whiptail` on Debian/Ubuntu)
* Standard Unix utilities: `awk`, `grep`, `sort`, `uniq`, `head`, `tail`, `wc`, `find`, `tr`, `mktemp`, `sha256sum`, `realpath`
* Tested on **Linux** and **Windows (WSL / Git Bash)**. macOS is not yet supported — see [Known limitations](#known-limitations).

On launch, the app verifies that `whiptail` and the core utilities above are present and aborts with a clear message if any are missing.

## Usage

1. **Clone this repository:**

```bash
git clone https://github.com/aalopez76/bash-analyzer.git
```

2. **Navigate to the directory:**

```bash
cd bash-analyzer
```

3. **Run the main tool:**

```bash
./app.sh
```

4. **Select a file:**
   The app opens a built-in file explorer rooted at the available drives. Navigate into any directory and pick the CSV or TSV file you want to analyze — no need to copy files into the project or pass a path.

5. **Choose an action from the menu:**
   The active file is shown in the title bar and persists across menu invocations. Pick `File Scan`, `Data Quality`, `Search & Filter`, `CSV Joiner`, or `Format & Export`. Use `Exit` (option 6) to leave the app.

6. **Review and save results:**

   * Each module shows a preview before saving.
   * Reports land in `output/` as `.txt`; exported datasets land as `.csv`, `.sql`, `.json`, or `.md`.
   * On exit, `.txt` reports are archived into `history/` automatically.

## Project layout

```
app.sh                    # entry point — file picker + main menu
move.sh                   # post-exit archiver (output/*.txt → history/)
Makefile                  # developer task runner (lint/test/run/check)
functions/
  common.sh               # shared library: delimiter, CRLF norm, file explorer, preflight
  file-scan.sh            # Module 1
  data-quality.sh         # Module 2
  search.sh               # Module 3
  csv-joiner.sh           # Module 4
  format.sh               # Module 5
  file-search.sh          # helper
output/                   # generated reports and exports (gitignored)
history/                  # archived .txt reports (gitignored)
tests/                    # test suite + whiptail mock + fixtures
.github/workflows/ci.yml  # CI: shellcheck + test suite on every push/PR
```

## Development

This repo ships a `Makefile` so common tasks are one command away:

```bash
make            # list available targets
make test       # run the full test suite (no real whiptail needed)
make lint       # run shellcheck on all shell scripts
make check      # lint + test (what CI runs)
make run        # launch the app
```

Tests drive the app non-interactively via a `whiptail` mock, so the whole
suite is deterministic and runs in CI. See [`tests/README.md`](tests/README.md)
for details. Every push and pull request runs `make check` on GitHub Actions.

## Known limitations

* **macOS is not yet supported.** The code relies on GNU/coreutils behaviour —
  `sha256sum`, `mktemp --suffix`, `realpath` and a GNU `awk` regex flag — that
  differs on BSD/macOS. Use Linux or WSL for now. (Tracked as future work.)
* **CSV quoting is not honoured.** Parsing splits on the delimiter directly, so
  a quoted field containing the delimiter (e.g. `"Smith, John"` in a
  comma-separated file) will be miscounted. Keep delimiters out of field values,
  or pre-clean such files. A quoting-aware parser is planned.

---

## License

MIT License
