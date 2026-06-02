# Tests

Integration and unit tests for `bash-analyzer`. The suite drives the app non-interactively by replacing `whiptail` with a scripted mock, so every flow can be replayed deterministically without human input.

## Running the suite

From the project root, run the whole suite via the aggregate runner
(this is what `make test` and CI execute):

```bash
make test
# or directly:
bash tests/run_tests.sh
```

The runner executes every test script in order and reports an aggregate
pass/fail (exit non-zero if any script fails). No real `whiptail` is
needed — every flow is driven by the mock.

You can also run any script on its own:

```bash
bash tests/integration_test.sh          # File Scan, Regex (all + column), security checks
bash tests/test_duplicates.sh           # duplicate-row detection
bash tests/test_sql_export.sh           # SQL INSERT export
bash tests/test_joiner.sh               # CSV Joiner: INNER + LEFT
bash tests/test_data_quality.sh         # nulls, type anomalies, whitespace, duplicates
bash tests/test_format.sh               # Clean CSV, JSON, Markdown exports
bash tests/test_search_sort_unique.sh   # numeric sort + unique values
```

## How the mock works

`mock_whiptail.sh` is a drop-in replacement for `whiptail` that reads scripted responses from a queue file and logs every invocation for assertions.

| Mock dialog | Behavior |
|---|---|
| `--yesno` | Returns 0 (Yes) or 1 (No) from the queue |
| `--menu`, `--inputbox`, `--radiolist`, `--checklist` | Echoes the queued value on fd 3 (whiptail convention) |
| `--msgbox`, `--textbox` | Logged, no response needed |

Environment variables:

- `MOCK_WHIPTAIL_RESPONSES` — path to the response queue (one entry per line)
- `MOCK_WHIPTAIL_LOG` — path where every call is logged for later assertion

`integration_test.sh` sets both before invoking each module, then greps the log to verify the expected dialogs were shown.

## Files

| File | Purpose |
|---|---|
| `run_tests.sh` | Aggregate runner — runs every test below, reports pass/fail |
| `integration_test.sh` | File Scan, Regex search (all + column), security checks |
| `test_duplicates.sh` | Duplicate-file detection (File Scan) |
| `test_sql_export.sh` | SQL INSERT export (Format) |
| `test_joiner.sh` | CSV Joiner — INNER + LEFT join correctness |
| `test_data_quality.sh` | Data Quality — nulls, type anomalies, whitespace, duplicates |
| `test_format.sh` | Format — Clean CSV (fill/drop), JSON, Markdown |
| `test_search_sort_unique.sh` | Search — numeric sort + unique values |
| `mock_whiptail.sh` | Whiptail replacement |
| `fixtures/` | Small deterministic CSVs (see `fixtures/README.md`) |
| `debug_hash.sh` | Helper for hash-based duplicate debugging |

## Prerequisites

Same as the main app: Bash, `awk`, `grep`, `sort`, `wc`, `sha256sum`. Tested under WSL.
