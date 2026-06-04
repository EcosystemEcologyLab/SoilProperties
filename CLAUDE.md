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
- `data/overrides/` — human override decisions (infiltration_overrides.csv)

### 4. Pipeline hard rules
- Every output must have a companion `{output}.meta.json` (written by `write_meta()`).
- No record is ever silently dropped: exclusions go to `outputs/exclusion_log.csv`, unknowns to `outputs/unknown_log.csv`.
- Override decisions (`data/overrides/`) are read-only for scripts; the scientist edits them directly.
- All scientifically meaningful thresholds live in `R/pipeline_config.R` as documented named constants — never as magic numbers inline in scripts.

---

## Environment Variables

| Variable | Purpose | Default |
|---|---|---|
| `NEON_TOKEN` | Personal access token for `neonUtilities` downloads (avoids anonymous rate limits) | none required — anonymous access works |

---

## Pipeline Execution Order

Run from the project root; each script accepts a single file path argument.

```
R/01_qaqc_entry.R <field_sheet.xlsx>
  → QA/QC the daily field sheet; writes data/processed/{site}_{date}_infiltration_clean.csv
    plus appends to outputs/exclusion_log.csv and outputs/unknown_log.csv

R/02_calculate_infiltration.R <..._infiltration_clean.csv>
  → Fit I=C1√t+C2t, compute K via Zhang(1997)/van Genuchten; writes one
    data/processed/{site}_{date}_{soiltype}_infiltration_results.csv and
    figures/{site}_{date}_{soiltype}_curves.pdf per soil type, each with
    a .meta.json companion

R/03_append_fulldata.R <..._infiltration_results.csv>
  → Append replicate results to data/processed/B2_SoilInfiltration_FullData.xlsx
    (dedup key: site+date+plot+point_id; collisions preserved; overrides via
    data/overrides/infiltration_overrides.csv)
```

---

## Coding Conventions

### Language and style
- Primary language: R
- Style: tidyverse style guide (https://style.tidyverse.org/)
- Use base R pipe `|>` not `%>%` in new code; existing scripts use `%>%` (dplyr)

### Package preferences
- Data manipulation: dplyr, tidyr
- Reading field sheets: readxl (input), openxlsx (output xlsx)
- Plotting: ggplot2
- Metadata: jsonlite, digest
- Testing: testthat
- Do not introduce new package dependencies without discussion

### Functions
- Every function must have documentation (roxygen2 for R, docstrings for Python)
- Every function must have at least one test

---

## QC and Quality Standards

Six QC rules are applied in order by `R/01_qaqc_entry.R`; first failure wins:
1. **soil_type controlled vocabulary** — empty → UNKNOWN; unrecognised → EXCLUDE
2. **Numeric ranges** — missing time/volume → UNKNOWN; negative or > MAX_VOLUME_ML (95 mL) → EXCLUDE
3. **Monotonic time** — time decreasing within a replicate → EXCLUDE offending row
4. **Monotonic volume** — volume rise > VOL_MONOTONIC_TOLERANCE_ML (1 mL) → EXCLUDE offending row
5. **Suction validity** — suction not in VALID_SUCTIONS_CM {0.5,1,2,3,4,5,6,7} → EXCLUDE entire site-date
6. **t=0 anchor** — no t=0 row in replicate → UNKNOWN, replicate dropped

Fit quality (`R/02_calculate_infiltration.R`):
- `r² < MIN_FIT_R2 (0.95)` → `REVIEW_low_r2` (kept, scientist reviews)
- `C1 ≤ 0` → `REVIEW_negative_C1`, K set to NA
- `n < MIN_FIT_POINTS (5)` → `UNKNOWN_insufficient_points`, K set to NA

All thresholds are declared as named constants in `R/pipeline_config.R`.

---

## Confidence and Quality Vocabulary

This project uses the shared vocabulary from SCIENCE_PRINCIPLES.md:

| Label | `qc_flag` value | Meaning |
|---|---|---|
| HIGH | `OK` | Fit meets all thresholds; K reported |
| MEDIUM | `REVIEW_low_r2` | r² below MIN_FIT_R2 (0.95); K reported but flagged for review |
| LOW / EXCLUDE | `REVIEW_negative_C1` | Negative C1; K set to NA; logged to exclusion log |
| UNKNOWN | `UNKNOWN_insufficient_points` | Too few points to fit; K = NA; logged to unknown log |

QA/QC exclusion rows carry no confidence label — they never reach the fit stage.

---

## Output Metadata

Every CSV and PDF produced by scripts 02 and 03 gets a companion `{filename}.meta.json`
written by `R/write_meta.R`. The JSON contains:

```json
{
  "run_datetime_utc": "2026-06-02T18:25:56Z",
  "pipeline_version": "d60875f",
  "input_sources": [{"path": "...", "sha256": "..."}],
  "r_session_info": "outputs/session_info.txt",
  "notes": "free-text provenance notes"
}
```

`outputs/session_info.txt` captures `sessionInfo()` from the R session that produced the outputs.
All `*.meta.json` files and `outputs/` are gitignored; they are regenerated by running the pipeline.

---

## Exclusion Logging

Two append-mode CSV logs live in `outputs/` (gitignored, regenerated by the pipeline):

**`outputs/exclusion_log.csv`** — records every row that was removed from analysis:
| Column | Contents |
|---|---|
| `site_id` | Site name |
| `variable` | Column that triggered the rule (or `ALL` for site-date-level exclusions) |
| `timestamp` | time_s value of the excluded row (or `ALL`) |
| `reason` | machine-readable reason code (e.g. `soil_type_unrecognised`, `non_monotonic_volume`) |
| `threshold` | the rule that was violated |
| `excluded_by` | script filename that wrote the row |

**`outputs/unknown_log.csv`** — records records that could not be classified (missing data, insufficient points):
| Column | Contents |
|---|---|
| `record_id` | `site_date_plot_point_id` key |
| `reason` | machine-readable reason code (e.g. `soil_type_missing`, `no_t0_anchor`) |
| `logged_by` | script filename that wrote the row |

Both logs are created (header-only) even on a clean run, per "write both logs even if empty".

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
