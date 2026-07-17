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
- `figures/` — PNG curve plots

The following directories are git-tracked:
- `data/reference/` — vg_parameters.csv, infiltrometer_radii.csv, subplot_soiltexture.csv (SoilType abbreviation→USDA texture lookup; confirmed by Lindsey Bell 2026-06-04)

### 4. Pipeline hard rules
- Entry pipeline is **stop-loudly**: print violations table, `stop()`, scientist fixes source `.xlsx` and re-runs. Nothing is silently dropped or flagged-and-continued.
- All scientifically meaningful thresholds live in `scripts/functions_config/soilinfiltration_config.R` as documented named constants — never as magic numbers inline in scripts.
- `SoilTexture` (USDA class) is never entered in the field sheet — it is derived automatically from the `SoilType` abbreviation (PSAM, TCAM, etc.) via `data/reference/subplot_soiltexture.csv`.

---

## Environment Variables

| Variable | Purpose | Default |
|---|---|---|
| `INFILTRATION_DATA_DIR` | Full path to the network folder containing daily infiltration `.xlsx` files | *(prompts if unset)* |
| `SOILMOISTURE_DATA_DIR` | Full path to the network folder containing daily soil-moisture `.xlsx` files | *(prompts if unset)* |
| `ASD_DATA_DIR` | Full path to the ASD base data folder (parent of `ProcessedReflectance/`, `SpectralID/`, `FullSpectralFieldData/`) | *(prompts if unset)* |
| `TRAILCAM_RAW_IMAGE_DIR` | Root folder of trail camera images; must contain one subdirectory per camera ID | *(prompts if unset)* |

Set these in a local `.env` file (copy `.env.example`; the file is gitignored). Windows, UNC, and Mac path examples are in `.env.example`.

`.Rprofile` loads `.env` automatically at session start via `dotenv::load_dot_env()` — contributors do not need to call it manually.

---

## Pipeline Execution Order

**Note:** The entry pipelines (clean_soilinfiltration.R, clean_soilmoisture.R, process_asd.R) and the trail camera pipeline run locally in RStudio on a machine with the lab network share mounted — they are not designed to run inside the devcontainer or Codespaces environment, which has no network mount configured.

### Entry pipeline (interactive, run from RStudio)

1. Open `SoilProperties.Rproj` in RStudio (sets working dir to project root).
2. Enter data into both sheets of a new `.xlsx` file using the template at
   `output_template/Soil_Infiltration_FieldData_template.xlsx`.
   File must be named `Soil_Infiltration_FieldData_YYYYMMDD.xlsx`.
3. `source("scripts/data_cleaning/clean_soilinfiltration.R")` — prompts for the file path, then:
   - Step 1: compares Sheet1 and Sheet2 cell-by-cell; `stop()` on any mismatch
   - Step 2: validates date, per-row rules, and replicate rules; `stop()` on any violation
   - Step 3: appends Sheet1 rows (with Date and File prepended) to `data/Full/B2_SoilInfiltration_FullData.csv`
             and writes one row to `outputs/infiltration_append_log.csv`
4. Commit the updated `data/Full/B2_SoilInfiltration_FullData.csv` to a branch and open a PR.

### Compute pipeline (batch, run from terminal)

```
Rscript scripts/data_processing/calculate_infiltration.R
```

### ASD hyperspectral pipeline (standalone)

`scripts/data_processing/process_asd.R` — processes ASD Field Spec 3 reflectance
data (reads `ProcessedReflectance_YYYYMMDD.txt` + `SpectralID_YYYYMMDD.csv`,
calculates 19 Barnes et al. 2017 spectral indices, appends to
`SpectralIndices_FullData.csv`). Configure paths at the top of the file before
each run. Not part of the infiltration or soil moisture pipelines.

Reads `data/Full/B2_SoilInfiltration_FullData.csv`, derives USDA SoilTexture from
the `SoilType` abbreviation (via `data/reference/subplot_soiltexture.csv`), fits
I = C1√t + C2t per replicate (grouped by Date + SoilType + Group), computes K
via Zhang (1997) / van Genuchten.

Writes:
- `data/processed/B2_SoilInfiltration_Results.csv` — one row per replicate
- `figures/B2_SoilInfiltration_curves_<YYYYMMDD>.png` — one panel per replicate (x-axis = √t)

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

### Entry pipeline — stop-loudly (`scripts/data_cleaning/clean_soilinfiltration.R`)

