# CLAUDE.md — SoilProperties

## Lab Principles Source

<!-- Record the commit hash of EcosystemEcologyLab/lab-principles that was
     used to initialise this project. This makes the version of standards
     traceable for any published result. -->

- Repository: EcosystemEcologyLab/lab-principles
- Commit:41dd83436ad1bd15520659f0969b64e147ae3e15
- Copied:2026-05-18
- SCIENCE_PRINCIPLES.md v1.0
- SCIENCE_PRINCIPLES_PIPELINES.md v1.0
- SCIENCE_PRINCIPLES_TEXT_ANALYSIS.md NA

---

## Project Context

In natural ecosystems, however, most research has focused on evaluating the 
influence of soil moisture or climate variables on ecosystem productivity, often 
overlooking the role of soil properties themselves. Other studies have attempted
to model these interactions and have found that certain soil properties, such as
soil water retention, exert a strong influence on Gross Primary Productivity 
(GPP), and may be even more important in semi-arid ecosystems.Despite this, the 
influence of specific soil properties on plant function remains poorly 
constrained in arid ecosystems due to the lack of field observations. To address
this gap, we characterize plant responses to changing precipitation 
conditions (i.e., induced drought) across several soil types at the Biosphere 2. 

**PI:** David J.P. Moore, University of Arizona  
**Collaborators:** Angie Abarzua Munoz; Lindsey Bell  
**Funding:** 
**Repository:** https://github.com/EcosystemEcologyLab/SoilProperties  

---

## Hard Rules — Read These First



### 1. Data sources


### 2. Credentials and secrets
All credentials must be read from environment variables. Never hard-code
any credential, API key, password, or token. See `.env.example` for the
full list of required environment variables.

### 3. Data files
The following directories are gitignored and must never be committed:
- `data/raw/` — raw instrument downloads
- `data/extracted/` — intermediate extractions
- `data/processed/` — pipeline-generated CSVs and the FullData xlsx
- `outputs/` — exclusion logs, unknown logs, session_info.txt
- `figures/` — PDF curve plots

The following directories are git-tracked:
- `data/reference/` — vg_parameters.csv, infiltrometer_radii.csv (source of truth for math constants)
- `data/reference/` — vg_parameters.csv, infiltrometer_radii.csv, subplot_soiltexture.csv (Subplot→USDA texture lookup; confirmed by Lindsey Bell 2026-06-04)

### 4. Pipeline hard rules
- Entry pipeline is **stop-loudly**: print violations table, `stop()`, scientist fixes source `.xlsx` and re-runs. Nothing is silently dropped or flagged-and-continued.
- All scientifically meaningful thresholds live in `R/soilinfiltration_config.R` as documented named constants — never as magic numbers inline in scripts.
- `SoilTexture` is never entered in the field sheet — it is derived automatically from `Subplot` via `data/reference/subplot_soiltexture.csv`.

---

## Environment Variables

| Variable | Purpose | Default |
|---|---|---|
| (none required) | No credentials are needed to run either pipeline | — |

---

## Pipeline Execution Order

### Entry pipeline (interactive, run from RStudio)

1. Open `SoilProperties.Rproj` in RStudio (sets working dir to project root).
2. Enter data into both sheets of a new `.xlsx` file using the template at
   `output_template/Soil_Infiltration_FieldData_template.xlsx`.
   File must be named `Soil_Infiltration_FieldData_YYYYMMDD.xlsx`.
3. `source("R/clean_soilinfiltration.R")` — prompts for the filename, then:
   - Step 1: compares Sheet1 and Sheet2 cell-by-cell; `stop()` on any mismatch
   - Step 2: validates date, per-row rules, and replicate rules; `stop()` on any violation
   - Step 3: appends Sheet1 rows (with Date prepended) to `data/B2_SoilInfiltration_FullData.csv`
             and writes one row to `outputs/infiltration_append_log.csv`
4. Commit the updated `data/B2_SoilInfiltration_FullData.csv` to a branch and open a PR.

### Compute pipeline (batch, run from terminal)

```
Rscript R/calculate_infiltration.R
```

Reads `data/B2_SoilInfiltration_FullData.csv`, derives SoilTexture from Subplot
(via `data/reference/subplot_soiltexture.csv`), fits I = C1√t + C2t per replicate
(grouped by Date + Site + Subplot), computes K via Zhang (1997) / van Genuchten.

Writes:
- `data/processed/B2_SoilInfiltration_Results.csv` — one row per replicate
- `figures/B2_SoilInfiltration_curves_<YYYYMMDD>.pdf` — one panel per replicate

---

## Coding Conventions

