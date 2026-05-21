# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Running the App

```bash
./app.sh
```

Requires Bash and `whiptail`. On Windows, run inside WSL. The `output/` and `history/` directories are created automatically.

## Dependencies

Standard Unix tools: `awk`, `grep`, `sort`, `uniq`, `head`, `tail`, `wc`, `find`, `sha256sum`, `mktemp`, `tr`. The only non-standard dependency is `whiptail` (`apt install whiptail` on Debian/Ubuntu).

## Architecture

`app.sh` is the sole entry point. On launch it asks the user to select a CSV/TSV file via an interactive file explorer (`navigate_and_select` from `common.sh`), then presents a 5-option analysis menu. All UI is handled via `whiptail`; all output lands in `output/` as `.txt` (and `.csv` for joins and clean exports). On exit, `move.sh` archives `output/*.txt` to `history/`.

### Shared state (persisted between menu invocations)

| File | Written by | Read by |
|---|---|---|
| `functions/directory.txt` | `app.sh` | `csv-joiner.sh` |
| `functions/selected_file.txt` | `app.sh`, `csv-joiner.sh` | all analysis modules |

### Shared library: `functions/common.sh`

Sourced by every module. Provides:
- `detect_delimiter(file)` — inspects line 2 for tab, semicolon, or comma. Returns `printf '\t'` for tab.
- `load_selected_file()` — reads `selected_file.txt`, validates the path, normalizes CRLF via `tr -d '\r'` into a tmpfile, then sets `$selected_file` (pointing to the tmpfile) and `$delimiter`. Registers a `trap EXIT` to clean up the tmpfile.
- `load_directory()` — reads `directory.txt`, sets `$directory`
- `navigate_and_select(title, start)` — interactive file explorer used by `app.sh` at startup
- Common path variables: `$FUNCTIONS_DIR`, `$SCRIPT_DIR`, `$OUTPUT_DIR`, `$DIRECTORY_FILE`, `$SELECTED_FILE_PATH`

### Module summary

| Option | Script | Key output |
|---|---|---|
| 1 File Scan | `file-scan.sh` | `output/scan-report.txt` |
| 2 Data Quality | `data-quality.sh` | `output/quality-report.txt` |
| 3 Search & Filter | `search.sh` | `output/regex_result.txt`, `condition_result.txt`, `sort_result.txt`, `unique_result.txt` |
| 4 CSV Joiner | `csv-joiner.sh` | `output/join_result.csv` + `join_result.txt` |
| 5 Format | `format.sh` | `output/format-report.txt`, `output/clean_result.csv` |

## Key Patterns

**CRLF normalization** (`common.sh:load_selected_file`): Windows-origin files (`\r\n`) break AWK type detection and field comparisons in WSL. `load_selected_file()` always pipes the file through `tr -d '\r'` into a `mktemp` and sets `$selected_file` to that tmpfile for the duration of the module. All reads go to the tmpfile — the original file is never modified.

**Delimiter detection** (`common.sh:detect_delimiter`): reads line 2 (not line 1, which is the header) and tests tab → semicolon → comma.

**Row counting**: `wc -l` includes blank trailing lines. All modules use `awk 'NF' "$file" | tail -n +2 | wc -l` to count only non-blank data rows.

**AWK column filtering** (`search.sh`, action 2): the condition is built as a string — `condition="(\$$col_index $operator \"$value\")"` — and passed as an AWK program: `awk -F"$delimiter" "$condition || NR==1"`. Values are quoted inside the AWK expression; the outer shell double-quoting preserves embedded quotes during expansion.

**Sort numeric detection** (`search.sh`, action 3): before sorting, each selected column is scanned to determine if all non-blank values are numeric. If so, `-n` is appended to the sort key (e.g., `-k3,3n`) so numbers sort correctly instead of lexicographically.

**save_result() pattern** (`search.sh`): all Search & Filter results are written to a `mktemp` first, shown via `--textbox`, then a `--yesno "Save / Cancel"` prompt lets the user decide before copying to the permanent `output/` file.

**Temp files and trap management**: modules that override `trap EXIT` (search.sh actions 1 and 4) include `"$selected_file"` in their trap and explicit cleanup to avoid leaking the CRLF-normalized tmpfile created by `load_selected_file`.

**CSV Joiner JOIN logic**: implemented in a single two-pass AWK program. Primary and secondary files are loaded into associative arrays keyed by the join column (string comparison). Supports INNER, LEFT, RIGHT, FULL OUTER. The secondary key column is excluded from the output to avoid duplication.

**Post-JOIN analysis** (`csv-joiner.sh`): writes `join_result.csv` path to `selected_file.txt` before spawning sub-modules, then restores the original selected file path afterward.
