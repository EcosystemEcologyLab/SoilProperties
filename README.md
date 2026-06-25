# SoilProperties

Soil infiltration measurements from the Biosphere 2 induced-drought experiment.
Characterises plant responses to changing precipitation across soil types by
fitting Philip's two-term equation (I = C₁√t + C₂t) per replicate and deriving
saturated hydraulic conductivity (K) via Zhang (1997) / van Genuchten.

**PI:** David J.P. Moore, University of Arizona  
**Collaborators:** Angie Abarzua Munoz; Lindsey Bell

---

## Soil infiltration pipeline

### One-time setup

1. Open `SoilProperties.Rproj` in RStudio (sets the working directory to the
   project root — all paths in the scripts are relative to this root).
2. Install required packages if not already present:
   ```r
   install.packages(c("openxlsx", "dplyr", "purrr", "ggplot2"))
   ```
3. Confirm that the reference files exist:
   - `data/reference/subplot_soiltexture.csv` — SoilType abbreviation → USDA texture class
   - `data/reference/vg_parameters.csv` — van Genuchten α and n per texture class
   - `data/reference/infiltrometer_radii.csv` — MiniDisk disk radius

### Day-to-day workflow (four steps)

1. **Open the project** — double-click `SoilProperties.Rproj` in RStudio.
2. **Drop the field file into `data/raw/`** — the file must be named
   `Soil_Infiltration_FieldData_YYYYMMDD.xlsx` and filled in from the template
   at `output_template/Soil_Infiltration_FieldData_template.xlsx`.
   Both Sheet1 and Sheet2 must be completed (double-entry verification).
3. **Run the pipeline** — in the RStudio console:
   ```r
   source("R/run_infiltration_pipeline.R")
   ```
   When prompted, enter the filename (e.g. `Soil_Infiltration_FieldData_20260611.xlsx`).
   A bare filename is resolved to `data/raw/` automatically; a full or relative
   path is also accepted. The script prints the resolved path before doing anything —
   confirm it looks correct before proceeding.
4. **Follow the printed git commands** — on success the script prints the exact
   commands to create a branch, commit the updated master CSV and results CSV,
   push, and open a pull request for Lindsey to review before merging.

### QC flags

Every replicate in `data/processed/B2_SoilInfiltration_Results.csv` carries a
`qc_flag`. Flags do not stop the script — every replicate gets a row.

| `qc_flag` | Confidence | Meaning |
|---|---|---|
| `OK` | HIGH | r² ≥ 0.95, C1 > 0, K within texture bound; K reported |
| `REVIEW_low_r2` | MEDIUM | r² < 0.95; K reported — check fit quality |
| `REVIEW_high_K` | MEDIUM | K above the typical upper bound for this texture; K reported — check field notes |
| `REVIEW_negative_C1` | LOW | C1 ≤ 0 (unphysical fit); K = NA |
| `UNKNOWN_insufficient_points` | UNKNOWN | Fewer than 5 points or fit failed; K = NA |
| `UNKNOWN_no_texture_mapping` | UNKNOWN | SoilType abbreviation not in subplot_soiltexture.csv; K = NA |

### When the pipeline stops

The entry pipeline is stop-loudly: it prints a table of violations and stops
before writing anything. No data is silently dropped.

**Sheet mismatch (Step 1):** the table shows which cells differ between Sheet1
and Sheet2 and whether the difference is a value, whitespace, or case mismatch.
Open the `.xlsx`, fix both sheets to agree, save, and re-run.

**Validation violation (Step 2):** the table shows the row, the rule that
failed, and the observed value. Common causes: SoilType abbreviation not in the
allowed list, Time or Volume outside valid range, missing t = 0 anchor, or
non-monotonic Volume. Fix the source `.xlsx` and re-run. The script never writes
to the entry file.

All thresholds are declared as named constants in `R/soilinfiltration_config.R`.
Changing a threshold is a scientific decision — commit the change with a clear
message explaining why.
