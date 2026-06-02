# Test fixtures

Small, deterministic CSV files used by the test suite. Each is crafted to
exercise a specific module behaviour.

| File | Used by | What it exercises |
|---|---|---|
| `employees.csv` | `test_joiner.sh`, `test_search_sort_unique.sh` | Primary join table (key `DeptID`, col 3); numeric sort + unique values |
| `departments.csv` | `test_joiner.sh` | Secondary join table (key `DeptID`, col 1). `DeptID=30` has no match; `DeptID=99` (Dave) has no department |
| `quality.csv` | `test_data_quality.sh` | One empty `age`, one type anomaly (`abc` in a numeric column), one whitespace value (` 40 `), one duplicate row (`3,25,NYC`) |
| `malformed.csv` | `test_format.sh` | One empty field (null fill), one short row (`7,8` → malformed, dropped by Clean CSV) |
| `quoted.csv` | `test_csv_quoting.sh` | Quoted fields containing the delimiter (`"Smith, John"`); exercises the M6 quoting-aware parser (`common.sh:csv_fpat` / `AWK_UNQUOTE`) in both `file-scan` and `data-quality` |

> **M6 (CSV quoting) — rollout in progress (2/5).** A quoting-aware splitter
> lives in `common.sh` (`csv_fpat`, `AWK_UNQUOTE`, gawk `FPAT`-based);
> **`file-scan.sh` and `data-quality.sh` are routed through it.** The remaining
> modules (`search`, `format`, `csv-joiner`) still split naively and miscount
> quoted delimiters — their fixtures keep avoiding quoted delimiters until
> migrated. See `docs/AUDIT.md` and `handoff.md` §11.
