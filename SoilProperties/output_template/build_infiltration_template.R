# build_infiltration_template.R
# Generates output_template/Soil_Infiltration_FieldData_template.xlsx.
# Run from the project root: Rscript output_template/build_infiltration_template.R
#
# Two identical sheets (Sheet1, Sheet2) with columns:
#   Site, Subplot, SuctionRate, Time, Volume, SoilMoisture_12cm
#
# Data validation dropdowns:
#   Subplot     — VALID_SUBPLOTS from soilinfiltration_config.R
#   SuctionRate — VALID_SUCTIONS_CM from soilinfiltration_config.R
#
# SoilTexture is NOT entered by observers — it is derived automatically from
# Subplot via data/reference/subplot_soiltexture.csv.
#
# No formulas in the template — entry only.

source("scripts/functions_config/soilinfiltration_config.R")
library(openxlsx)

OUT_PATH  <- file.path("output_template", "Soil_Infiltration_FieldData_template.xlsx")
COLS      <- c("Site", "Subplot", "SuctionRate", "Time", "Volume", "SoilMoisture_12cm")
N_ROWS    <- 200L   # data rows reserved (beyond the header)

wb <- createWorkbook()

for (sheet_name in c("Sheet1", "Sheet2")) {
  addWorksheet(wb, sheet_name)

  # Header row
  writeData(wb, sheet_name, as.data.frame(t(COLS)), startRow = 1,
            startCol = 1, colNames = FALSE)

  # Bold header style
  hdr_style <- createStyle(textDecoration = "bold", border = "Bottom")
  addStyle(wb, sheet_name, hdr_style,
           rows = 1, cols = seq_along(COLS), gridExpand = TRUE)

  # Column widths
  setColWidths(wb, sheet_name, cols = seq_along(COLS),
               widths = c(8, 10, 12, 8, 8, 18))

  # ── Data validation ──────────────────────────────────────────────────────────
  data_rows <- seq(2, N_ROWS + 1)

  # Subplot dropdown
  subplot_col <- which(COLS == "Subplot")
  dataValidation(wb, sheet_name,
                 col = subplot_col, rows = data_rows,
                 type = "list",
                 value = paste0('"', paste(VALID_SUBPLOTS, collapse = ","), '"'))

  # SuctionRate dropdown
  suction_col <- which(COLS == "SuctionRate")
  dataValidation(wb, sheet_name,
                 col = suction_col, rows = data_rows,
                 type = "list",
                 value = paste0('"', paste(VALID_SUCTIONS_CM, collapse = ","), '"'))
}

saveWorkbook(wb, OUT_PATH, overwrite = TRUE)
message("Template written to: ", OUT_PATH)
