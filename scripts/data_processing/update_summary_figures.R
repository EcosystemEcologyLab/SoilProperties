#' Standalone summary figure and README update script.
#'
#' Run via: Rscript scripts/data_processing/update_summary_figures.R
#' Not sourced by the infiltration pipeline — run separately or via CI.
#'
#' Reads each *_FullData CSV, generates summary figures in figures/summary/,
#' and rewrites README.md with the current data status table and K values table.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(tidyr)
})

dir.create("figures/summary", showWarnings = FALSE, recursive = TRUE)

# ── Helpers ───────────────────────────────────────────────────────────────────

read_if_data <- function(path) {
  if (!file.exists(path)) return(NULL)
  df <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(df) || nrow(df) == 0) return(NULL)
  df
}

# ── Load data ─────────────────────────────────────────────────────────────────

infil_full       <- read_if_data("data/Full/B2_SoilInfiltration_FullData.csv")
moisture         <- read_if_data("data/Full/B2_SoilMoisture_FullData.csv")
spectra          <- read_if_data("data/Full/SpectralIndices_FullData.csv")
infil_results    <- read_if_data("data/processed/B2_SoilInfiltration_Results.csv")
moisture_summary <- read_if_data("data/processed/B2_SoilMoisture_Summary.csv")
# Jmax/Vcmax: file not yet available; update path when data arrives
jmax_vcmax       <- read_if_data("data/B2_GasExchange_FullData.csv")

# ── Figure 1: Hyperspectral indices timeseries ────────────────────────────────
# Colours by plantID — SpectralIndices_FullData.csv has no SoilType column.
# If a plantID → SoilType lookup becomes available, replace the colour aesthetic.

if (!is.null(spectra)) {
  index_cols <- grep("_mean$", names(spectra), value = TRUE)

  spectra_long <- spectra |>
    mutate(date = as.Date(date)) |>
    pivot_longer(
      cols  = all_of(index_cols),
      names_to  = "index",
      values_to = "value"
    ) |>
    mutate(index = sub("_mean$", "", index))

  p1 <- ggplot(spectra_long,
               aes(x = date, y = value, colour = plantID, group = plantID)) +
    geom_line(linewidth = 0.6) +
    geom_point(size = 1.5) +
    facet_wrap(~index, scales = "free_y") +
    labs(
      title   = "Hyperspectral indices over time",
      x       = "Date",
      y       = "Index value",
      colour  = "Plant ID"
    ) +
    theme_bw() +
    theme(legend.position = "bottom")

  ggsave("figures/summary/hyperspectral_indices_timeseries.png", p1,
         width = 16, height = 12, dpi = 150)
  message("Saved: figures/summary/hyperspectral_indices_timeseries.png")
} else {
  message("SpectralIndices_FullData.csv has no data — skipping hyperspectral figure")
}

# ── Figure 2: Soil moisture per-plant daily averages ─────────────────────────
# Reads the wide-format summary produced by summarise_soilmoisture.R.
# Pivots back to long for faceting by sensor type (T vs M).

if (!is.null(moisture_summary)) {
  moisture_long <- moisture_summary |>
    mutate(Date = as.Date(Date)) |>
    tidyr::pivot_longer(
      cols         = tidyr::matches("_(mean|sd)$"),
      names_to     = c("sensor_depth", ".value"),
      names_pattern = "^(.+)_(mean|sd)$"
    ) |>
    mutate(
      Sensor       = sub("_.*$", "", sensor_depth),
      sensor_label = dplyr::case_when(
        Sensor == "T" ~ "Temperature (°C)",
        Sensor == "M" ~ "Soil moisture (% VWC)",
        TRUE          ~ Sensor
      )
    )

  p2 <- ggplot(moisture_long,
               aes(x = Date, y = mean, colour = SoilType, group = PlantID)) +
    geom_point(size = 1.5, alpha = 0.7) +
    geom_errorbar(
      aes(ymin = mean - sd, ymax = mean + sd),
      width = 0.5, alpha = 0.5
    ) +
    facet_wrap(~sensor_label, ncol = 1, scales = "free_y") +
    labs(
      title  = "Soil moisture and temperature — per-plant daily averages",
      x      = "Date",
      y      = "Mean value",
      colour = "Soil type"
    ) +
    theme_bw() +
    theme(legend.position = "bottom")

  ggsave("figures/summary/soilmoisture_summary.png", p2,
         width = 10, height = 8, dpi = 150)
  message("Saved: figures/summary/soilmoisture_summary.png")
} else {
  message("B2_SoilMoisture_Summary.csv has no data — skipping soil moisture figure")
}

# ── Figure 3: Jmax and Vcmax timeseries ──────────────────────────────────────
# Expected columns in B2_GasExchange_FullData.csv: Date, SoilType, Jmax, Vcmax.
# Update column names here if the schema differs when the file becomes available.

