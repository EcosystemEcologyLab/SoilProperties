# calculate_infiltration.R
# Batch compute step — run after the master CSV has been updated by
# clean_soilinfiltration.R.
#
# Usage: Rscript scripts/data_cleaning/calculate_infiltration.R
#
# Reads data/Full/B2_SoilInfiltration_FullData.csv, looks up van Genuchten alpha/n
# via the SoilType -> USDA texture mapping in data/reference/subplot_soiltexture.csv
# (field abbreviations are in the 'subplot' column of that file), fits
# I = C1*sqrt(t) + C2*t per replicate (grouped by Date + SoilType + Group),
# computes K (cm/s) via the Zhang (1997) A coefficient, and writes:
#   data/processed/B2_SoilInfiltration_Results.csv   — one row per replicate
#   figures/B2_SoilInfiltration_curves_<YYYYMMDD>.png — one panel per replicate

source("scripts/functions_config/soilinfiltration_config.R")
source("scripts/functions_config/infiltration_math.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(ggplot2)
})

# ── Reference tables ──────────────────────────────────────────────────────────

.load_refs <- function() {
  vg <- read.csv(file.path("data", "reference", "vg_parameters.csv"),
                 stringsAsFactors = FALSE)
  # subplot_soiltexture.csv: the 'subplot' column holds the field SoilType
  # abbreviations (PSAM, THSL, TCAM, THCL, TCAL); 'soil_texture' is the
  # USDA texture class used to look up VG parameters.
  st <- read.csv(file.path("data", "reference", "subplot_soiltexture.csv"),
                 stringsAsFactors = FALSE)
  list(vg = vg, abbrev_tex = st)
}

# ── Per-replicate compute ─────────────────────────────────────────────────────

.calc_replicate <- function(d, vg, abbrev_tex) {
  d <- d[order(as.numeric(d$Time)), ]

  soiltype_abbr <- d$SoilType[1]
  group         <- as.character(d$Group[1])
  suction_cm    <- as.numeric(d$SuctionRate[1])
  h0            <- -suction_cm

  # SoilType abbreviation -> USDA texture class
  tex_row      <- abbrev_tex[abbrev_tex$subplot == soiltype_abbr, ]
  soil_texture <- if (nrow(tex_row) == 1) tex_row$soil_texture[1] else NA_character_

  # USDA texture -> van Genuchten alpha and n
  vg_row <- if (!is.na(soil_texture)) vg[vg$soil_type == soil_texture, ] else vg[0, ]
  alpha  <- if (nrow(vg_row) == 1) vg_row$alpha[1] else NA_real_
  n_vg   <- if (nrow(vg_row) == 1) vg_row$n[1]     else NA_real_

  # Cumulative infiltration (cm) and two-parameter fit
  time_num <- as.numeric(d$Time)
  vol_num  <- as.numeric(d$Volume)
  V0  <- vol_num[time_num == 0][1]
  I   <- cumulative_infiltration(V0, vol_num, RADIUS_CM)
  fit <- fit_infiltration(time_num, I)

  C1       <- fit$C1
  n_points <- fit$n_points

  # Zhang (1997) A coefficient and K
  A <- if (!is.na(alpha) && !is.na(n_vg)) {
    A_coefficient(alpha, n_vg, RADIUS_CM, h0)
  } else {
    NA_real_
  }
  K <- if (!is.na(C1) && !is.na(A) && C1 > 0) C1 / A else NA_real_

  # QC flag — priority order per spec
  qc <- if (is.na(C1) || n_points < MIN_FIT_POINTS) {
    K <- NA_real_; "UNKNOWN_insufficient_points"
  } else if (C1 <= 0) {
    K <- NA_real_; "REVIEW_negative_C1"
  } else if (is.na(soil_texture) || is.na(alpha)) {
    K <- NA_real_; "UNKNOWN_no_texture_mapping"
  } else if (is.na(fit$r2) || fit$r2 < MIN_FIT_R2) {
    "REVIEW_low_r2"
  } else {
    k_upper <- unname(K_UPPER_CM_HR[tools::toTitleCase(soil_texture)])
    if (!is.na(k_upper) && !is.na(K) && (K * 3600) > k_upper) {
      "REVIEW_high_K"
    } else {
      "OK"
    }
  }

  # Take first non-NA soil moisture reading for the replicate
  sm_vals <- na.omit(d$SoilMoisture_12cm)
  soil_moisture <- if (length(sm_vals) > 0) as.numeric(sm_vals[1]) else NA_real_

  data.frame(
    Date              = d$Date[1],
    File              = d$File[1],
    SoilType_abbr     = soiltype_abbr,
    SoilTexture_VG    = if (is.na(soil_texture)) NA_character_ else soil_texture,
    Group             = group,
    SuctionRate_cm    = suction_cm,
    SoilMoisture_12cm = soil_moisture,
    n_points          = n_points,
    V0_mL             = V0,
    C1                = C1,
    C2                = fit$C2,
    r2                = fit$r2,
    alpha             = alpha,
    n_vg              = n_vg,
    A                 = A,
    K_cm_per_s        = K,
    K_cm_per_hr       = if (is.na(K)) NA_real_ else K * 3600,
    K_mm_per_hr       = if (is.na(K)) NA_real_ else K * 3600 * 10,
    qc_flag           = qc,
    stringsAsFactors  = FALSE
  )
}

# ── Curves figure (PNG, x-axis = sqrt(t)) ────────────────────────────────────