**Step 1 — double-entry comparison** (`detect_sheet_mismatches`):
- Sheet1 and Sheet2 must have the same row count and identical values in every cell.
- Mismatches are classified as `value`, `whitespace`, or `case`.
- Any mismatch: print table → `stop()`.

**Step 2 — per-row rules** (`detect_row_violations`); all rows checked before stopping:
- SoilType: missing → violation; not in VALID_SOIL_TYPES → violation
- Group: missing → violation
- SuctionRate: missing → violation; not numeric → violation; not in VALID_SUCTIONS_CM → violation
- Time: missing → violation; negative → violation; > TIME_MAX_S (21 600 s) → violation
- Volume: missing → violation; negative → violation; > MAX_VOLUME_ML (95 mL) → violation
- SoilMoisture_12cm: **no checks** (reference measurement, carried through unchanged)

**Step 2 — replicate rules** (`detect_replicate_violations`; only if per-row passes):
- Per (SoilType, Group): exactly one t=0 anchor; Time strictly increasing; Volume
  non-increasing within VOL_MONOTONIC_TOLERANCE_ML (1 mL); SuctionRate constant.

All thresholds are declared as documented named constants in `scripts/functions_config/soilinfiltration_config.R`.

### Compute pipeline — quality flags (`scripts/data_processing/calculate_infiltration.R`)

Fit quality is not a data-entry error — flags do not stop the script; every replicate gets a row:

| `qc_flag` | Meaning |
|---|---|
| `OK` | r² ≥ 0.95 and C1 > 0 and K ≤ texture bound; K reported |
| `REVIEW_negative_C1` | C1 ≤ 0 (unphysical); K = NA |
| `REVIEW_low_r2` | r² < MIN_FIT_R2 (0.95); K reported, scientist reviews |
| `REVIEW_high_K` | K > K_UPPER_CM_HR bound for texture (physically possible but unusually high); K reported, check field notes |
| `UNKNOWN_insufficient_points` | n < MIN_FIT_POINTS (5) or fit failed; K = NA |
| `UNKNOWN_no_texture_mapping` | SoilType abbreviation not in subplot_soiltexture.csv; K = NA |

---

## Confidence and Quality Vocabulary

The fit-quality flags in `scripts/data_processing/calculate_infiltration.R` map to the shared vocabulary from SCIENCE_PRINCIPLES.md:

| Shared label | `qc_flag` value |
|---|---|
| HIGH | `OK` |
| MEDIUM | `REVIEW_low_r2`, `REVIEW_high_K` |
| LOW | `REVIEW_negative_C1` |
| UNKNOWN | `UNKNOWN_insufficient_points`, `UNKNOWN_no_texture_mapping` |

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
(`data/Full/B2_SoilInfiltration_FullData.csv`) is git-tracked — committing it after each
field day provides the full append history via `git log`.

---

## Exclusion Logging

There are **no exclusion or unknown logs** in the entry pipeline. The stop-loudly model means no data is silently dropped — violations stop the script and the scientist fixes the source file. There is nothing to log.

The compute pipeline (`scripts/data_processing/calculate_infiltration.R`) uses `qc_flag` values in the results CSV to flag replicates that could not yield a valid K (see QC and Quality Standards above). These are not "excluded" — they appear in the results with `K_cm_per_s = NA` and a descriptive `qc_flag`.

---

## Known Pending Items

<!-- List any known limitations, stopgap functions, or pending upstream
     fixes that affect this project. Update this list as issues are resolved. -->

| Item | Tracked in |
|---|---|
| [Description] | [GitHub issue URL] |

### Pending Package Additions

The following packages are required by the trail camera vegetation-index pipeline and must be reviewed and approved by the PI before `renv::snapshot()` locks them in. Do not run `renv::snapshot()` until both are approved.

| Package | Purpose | System dependency |
|---|---|---|
| `magick` | Image I/O, cropping, and OCR — reads and crops JPEG/PNG images; uses its bundled Tesseract to read timestamps embedded in image frames | ImageMagick library (`libmagick++-dev` on Linux; `brew install imagemagick` on Mac) |
| `exifr` | EXIF timestamp extraction as a fallback when frame-embedded timestamps are unavailable or unreadable by OCR | System `exiftool` (`libimage-exiftool-perl` on Linux; `brew install exiftool` on Mac) |

---

## Data Use and Citation

<!-- List any data use agreements, required citations, or attribution
     requirements that apply to data used in this project. -->

[LIST REQUIRED CITATIONS AND DATA USE OBLIGATIONS]
