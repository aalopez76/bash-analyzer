# Auditoría técnica — `bash-analyzer`

**Fecha:** 2026-05-29
**Autor:** Revisión Senior DS (Claude Code)
**Alcance revisado:** todo el código fuente (`app.sh`, `move.sh`, `functions/*.sh`), tests (`tests/*`), documentación (`README.md`, `CLAUDE.md`, `tests/README.md`) y configuración (`.gitignore`).

---

## 1. Resumen ejecutivo

`bash-analyzer` es una **suite de análisis de CSV/TSV en Bash puro** (~1.060 líneas) con UI interactiva vía `whiptail`. Es un proyecto **bien estructurado para lo que es**: separación limpia en módulos, librería compartida (`common.sh`), normalización CRLF centralizada, detección de delimitador y una suite de tests con *mock* de `whiptail` poco común en proyectos shell. La documentación es notablemente buena.

> **Nota de encuadre importante:** este **no es un proyecto de ML/Python**. No hay modelos, entrenamiento, experimentos ni dependencias Python. Por tanto, herramientas del playbook clásico de DS — **DVC, MLflow/W&B, `poetry.lock`, `requirements.txt`, `src/{data,features,models}`, versionado de datasets** — **no aplican** y se descartan justificadamente. Se traducen a sus equivalentes reales en un proyecto Bash (ver tabla §5).

El proyecto es **funcional y mantenible**, pero le faltan las **redes de seguridad** que esperaríamos en algo presentado como pieza de portfolio *y* usado en operaciones: no hay ejecución de errores estricta, ni CI, ni linting, y la cobertura de tests deja sin verificar los módulos más complejos (Joiner y la mayor parte de Format). Hay además **afirmaciones de portabilidad (macOS) que el código no cumple**.

**Veredicto:** base sólida; el trabajo de mayor impacto es **endurecer la robustez y automatizar la validación**, no reescribir lógica.

---

## 2. Lo que está bien (rescatable)

- **Arquitectura modular clara.** Un módulo por responsabilidad; `common.sh` concentra utilidades compartidas (delimitador, CRLF, navegador de ficheros, rutas).
- **Normalización CRLF segura** (`common.sh:load_selected_file`): trabaja sobre una copia `mktemp`; **el fichero original nunca se modifica**. Patrón correcto y bien documentado.
- **Conciencia de seguridad real.** El filtro por columnas (`search.sh` acción 2) pasa la entrada del usuario como **variables AWK (`-v`)** en lugar de interpolarla como código — evita inyección. La búsqueda regex usa `-v re=`. Incluso existe un **test de seguridad** (TEST 4) que vigila esta propiedad.
- **Suite de tests con *mock* de `whiptail`** (`tests/mock_whiptail.sh`): permite reproducir flujos interactivos de forma determinista. Es un activo poco habitual en proyectos Bash.
- **UX consistente:** patrón "previsualizar → preguntar si guardar" (`save_result`) en Search & Filter.
- **Limpieza de temporales** vía `trap EXIT` en los módulos que crean *tmpfiles*.
- **Documentación de primer nivel:** `README.md`, `CLAUDE.md` (guía de arquitectura) y `tests/README.md` están actualizados y son precisos.
- **`.gitignore` sensato:** ignora estado de runtime, salidas y artefactos de test conservando los `.gitkeep`.

---

## 3. Problemas detectados (por gravedad)

### 🔴 Críticos

| # | Problema | Evidencia | Impacto |
|---|---|---|---|
| C1 | **Sin `set -euo pipefail`** en `app.sh` ni en ningún módulo de `functions/`. | Ningún módulo lo declara (los tests sí usan `set -uo pipefail`). | Un comando que falla a mitad de un pipeline (p. ej. `awk`/`sort`) se **ignora silenciosamente** → informes corruptos o parciales sin aviso. Es el mayor riesgo para la *confianza en los resultados*. |
| C2 | **Sin CI.** No existe `.github/workflows/`. | Repo sin pipeline. | Los tests existen pero **nadie los ejecuta automáticamente**. Cualquier regresión llega a `main` sin ser detectada. Crítico para una pieza de portfolio. |
| C3 | **Sin verificación de dependencias más allá de `whiptail`.** | `app.sh:7` solo comprueba `whiptail`. Los módulos se invocan directos (como hacen los tests) asumiendo `awk`, `sort`, `sha256sum`, `mktemp`, `realpath`. | Si falta una utilidad o difiere de la esperada, el fallo es opaco y tardío. No hay *preflight* ni versiones documentadas. |

### 🟡 Mejorables

