# Test fixtures

Small, deterministic CSV files used by the test suite. Each is crafted to
exercise a specific module behaviour.

| File | Used by | What it exercises |
|---|---|---|
| `employees.csv` | `test_joiner.sh`, `test_search_sort_unique.sh` | Primary join table (key `DeptID`, col 3); numeric sort + unique values |
| `departments.csv` | `test_joiner.sh` | Secondary join table (key `DeptID`, col 1). `DeptID=30` has no match; `DeptID=99` (Dave) has no department |
| `quality.csv` | `test_data_quality.sh` | One empty `age`, one type anomaly (`abc` in a numeric column), one whitespace value (` 40 `), one duplicate row (`3,25,NYC`) |
| `malformed.csv` | `test_format.sh` | One empty field (null fill), one short row (`7,8` → malformed, dropped by Clean CSV) |
| `quoted.csv` | `test_csv_quoting.sh` | Quoted fields containing the delimiter (`"Smith, John"`); exercises the M6 quoting-aware parser in `file-scan`, `data-quality`, `search` and `format` |
| `qjoin_left.csv` / `qjoin_right.csv` | `test_csv_quoting.sh` | A JOIN whose **key** is a quoted, comma-bearing value (`"North, East"`); proves `csv-joiner` matches keys correctly via `patsplit()` + `unq()` |

> **M6 (CSV quoting) — COMPLETE (all 5 modules).** A quoting-aware splitter
> lives in `common.sh` (`csv_fpat`, `AWK_UNQUOTE`, gawk `FPAT`/`patsplit`-based)
> and every module is routed through it. New fixtures may now use quoted fields
> containing the delimiter. Out of scope: embedded newlines inside quoted
> fields. See `handoff.md` §4/§11.