### Language and style
- Primary language: R
- Style: tidyverse style guide (https://style.tidyverse.org/)
- Use base R pipe `|>` not `%>%` in new code; existing scripts use `%>%` (dplyr)

### Package preferences
- Data manipulation: dplyr, purrr
- Reading/writing field sheets: openxlsx
- Plotting: ggplot2
- Testing: testthat
- Do not introduce new package dependencies without discussion

### Functions
- Every function must have documentation (roxygen2 for R, docstrings for Python)
- Every function must have at least one test

---

## QC and Quality Standards

### Entry pipeline — stop-loudly (`R/clean_soilinfiltration.R`)

**Step 1 — double-entry comparison** (`detect_sheet_mismatches`):
- Sheet1 and Sheet2 must have the same row count and identical values in every cell.
- Mismatches are classified as `value`, `whitespace`, or `case`.
- Any mismatch: print table → `stop()`.

**Step 2 — per-row rules** (`detect_row_violations`); all rows checked before stopping:
- Site: missing → violation
- Subplot: missing → violation; not in VALID_SUBPLOTS → violation
- SuctionRate: missing → violation; not numeric → violation; not in VALID_SUCTIONS_CM → violation
- Time: missing → violation; negative → violation; > TIME_MAX_S (21 600 s) → violation
- Volume: missing → violation; negative → violation; > MAX_VOLUME_ML (95 mL) → violation
- SoilMoisture_12cm: **no checks** (reference measurement, carried through unchanged)

**Step 2 — replicate rules** (`detect_replicate_violations`; only if per-row passes):
- Per (Site, Subplot) group: exactly one t=0 anchor; Time strictly increasing; Volume
  non-increasing within VOL_MONOTONIC_TOLERANCE_ML (1 mL); SuctionRate constant.

All thresholds are declared as documented named constants in `R/soilinfiltration_config.R`.

### Compute pipeline — quality flags (`R/calculate_infiltration.R`)

Fit quality is not a data-entry error — flags do not stop the script; every replicate gets a row:

| `qc_flag` | Meaning |
|---|---|
| `OK` | r² ≥ 0.95 and C1 > 0; K reported |
| `REVIEW_low_r2` | r² < MIN_FIT_R2 (0.95); K reported, scientist reviews |
| `REVIEW_negative_C1` | C1 ≤ 0 (unphysical); K = NA |
| `UNKNOWN_insufficient_points` | n < MIN_FIT_POINTS (5); K = NA |
| `UNKNOWN_no_texture_lookup` | Subplot not found in subplot_soiltexture.csv; K = NA |

---

## Confidence and Quality Vocabulary

The fit-quality flags in `R/calculate_infiltration.R` map to the shared vocabulary from SCIENCE_PRINCIPLES.md:

| Shared label | `qc_flag` value |
|---|---|
| HIGH | `OK` |
| MEDIUM | `REVIEW_low_r2` |
| LOW | `REVIEW_negative_C1` |
| UNKNOWN | `UNKNOWN_insufficient_points`, `UNKNOWN_no_texture_lookup` |

Entry-pipeline violations (`clean_soilinfiltration.R`) carry no confidence label — they stop the script before any data reaches the compute stage.

---

## Output Metadata

Provenance is tracked via the append log rather than per-file JSON companions.

**`outputs/infiltration_append_log.csv`** — one row per `clean_soilinfiltration.R` run:

| Column | Contents |
|---|---|
| `run_datetime_utc` | ISO 8601 UTC timestamp of the run |
| `file_appended` | Basename of the daily `.xlsx` file processed |
| `date_appended` | Field date (YYYY-MM-DD) |
| `n_rows` | Number of rows appended to the master CSV |
| `git_commit` | Short hash of the repo at run time |

`outputs/` is gitignored; the log is regenerated by the pipeline. The master CSV
(`data/B2_SoilInfiltration_FullData.csv`) is git-tracked — committing it after each
field day provides the full append history via `git log`.

---

## Exclusion Logging

There are **no exclusion or unknown logs** in the entry pipeline. The stop-loudly model means no data is silently dropped — violations stop the script and the scientist fixes the source file. There is nothing to log.

The compute pipeline (`R/calculate_infiltration.R`) uses `qc_flag` values in the results CSV to flag replicates that could not yield a valid K (see QC and Quality Standards above). These are not "excluded" — they appear in the results with `K_cm_per_s = NA` and a descriptive `qc_flag`.

---

## Known Pending Items

<!-- List any known limitations, stopgap functions, or pending upstream
     fixes that affect this project. Update this list as issues are resolved. -->

| Item | Tracked in |
|---|---|
| [Description] | [GitHub issue URL] |

---

## Data Use and Citation

<!-- List any data use agreements, required citations, or attribution
     requirements that apply to data used in this project. -->

[LIST REQUIRED CITATIONS AND DATA USE OBLIGATIONS]
