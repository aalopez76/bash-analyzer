# Tests

Integration and unit tests for `bash-analyzer`. The suite drives the app non-interactively by replacing `whiptail` with a scripted mock, so every flow can be replayed deterministically without human input.

## Running the suite

From the project root:

```bash
bash tests/integration_test.sh
```

Covers three end-to-end flows: **File Scan**, **Regex Search**, and **Column Filter (multi-condition)**.

Focused unit tests:

```bash
bash tests/test_duplicates.sh    # duplicate-row detection
bash tests/test_sql_export.sh    # SQL INSERT export
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
| `integration_test.sh` | Main suite — 3 end-to-end flows |
| `mock_whiptail.sh` | Whiptail replacement |
| `test_duplicates.sh` | Unit test for duplicate detection |
| `test_sql_export.sh` | Unit test for SQL export |
| `debug_hash.sh` | Helper for hash-based duplicate debugging |

## Prerequisites

Same as the main app: Bash, `awk`, `grep`, `sort`, `wc`, `sha256sum`. Tested under WSL.
