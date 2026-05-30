# Plan de refactorización — `bash-analyzer`

**Fecha:** 2026-05-29
**Base:** `docs/AUDIT.md`
**Principio rector:** cada tarea es **atómica, reversible y no rompe la funcionalidad existente**. Se ejecuta en orden; tras cada cambio se corre la suite de tests. Cada tarea = un commit con [Conventional Commits](https://www.conventionalcommits.org/).

## Decisiones acordadas con el usuario

- **Orden de prioridades:** el propuesto en `AUDIT.md` §4, tal cual.
- **M3 (macOS):** *sincerar el README* — declarar soporte **Linux/WSL**; macOS queda como mejora futura (no se reescribe `sha256sum`/`mktemp` ahora).
- **M6 (CSV entrecomillado):** **backlog** — se documenta la limitación; el parser robusto se aborda en una iteración futura.

## Salvaguarda previa (antes de tocar código)

- **T0 — Rama de respaldo.** Confirmar árbol git limpio y crear rama `refactor/hardening` desde `main`. Todo el trabajo va ahí; `main` queda intacto y revertible. *(Requiere confirmación del usuario.)*

---

## Fase 1 — Red de seguridad (máximo impacto, riesgo nulo sobre la lógica)

> Se hace **primero** para que detecte regresiones de todas las fases siguientes.

- **T1 — `Makefile`** con targets:
  - `lint` → `shellcheck` sobre `app.sh move.sh functions/*.sh tests/*.sh`
  - `test` → ejecuta `integration_test.sh` + `test_duplicates.sh` + `test_sql_export.sh`
  - `run` → `./app.sh`
  - `check` → `lint` + `test`
  - `help` (default) → lista targets
  - *Verificación:* `make help`, `make test` en verde. *Commit:* `build: add Makefile with lint/test/run/check targets`.

- **T2 — *Runner* único de tests** `tests/run_tests.sh` que encadena los tres scripts y devuelve código agregado (lo consumen `make test` y CI).
  - *Verificación:* `bash tests/run_tests.sh` corre los 3 y resume PASS/FAIL. *Commit:* `test: add aggregate test runner`.

- **T3 — CI con GitHub Actions** `.github/workflows/ci.yml`:
  - Trigger: `push` y `pull_request`.
  - Job en `ubuntu-latest`: instalar `whiptail` + `shellcheck`, ejecutar `make check`.
  - *Verificación:* workflow válido (yamllint mental / `act` si está disponible); se confirmará al hacer push. *Commit:* `ci: add GitHub Actions workflow (shellcheck + test suite)`.

- **T4 — Línea base de `shellcheck`.** Ejecutar `make lint`, revisar hallazgos y **corregir los seguros** (quoting, `read -r`, `$?` indirecto, etc.). Lo que requiera cambio de comportamiento se anota con `# shellcheck disable=...` justificado o se difiere.
  - *Verificación:* `make lint` limpio (o con *disables* documentados); `make test` sigue verde. *Commit(s):* `style: resolve shellcheck findings in <módulo>`.

---

## Fase 2 — Robustez de ejecución (C1)

- **T5 — `set -euo pipefail` módulo a módulo.** Introducir en cada script de `functions/` y en `app.sh`/`move.sh`, **uno a la vez**, corriendo `make test` tras cada uno. Ajustar puntos donde un no-cero es esperado (p. ej. `grep` sin match, cancelaciones de `whiptail` que devuelven no-cero) con guardas (`|| true`, captura de `$?`).
  - *Verificación:* suite verde tras cada módulo. *Commit por módulo:* `fix(<módulo>): enable strict mode (set -euo pipefail)`.

- **T6 — Validación de entradas (M5).** En `file-scan.sh`, validar que `num_lines` sea numérico (replicando el patrón ya existente para `col_index` en `search.sh`).
  - *Verificación:* test que pasa entrada no numérica y espera mensaje controlado. *Commit:* `fix(file-scan): validate numeric line-count input`.

---

## Fase 3 — Cobertura de los módulos sin red (M2)

> Se añaden **antes** de cualquier limpieza de esos módulos, para refactorizar con red.

- **T7 — Test E2E CSV Joiner** (módulo 4): un INNER y un LEFT join sobre dos CSV de fixture; verificar cabecera combinada, exclusión de clave secundaria y nº de filas.
  - *Commit:* `test: add end-to-end coverage for CSV joiner`.
- **T8 — Test E2E Data Quality** (módulo 2): verificar conteo de nulos, anomalías de tipo y detección de duplicados.
  - *Commit:* `test: add end-to-end coverage for data quality`.
- **T9 — Test E2E Format** (módulo 5): Clean CSV (relleno de nulos + descarte de filas malformadas), JSON y Markdown.
  - *Commit:* `test: add end-to-end coverage for format exports`.
- **T10 — Test Search acciones 3 y 4** (Sort numérico y Unique).
  - *Commit:* `test: cover sort and unique actions in search`.

*Fixtures:* CSV pequeños y deterministas bajo `tests/fixtures/` (incluido uno con campos entrecomillados que **documenta** la limitación M6 como `xfail`/comentario, sin arreglarla aún).

---

## Fase 4 — Preflight de dependencias (C3)

- **T11 — `require_tools` en `common.sh`:** función que verifica `awk grep sort uniq head tail wc find sha256sum mktemp tr` (+ `whiptail` desde `app.sh`) y aborta con mensaje claro si falta alguno. Invocada al inicio de cada módulo (o desde `common.sh` al cargarse).
  - *Verificación:* test que simula utilidad ausente (PATH recortado) y espera fallo controlado. *Commit:* `feat(common): add dependency preflight check`.

---

## Fase 5 — Sinceridad de portabilidad (M3)

- **T12 — Corregir README:** sección *Requirements* declara **Linux y Windows (WSL)**; macOS se mueve a "limitaciones conocidas / roadmap" citando `sha256sum`, `mktemp --suffix`, `realpath` y gawk `/i`.
  - *Commit:* `docs: align README platform support with actual behavior`.

---

## Fase 6 — Limpieza de bajo riesgo (M7)

- **T13 — Deduplicar `search.sh` acción 1:** extraer el bloque de informe repetido de los tres *scopes* a una función `write_regex_report`.
  - *Verificación:* los tests de regex (existentes + nuevos) siguen verdes. *Commit:* `refactor(search): extract shared regex report builder`.

---

## Cierre (Paso 5)

- **T14 — Documentar limitaciones conocidas** (M6 CSV quoting, macOS) en README y `CLAUDE.md`.
- **T15 — Actualizar `README.md`** (instalar entorno, ejecutar pipeline vía `make`, lanzar tests) y **`CLAUDE.md`** (nuevos comandos `make`, CI, convención de tests/fixtures).
  - *Commits:* `docs: document known limitations`, `docs: update README and CLAUDE.md to final state`.
- **T16 — Commit final** y propuesta de siguiente iteración (modo no interactivo / `bats-core` / soporte macOS / CSV quoting).

---

## Resumen de impacto

| Fase | Tareas | Aborda | Rompe lógica |
|---|---|---|---|
| Salvaguarda | T0 | — | No |
| 1 Red de seguridad | T1–T4 | C2, M1, M4 | No |
| 2 Robustez | T5–T6 | C1, M5 | Riesgo bajo (mitigado por tests) |
| 3 Cobertura | T7–T10 | M2 | No (solo añade tests) |
| 4 Preflight | T11 | C3 | No |
| 5 Portabilidad | T12 | M3 | No (solo docs) |
| 6 Limpieza | T13 | M7 | Riesgo bajo (mitigado por tests) |
| Cierre | T14–T16 | doc | No |

> Las fases 1, 3, 4 y 5 **no tocan la lógica de negocio**. Las fases 2 y 6 sí, pero siempre con la suite de tests como red (por eso van después de la Fase 1 y, para los módulos frágiles, de la Fase 3).
