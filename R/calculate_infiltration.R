# calculate_infiltration.R
# Batch compute step — run after the master CSV has been updated by
# clean_soilinfiltration.R.
#
# Usage: Rscript R/calculate_infiltration.R
#
# Reads data/B2_SoilInfiltration_FullData.csv, fits I = C1*sqrt(t) + C2*t per
# replicate (grouped by Date + Site + Subplot), looks up van Genuchten alpha/n
# via the Subplot -> SoilTexture mapping in data/reference/subplot_soiltexture.csv,
# computes K (cm/s) via the Zhang (1997) A coefficient, and writes:
#   data/processed/B2_SoilInfiltration_Results.csv   — one row per replicate
#   figures/B2_SoilInfiltration_curves_<YYYYMMDD>.pdf — one panel per replicate

source("R/soilinfiltration_config.R")
source("R/infiltration_math.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(ggplot2)
})

# ── Reference tables ────────────────────────────────────────────────────────────

.load_refs <- function() {
  vg <- read.csv(file.path("data", "reference", "vg_parameters.csv"),
                 stringsAsFactors = FALSE)
  st <- read.csv(file.path("data", "reference", "subplot_soiltexture.csv"),
                 stringsAsFactors = FALSE)
  list(vg = vg, subplot_tex = st)
}

# ── Per-replicate compute ───────────────────────────────────────────────────────

.calc_replicate <- function(d, vg, subplot_tex, radius_cm) {
  d <- d[order(d$Time), ]

  subplot      <- d$Subplot[1]
  suction_cm   <- as.numeric(d$SuctionRate[1])
  h0           <- -suction_cm

  # Subplot -> SoilTexture lookup
  tex_row      <- subplot_tex[subplot_tex$subplot == subplot, ]
  soil_texture <- if (nrow(tex_row) == 1) tex_row$soil_texture[1] else NA_character_

  # Van Genuchten parameters
  vg_row <- if (!is.na(soil_texture)) vg[vg$soil_type == soil_texture, ] else vg[0, ]
  alpha  <- if (nrow(vg_row) == 1) vg_row$alpha[1] else NA_real_
  n_vg   <- if (nrow(vg_row) == 1) vg_row$n[1]     else NA_real_

  # Cumulative infiltration and fit
  V0   <- d$Volume[d$Time == 0][1]
  I    <- cumulative_infiltration(V0, d$Volume, radius_cm)
  fit  <- fit_infiltration(d$Time, I)

  C1       <- fit$C1
  n_points <- fit$n_points

  # A coefficient and K
  A <- if (!is.na(alpha) && !is.na(n_vg)) {
    A_coefficient(alpha, n_vg, radius_cm, h0)
  } else {
    NA_real_
  }

  K <- if (!is.na(C1) && !is.na(A) && C1 > 0) C1 / A else NA_real_

  # QC flag (precedence: insufficient > negative C1 > missing texture > low r2 > OK)
  qc <- if (is.na(C1) || n_points < MIN_FIT_POINTS) {
    K <- NA_real_
    "UNKNOWN_insufficient_points"
  } else if (C1 <= 0) {
    K <- NA_real_
    "REVIEW_negative_C1"
  } else if (is.na(soil_texture) || is.na(alpha)) {
    K <- NA_real_
    "UNKNOWN_no_texture_lookup"
  } else if (is.na(fit$r2) || fit$r2 < MIN_FIT_R2) {
    "REVIEW_low_r2"
  } else {
    "OK"
  }

  data.frame(
    Date               = d$Date[1],
    Site               = d$Site[1],
    Subplot            = subplot,
    SoilTexture        = if (is.na(soil_texture)) "" else soil_texture,
    SuctionRate        = suction_cm,
    infiltrometer_type = INFILTROMETER_TYPE,
    radius_cm          = radius_cm,
    n_points           = n_points,
    C1                 = C1,
    C2                 = fit$C2,
    r2                 = fit$r2,
    alpha              = alpha,
    n_vg               = n_vg,
    A                  = A,
    K_cm_per_s         = K,
    K_cm_per_hr        = if (is.na(K)) NA_real_ else K * 3600,
    qc_flag            = qc,
    stringsAsFactors   = FALSE
  )
}

# ── Curves PDF ──────────────────────────────────────────────────────────────────