.write_curves_png <- function(master, results, png_path) {
  # Observed infiltration per row; x = sqrt(t) to linearise the Philip equation
  obs <- master |>
    mutate(
      Time   = as.numeric(Time),
      Volume = as.numeric(Volume)
    ) |>
    group_by(Date, SoilType, Group) |>
    mutate(
      V0     = Volume[Time == 0][1],
      I_cm   = cumulative_infiltration(V0, Volume, RADIUS_CM),
      sqrt_t = sqrt(Time)
    ) |>
    ungroup() |>
    mutate(rep_key = paste0(Date, "/", SoilType, "/", Group))

  # Build panel label: SoilType + Group + K + R² + QC flag
  panel_labels <- results |>
    mutate(
      rep_key = paste0(Date, "/", SoilType_abbr, "/", Group),
      panel   = sprintf(
        "%s  Grp %s\nK=%s cm/s  r²=%s  [%s]",
        SoilType_abbr,
        Group,
        ifelse(is.na(K_cm_per_s), "NA",
               formatC(K_cm_per_s, format = "e", digits = 2)),
        ifelse(is.na(r2), "NA", formatC(r2, digits = 3, format = "f")),
        qc_flag
      )
    ) |>
    select(rep_key, panel)

  obs <- obs |> left_join(panel_labels, by = "rep_key")

  # Fitted curves in sqrt(t) space: I = C1*sqrt_t + C2*sqrt_t^2
  fit_ok <- results |>
    filter(!is.na(C1) & !is.na(C2)) |>
    mutate(rep_key = paste0(Date, "/", SoilType_abbr, "/", Group))

  fit_lines_list <- lapply(seq_len(nrow(fit_ok)), function(i) {
    rr     <- fit_ok[i, ]
    sq_max <- max(obs$sqrt_t[obs$rep_key == rr$rep_key], na.rm = TRUE)
    if (!is.finite(sq_max) || sq_max <= 0) return(NULL)
    sq_seq <- seq(0, sq_max, length.out = 100)
    data.frame(
      rep_key = rr$rep_key,
      sqrt_t  = sq_seq,
      I_cm    = rr$C1 * sq_seq + rr$C2 * sq_seq^2,
      stringsAsFactors = FALSE
    )
  })
  fit_lines_raw <- Filter(Negate(is.null), fit_lines_list)
  fit_lines     <- if (length(fit_lines_raw) > 0) {
    do.call(rbind, fit_lines_raw) |> left_join(panel_labels, by = "rep_key")
  } else {
    NULL
  }

  # Drop rows with no panel label (shouldn't occur, but guards against mismatches)
  obs <- obs[!is.na(obs$panel), ]

  p <- ggplot(obs, aes(sqrt_t, I_cm)) +
    geom_point(size = 1.5, colour = "black") +
    facet_wrap(~ panel, scales = "free") +
    labs(
      x     = expression(sqrt(italic(t)) ~ "(s"^{0.5} * ")"),
      y     = "Cumulative infiltration (cm)",
      title = "B2 Soil Infiltration — fitted curves"
    ) +
    theme_bw(base_size = 8)

  if (!is.null(fit_lines) && nrow(fit_lines) > 0) {
    p <- p + geom_line(
      data = fit_lines, aes(sqrt_t, I_cm),
      colour = "firebrick", linewidth = 0.8
    )
  }

  dir.create(dirname(png_path), showWarnings = FALSE, recursive = TRUE)
  n_pan  <- length(unique(obs$panel))
  ncol_p <- min(3L, max(1L, n_pan))
  nrow_p <- ceiling(n_pan / ncol_p)
  ggsave(png_path, p,
         width = 3.5 * ncol_p, height = 3.0 * nrow_p,
         dpi = 150, limitsize = FALSE)
  invisible(png_path)
}

# ── Main ──────────────────────────────────────────────────────────────────────

run_calculate_infiltration <- function(master_csv = MASTER_CSV) {
  if (!file.exists(master_csv)) {
    stop("Master CSV not found: ", master_csv,
         "\nRun clean_soilinfiltration.R first to populate it.")
  }

  master <- read.csv(master_csv, stringsAsFactors = FALSE,
                     colClasses = c(Date = "character"))
  if (nrow(master) == 0) stop("Master CSV has no rows: ", master_csv)

  refs    <- .load_refs()
  results <- master |>
    group_by(Date, SoilType, Group) |>
    group_split() |>
    map_dfr(~ .calc_replicate(.x, refs$vg, refs$abbrev_tex))

  # Results CSV
  dir.create(file.path("data", "processed"), showWarnings = FALSE, recursive = TRUE)
  out_csv <- file.path("data", "processed", "B2_SoilInfiltration_Results.csv")
  write.csv(results, out_csv, row.names = FALSE)

  # Curves PNG (dated so successive runs don't overwrite)
  run_date <- format(Sys.Date(), "%Y%m%d")
  png_path <- file.path("figures",
                        paste0("B2_SoilInfiltration_curves_", run_date, ".png"))
  .write_curves_png(master, results, png_path)

  n_ok     <- sum(results$qc_flag == "OK",            na.rm = TRUE)
  n_high_k <- sum(results$qc_flag == "REVIEW_high_K", na.rm = TRUE)
  n_rev    <- sum(grepl("^REVIEW",  results$qc_flag), na.rm = TRUE)
  n_unk    <- sum(grepl("^UNKNOWN", results$qc_flag), na.rm = TRUE)
  message(sprintf(
    "calculate_infiltration complete: %d replicates (%d OK, %d REVIEW [incl. %d REVIEW_high_K], %d UNKNOWN)",
    nrow(results), n_ok, n_rev, n_high_k, n_unk))
  message("  -> ", out_csv)
  message("  -> ", png_path)

  invisible(results)
}

if (sys.nframe() == 0L) run_calculate_infiltration()
