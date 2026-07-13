# Human override files

This directory is **git-tracked** — its contents are scientific decisions, not
pipeline outputs (see `SCIENCE_PRINCIPLES_PIPELINES.md` → "Human override files").

The pipeline reads override files here, applies them, and flags them in output
metadata. **Claude / the pipeline must never write to or modify files in this
directory.** Override files survive reruns; they are inputs, not outputs.

## When an override is needed

`R/03_append_fulldata.R` refuses to overwrite an existing
`(site, date, plot, point_id)` key in `B2_SoilInfiltration_FullData.xlsx`. To
deliberately replace an existing record, add an override file here.

## Format

CSV named `infiltration_overrides.csv` with columns:

| Column | Content |
|--------|---------|
| `record_id` | `{site}_{date}_{plot}_{point_id}` of the record to replace |
| `decision` | `replace` (the only currently supported action) |
| `reason` | Human-readable justification |
| `date` | Date the decision was made (YYYY-MM-DD) |
| `author` | Person making the decision |