| # | Problema | Evidencia | Impacto |
|---|---|---|---|
| M1 | **Sin linting (`shellcheck`).** | No hay config ni invocación. | Sin análisis estático; errores comunes de quoting/uso de variables pasan inadvertidos. Es el "lint" que el playbook pide. |
| M2 | **Cobertura de tests parcial.** Sin tests end-to-end de **CSV Joiner** (módulo 4, el más complejo), **Data Quality** (módulo 2), **Format** salvo SQL (Clean CSV, JSON, Markdown sin cubrir) ni de Search acciones **3 (Sort)** y **4 (Unique)**. | `tests/integration_test.sh` cubre File Scan y Regex; `test_sql_export.sh` solo SQL. | El módulo más frágil (Joiner) no tiene red de seguridad. Riesgo de regresión silenciosa. |
| M3 | **Portabilidad macOS/BSD rota pese a lo que afirma el README.** Uso de `mktemp --suffix` (`common.sh:49`, `csv-joiner.sh:27`), `sha256sum` (`file-scan.sh`), `realpath` (`file-scan.sh:113`) y flag `/i` de gawk (`format.sh:40`, no POSIX). | README: "Compatible with Linux, macOS, and Windows via WSL". | En macOS estos comandos difieren (`shasum`, sin `--suffix`) → el tool **no funciona** ahí. Discrepancia doc/realidad. |
| M4 | **Sin *runner* único de tests ni `Makefile`.** | Hay que invocar cada script a mano. | Fricción para ejecutar la suite completa; CI y onboarding más difíciles. |
| M5 | **Validación de entrada incompleta.** `file-scan.sh:42` toma `num_lines` sin validar que sea numérico antes de `head -n "$((num_lines+1))"`. | `file-scan.sh`. | Entrada no numérica produce error aritmético en vez de mensaje claro. (El filtro por columnas sí valida `col_index`, buen precedente a replicar.) |
| M6 | **Parsing CSV ingenuo: no soporta campos entrecomillados.** Todos los módulos hacen `split`/`-F` por el delimitador sin respetar comillas. | Toda la base AWK. | Un campo como `"Smith, John"` en un CSV con coma **rompe el conteo de columnas y los resultados**. Limitación de *correctitud de datos* relevante para un tool de datos. |
| M7 | **Duplicación de código** en `search.sh` acción 1: los tres *scopes* repiten bloques de informe casi idénticos (≈3×). | `search.sh:98-150`. | Mantenibilidad; un cambio de formato hay que hacerlo tres veces. |

### 🟢 Recomendaciones a futuro

- **G1 — Modo no interactivo / CLI con flags** (`--file`, `--action`, `--out`) para que el tool sea *scriptable* sin el *mock*. Abre la puerta a uso en pipelines reales.
- **G2 — Migrar tests a [`bats-core`](https://github.com/bats-core/bats-core)** para aserciones más limpias y reporte estándar (TAP).
- **G3 — Hook `pre-commit`** que corra `shellcheck` + tests rápidos antes de cada commit.
- **G4 — Empaquetado/distribución:** script de instalación o *build* de fichero único; opcionalmente publicar como release.
- **G5 — Cobertura con `kcov`** integrada en CI.
- **G6 — Soporte real de CSV entrecomillado** (resuelve M6) si el alcance de datos lo justifica.

---

## 4. Recomendaciones concretas, ordenadas por impacto/esfuerzo

> Ordenadas para maximizar valor sin romper funcionalidad. El detalle ejecutable irá en `docs/REFACTOR_PLAN.md`.

1. **Red de seguridad antes de tocar nada (C2, M1, M4):** añadir `Makefile` (`test`, `lint`, `run`, `check`) + workflow de **GitHub Actions** que ejecute `shellcheck` y la suite. Esto detecta regresiones de todos los pasos siguientes.
2. **Robustez de ejecución (C1):** introducir `set -euo pipefail` de forma controlada, módulo a módulo, verificando con los tests tras cada uno.
3. **Cobertura de los módulos sin red (M2):** tests end-to-end de Joiner, Data Quality, Format (Clean/JSON/MD) y Search 3/4. Idealmente **antes** de refactorizar nada de esos módulos.
4. **Preflight de dependencias (C3):** función `require_tools` en `common.sh` + documentar versiones mínimas.
5. **Sinceridad de portabilidad (M3):** o bien soportar macOS de verdad (alternativas a `sha256sum`/`mktemp --suffix`), o **corregir el README** para declarar Linux/WSL. Recomendado: corregir doc ahora, soporte macOS como mejora futura.
6. **Validación de entradas (M5)** y **deduplicación de `search.sh` (M7):** limpieza de bajo riesgo una vez haya tests que la respalden.
7. **Futuro (G1–G6):** según prioridades de negocio.

---

## 5. Traducción del playbook DS → equivalente Bash

| Objetivo playbook (Python/ML) | ¿Aplica? | Equivalente real en este proyecto |
|---|---|---|
| `requirements.txt` / `poetry.lock` | Parcial | Preflight `require_tools` + versiones mínimas documentadas |
| Lint | ✅ | `shellcheck` |
| Tests de regresión / integridad de datos | ✅ | Ampliar suite (Joiner, Format, Quality) + opcional `bats-core` |
| `Makefile` (`data/train/evaluate`) | ✅ (adaptado) | `Makefile` con `test`, `lint`, `run`, `check` |
| CI/CD | ✅ | GitHub Actions: `shellcheck` + suite en cada push/PR |
| `.gitignore`, `.env.example` | Parcial | `.gitignore` ya existe; `.env.example` no aplica (sin secretos/config) |
| DVC (versionado de datos) | ❌ | N/A — procesa ficheros arbitrarios del usuario |
| MLflow / W&B (tracking) | ❌ | N/A — sin modelos ni experimentos |
| Orquestación de pipelines | ❌ | N/A |
| `src/{data,features,models}` | ❌ | N/A — `functions/` ya es la capa de módulos |

---

## 6. Siguiente paso

Validar prioridades (§4) y, una vez acordadas, generar `docs/REFACTOR_PLAN.md` con tareas ejecutables y commits atómicos.
