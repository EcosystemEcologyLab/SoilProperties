# =============================================================================
# build_field_sheet_v2.R — generate the v2 field data sheet
# -----------------------------------------------------------------------------
# Produces output_template/Soil_Infiltration_FieldDataSheet_v2.xlsx:
#   * Preserves the original two-block layout and metadata header.
#   * Adds a SoilType column per plot, between Point ID and Time.
#   * SoilType cells carry a dropdown sourced from the 12-class controlled
#     vocabulary (read from data/reference/vg_parameters.csv — not hardcoded).
#   * Entry only — no formulas in the sheet.
#
# NOTE: This is a faithful RECONSTRUCTION of the field-entry layout from the
# project spec. The original Soil_Infiltration_FieldDataSheet.xlsx was not
# available in the repo when this was built; diff against the real sheet before
# field use.
#
# Run from project root:  Rscript output_template/build_field_sheet_v2.R
# =============================================================================

source("R/pipeline_config.R")

suppressPackageStartupMessages(library(openxlsx))

check_pipeline_config()
soil_types <- VALID_SOIL_TYPES        # controlled vocabulary (lowercase)

DATA_SHEET <- "Infiltration"
LIST_SHEET <- "Lists"
COLS <- c("Plot", "Point ID", "SoilType", "Time (sec)", "Volume (mL)")
N_DATA_ROWS <- 12                     # blank entry rows per block

wb <- createWorkbook()
addWorksheet(wb, DATA_SHEET)
addWorksheet(wb, LIST_SHEET, visible = FALSE)

# --- controlled vocabulary on a hidden sheet, referenced by the dropdown ---
writeData(wb, LIST_SHEET, data.frame(soil_type = soil_types), colNames = FALSE)
list_ref <- sprintf("'%s'!$A$1:$A$%d", LIST_SHEET, length(soil_types))

hdr_style  <- createStyle(textDecoration = "bold")
title_style <- createStyle(textDecoration = "bold", fontSize = 14)
meta_style <- createStyle(textDecoration = "bold")

# --- title + metadata header (label in col A, blank value in col B) ---
writeData(wb, DATA_SHEET, "Soil Infiltration Field Data Sheet (v2)",
          startCol = 1, startRow = 1)
addStyle(wb, DATA_SHEET, title_style, rows = 1, cols = 1)

meta_labels <- c("Site", "Date", "Time Start", "Time End",
                 "Suction Rate (cm)", "Observers", "Notes")
meta_rows <- 2:(1 + length(meta_labels))
for (i in seq_along(meta_labels)) {
  writeData(wb, DATA_SHEET, meta_labels[i], startCol = 1, startRow = meta_rows[i])
}
addStyle(wb, DATA_SHEET, meta_style, rows = meta_rows, cols = 1, gridExpand = TRUE)

# --- two stacked data blocks ---
block_start <- function(idx) {
  # block 1 header row 11, block 2 header row 11 + (N_DATA_ROWS + 3)
  11 + (idx - 1) * (N_DATA_ROWS + 3)
}

for (b in 1:2) {
  hr <- block_start(b)
  writeData(wb, DATA_SHEET, sprintf("Plot block %d", b),
            startCol = 1, startRow = hr - 1)
  addStyle(wb, DATA_SHEET, meta_style, rows = hr - 1, cols = 1)
  # column header row
  writeData(wb, DATA_SHEET, as.data.frame(t(COLS)), startCol = 1, startRow = hr,
            colNames = FALSE)
  addStyle(wb, DATA_SHEET, hdr_style, rows = hr, cols = seq_along(COLS),
           gridExpand = TRUE)
  # dropdown on SoilType column (col 3) across this block's data rows
  data_rows <- (hr + 1):(hr + N_DATA_ROWS)
  dataValidation(wb, DATA_SHEET, col = 3, rows = data_rows,
                 type = "list", value = list_ref, allowBlank = TRUE)
}

setColWidths(wb, DATA_SHEET, cols = 1:5, widths = c(10, 12, 18, 12, 14))

out <- "output_template/Soil_Infiltration_FieldDataSheet_v2.xlsx"
saveWorkbook(wb, out, overwrite = TRUE)
message("Field sheet written: ", out)
