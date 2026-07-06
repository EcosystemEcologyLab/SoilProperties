# Reference tables — provenance

These two CSVs are **git-tracked** scientific reference data. They are read by
`scripts/data_processing/calculate_infiltration.R`. Do not edit them without a
commit message explaining the scientific reason for the change.

## `vg_parameters.csv`

Van Genuchten α (1/cm) and *n* (dimensionless) parameters for the 12-class USDA
soil-texture controlled vocabulary.

- Columns: `soil_type`, `alpha` (1/cm), `n` (dimensionless)
- `soil_type` is the controlled vocabulary used everywhere in this pipeline
  (`VALID_SOIL_TYPES` is derived from this column — never hardcoded).
- **Source:** Parameter table distributed with the METER Group MiniDisk
  Infiltrometer calculation workbook
  (`MinidiskInfiltrometer_CalculationSheet_METER.xlsx`, "Van Genuchten Tables"
  sheet), which itself reproduces the van Genuchten / Zhang (1997) texture-class
  parameter set.
- **Citation:** Zhang, R. (1997). Determination of soil sorptivity and hydraulic
  conductivity from the disk infiltrometer. *Soil Science Society of America
  Journal*, 61(4), 1024–1030.

## `infiltrometer_radii.csv`

Disk radius (cm) for each MiniDisk infiltrometer model.

- Columns: `infiltrometer_type`, `radius_cm`
- **Source:** METER Group MiniDisk Infiltrometer documentation. The standard
  MiniDisk disk radius is 2.25 cm; the older "MiniDisk Version1" disk radius is
  1.6 cm.
- The active radius for a pipeline run is selected in
  `scripts/functions_config/soilinfiltration_config.R` by
  `INFILTROMETER_TYPE` (default `"MiniDisk"`).