if (!is.null(jmax_vcmax)) {
  jmax_long <- jmax_vcmax |>
    mutate(Date = as.Date(Date)) |>
    pivot_longer(
      cols      = c(Jmax, Vcmax),
      names_to  = "parameter",
      values_to = "value"
    )

  p3 <- ggplot(jmax_long,
               aes(x = Date, y = value, colour = SoilType, group = SoilType)) +
    geom_line(linewidth = 0.6) +
    geom_point(size = 1.5) +
    facet_wrap(~parameter, ncol = 1, scales = "free_y") +
    labs(
      title  = "Jmax and Vcmax over time",
      x      = "Date",
      y      = expression(paste("Value (", mu, "mol m"^{-2}, " s"^{-1}, ")")),
      colour = "Soil type"
    ) +
    theme_bw() +
    theme(legend.position = "bottom")

  ggsave("figures/summary/jmax_vcmax_timeseries.png", p3,
         width = 10, height = 8, dpi = 150)
  message("Saved: figures/summary/jmax_vcmax_timeseries.png")
} else {
  message("Jmax/Vcmax data not available — skipping figure (expected: data/B2_GasExchange_FullData.csv)")
}

# ── Build data status table ───────────────────────────────────────────────────

get_status <- function(path) {
  if (!file.exists(path)) return(c(last_date = "—", n_rows = "—"))
  df <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(df)) return(c(last_date = "error", n_rows = "error"))
  if (nrow(df) == 0) return(c(last_date = "—", n_rows = "0"))
  date_col <- intersect(c("Date", "date"), names(df))[1]
  last_date <- if (!is.na(date_col)) max(df[[date_col]], na.rm = TRUE) else "—"
  c(last_date = as.character(last_date), n_rows = as.character(nrow(df)))
}

datasets <- list(
  list(label = "Infiltration field data", path = "data/Full/B2_SoilInfiltration_FullData.csv"),
  list(label = "Soil moisture",           path = "data/Full/B2_SoilMoisture_FullData.csv"),
  list(label = "Hyperspectral indices",   path = "data/Full/SpectralIndices_FullData.csv"),
  list(label = "Jmax / Vcmax",           path = "data/B2_GasExchange_FullData.csv")
)

status_rows <- lapply(datasets, function(d) {
  s <- get_status(d$path)
  sprintf("| %s | %s | %s |", d$label, s["last_date"], s["n_rows"])
})

status_md <- paste(
  c("| Data type | Last update | Row count |",
    "|---|---|---|",
    unlist(status_rows)),
  collapse = "\n"
)

# ── Build K values table ──────────────────────────────────────────────────────

if (!is.null(infil_results)) {
  k_rows <- infil_results |>
    group_by(SoilType_abbr) |>
    filter(Date == max(Date)) |>
    ungroup() |>
    arrange(Date, SoilType_abbr, Group) |>
    mutate(
      K_fmt = ifelse(is.na(K_cm_per_hr), "NA", sprintf("%.3f", K_cm_per_hr))
    )

  k_table_rows <- sprintf(
    "| %s | %s | %s | %s | %s |",
    k_rows$Date, k_rows$SoilType_abbr, k_rows$Group, k_rows$K_fmt, k_rows$qc_flag
  )
  k_md <- paste(
    c("| Date | SoilType | Group | K\\_cm\\_per\\_hr | qc\\_flag |",
      "|---|---|---|---|---|",
      k_table_rows),
    collapse = "\n"
  )
} else {
  k_md <- "_No results yet._"
}

# ── Rewrite README.md ─────────────────────────────────────────────────────────

readme <- paste0(
  "# SoilProperties\n\n",
  "Field measurements of soil properties and plant physiological responses to induced drought conditions\n",
  "at the Biosphere 2 (2026 campaign). We characterise plant responses to changing precipitation\n",
  "across several soil types by measuring infiltration rates (saturated hydraulic conductivity K, derived\n",
  "via Philip's two-term equation and Zhang 1997 / van Genuchten), soil moisture at 12 cm and 20 cm\n",
  "depth, hyperspectral reflectance indices, and leaf-level gas exchange parameters (Jmax, Vcmax). The\n",
  "goal is to resolve how specific soil physical properties constrain plant function in semi-arid\n",
  "ecosystems where soil water retention is hypothesised to exert a stronger influence on gross primary\n",
  "productivity than climate variables alone.\n\n",
  "**PI:** David J.P. Moore, University of Arizona  \n",
  "**Collaborators:** Angie Abarzua Munoz; Lindsey Bell\n\n",
  "---\n\n",
  "## Data status\n\n",
  "<!-- Updated automatically by scripts/data_processing/update_summary_figures.R on each push to main -->\n\n",
  status_md, "\n\n",
  "---\n\n",
  "## Infiltration\n\n",
  "Most recent K values (saturated hydraulic conductivity) per replicate from\n",
  "`data/processed/B2_SoilInfiltration_Results.csv`:\n\n",
  "<!-- Updated automatically by scripts/data_processing/update_summary_figures.R on each push to main -->\n\n",
  k_md, "\n\n",
  "---\n\n",
  "## Figures\n\n",
  "Figures are auto-generated by `scripts/data_processing/update_summary_figures.R` and committed by CI on each data update.\n\n",
  "### Hyperspectral indices\n\n",
  "![Hyperspectral indices timeseries](figures/summary/hyperspectral_indices_timeseries.png)\n\n",
  "### Soil moisture\n\n",
  "![Soil moisture per-plant summary](figures/summary/soilmoisture_summary.png)\n\n",
  "### Jmax and Vcmax\n\n",
  "![Jmax and Vcmax timeseries](figures/summary/jmax_vcmax_timeseries.png)\n\n",
  "---\n\n",
  "## Documentation\n\n",
  "- [Infiltration workflow](docs/infiltration_workflow.md)\n"
)

writeLines(readme, "README.md")
message("Updated README.md")