.write_curves_pdf <- function(master, results, pdf_path, radius_cm) {
  # Observed infiltration per row
  obs <- master |>
    group_by(Date, Site, Subplot) |>
    mutate(
      V0   = Volume[Time == 0][1],
      I_cm = cumulative_infiltration(V0, Volume, radius_cm)
    ) |>
    ungroup() |>
    mutate(rep = paste0(Date, " / ", Site, " / ", Subplot))

  fitted <- results |>
    filter(!is.na(C1) & !is.na(C2)) |>
    mutate(rep = paste0(Date, " / ", Site, " / ", Subplot))

  fit_lines <- do.call(rbind, lapply(seq_len(nrow(fitted)), function(i) {
    rr   <- fitted[i, ]
    tmax <- max(obs$Time[obs$rep == rr$rep], na.rm = TRUE)
    tg   <- seq(0, tmax, length.out = 100)
    data.frame(rep = rr$rep, Time = tg,
               I_cm = rr$C1 * sqrt(tg) + rr$C2 * tg,
               stringsAsFactors = FALSE)
  }))

  strip <- results |>
    mutate(
      rep = paste0(Date, " / ", Site, " / ", Subplot),
      lab = sprintf(
        "%s\nK=%s cm/s  r²=%s  [%s]",
        rep,
        ifelse(is.na(K_cm_per_s), "NA",
               formatC(K_cm_per_s, format = "e", digits = 2)),
        ifelse(is.na(r2), "NA", formatC(r2, digits = 3, format = "f")),
        qc_flag
      )
    )
  lab_map     <- setNames(strip$lab, strip$rep)
  obs$panel   <- lab_map[obs$rep]
  if (!is.null(fit_lines) && nrow(fit_lines) > 0) {
    fit_lines$panel <- lab_map[fit_lines$rep]
  }

  p <- ggplot(obs, aes(Time, I_cm)) +
    geom_point(size = 1.3) +
    facet_wrap(~ panel, scales = "free") +
    labs(x = "Time (s)", y = "Cumulative infiltration (cm)",
         title = "B2 Soil Infiltration — fitted curves") +
    theme_bw(base_size = 8)
  if (!is.null(fit_lines) && nrow(fit_lines) > 0) {
    p <- p + geom_line(data = fit_lines, aes(Time, I_cm), colour = "firebrick")
  }

  dir.create(dirname(pdf_path), showWarnings = FALSE, recursive = TRUE)
  n_pan  <- length(unique(obs$panel))
  ncol_p <- min(3L, max(1L, n_pan))
  nrow_p <- ceiling(n_pan / ncol_p)
  ggsave(pdf_path, p, width = 3.2 * ncol_p, height = 2.8 * nrow_p,
         limitsize = FALSE)
  invisible(pdf_path)
}

# ── Main ────────────────────────────────────────────────────────────────────────

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
    group_by(Date, Site, Subplot) |>
    group_split() |>
    map_dfr(~ .calc_replicate(.x, refs$vg, refs$subplot_tex, RADIUS_CM))

  # Results CSV
  dir.create(file.path("data", "processed"), showWarnings = FALSE, recursive = TRUE)
  out_csv <- file.path("data", "processed", "B2_SoilInfiltration_Results.csv")
  write.csv(results, out_csv, row.names = FALSE)

  # Curves PDF (dated so successive runs don't overwrite)
  run_date <- format(Sys.Date(), "%Y%m%d")
  pdf_path <- file.path("figures",
                        paste0("B2_SoilInfiltration_curves_", run_date, ".pdf"))
  .write_curves_pdf(master, results, pdf_path, RADIUS_CM)

  n_ok  <- sum(results$qc_flag == "OK",                       na.rm = TRUE)
  n_rev <- sum(grepl("^REVIEW",  results$qc_flag),            na.rm = TRUE)
  n_unk <- sum(grepl("^UNKNOWN", results$qc_flag),            na.rm = TRUE)
  message(sprintf(
    "calculate_infiltration complete: %d replicates (%d OK, %d REVIEW, %d UNKNOWN)",
    nrow(results), n_ok, n_rev, n_unk))
  message("  -> ", out_csv)
  message("  -> ", pdf_path)

  invisible(results)
}

if (sys.nframe() == 0L) run_calculate_infiltration()
