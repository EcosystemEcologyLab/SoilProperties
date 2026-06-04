# =============================================================================
# 02_calculate_infiltration.R — fit infiltration curves and compute K
# -----------------------------------------------------------------------------
# Usage:  Rscript R/02_calculate_infiltration.R <path/to/{site}_{date}_infiltration_clean.csv>
#
# For each (site, date, plot, point_id) replicate:
#   I_t = (V0 - V_t)/(pi r^2);  fit I = C1*sqrt(t) + C2*t (no intercept);
#   look up van Genuchten alpha,n; A = Zhang(1997); K = C1/A (cm/s).
#
# Every replicate gets one output row — failed fits carry NA for K with a QC
# flag explaining why (per the principles: never silently drop a fit).
#
# Per the scientist's decision (2026-06-02) results are SPLIT PER SOIL TYPE:
# one results CSV, one curves PDF, and their .meta.json companions per soil type.
# =============================================================================

source("R/pipeline_config.R")
source("R/infiltration_math.R")
source("R/write_meta.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(ggplot2)
})

THIS_SCRIPT <- "02_calculate_infiltration.R"

#' Compute results for one replicate's rows.
#' @param d data.frame for a single (site,date,plot,point_id) replicate.
#' @param vg van Genuchten parameter table.
#' @param radius_cm active disk radius.
#' @return one-row data.frame of results.
.calc_replicate <- function(d, vg, radius_cm) {
  d <- d[order(d$time_s), ]
  suction <- d$suction_cm[1]
  h0 <- -suction                          # suction entered positive; head is negative
  V0 <- d$volume_ml[d$time_s == 0][1]     # anchor reservoir volume at t = 0

  I <- cumulative_infiltration(V0, d$volume_ml, radius_cm)
  fit <- fit_infiltration(d$time_s, I)

  vrow <- vg[vg$soil_type == d$soil_type[1], ]
  alpha <- vrow$alpha[1]; n_vg <- vrow$n[1]
  A <- A_coefficient(alpha, n_vg, radius_cm, h0)

  C1 <- fit$C1; r2 <- fit$r2; n_points <- fit$n_points
  K <- if (!is.na(C1)) C1 / A else NA_real_

  # ---- QC flag (precedence: insufficient -> negative C1 -> low r2 -> OK) ----
  if (is.na(C1) || n_points < MIN_FIT_POINTS) {
    qc <- "UNKNOWN_insufficient_points"; K <- NA_real_
  } else if (C1 <= 0) {
    qc <- "REVIEW_negative_C1"; K <- NA_real_   # K meaningless
  } else if (is.na(r2) || r2 < MIN_FIT_R2) {
    qc <- "REVIEW_low_r2"
  } else {
    qc <- "OK"
  }
  K_hr <- if (is.na(K)) NA_real_ else K * 3600

  data.frame(
    site = d$site[1], date = d$date[1], plot = d$plot[1], point_id = d$point_id[1],
    soil_type = d$soil_type[1], suction_cm = suction,
    infiltrometer_type = INFILTROMETER_TYPE, radius_cm = radius_cm,
    n_points = n_points, C1 = C1, C2 = fit$C2, r2 = r2,
    alpha = alpha, n_vg = n_vg, A = A,
    K_cm_per_s = K, K_cm_per_hr = K_hr, qc_flag = qc,
    stringsAsFactors = FALSE
  )
}

#' Build the curves PDF (one panel per replicate) for a set of results.
.write_curves_pdf <- function(clean, results, pdf_path) {
  # observed infiltration per row
  radius_cm <- results$radius_cm[1]
  obs <- clean %>%
    group_by(site, date, plot, point_id) %>%
    mutate(V0 = volume_ml[time_s == 0][1],
           I_cm = cumulative_infiltration(V0, volume_ml, radius_cm)) %>%
    ungroup() %>%
    mutate(rep = paste0("Plot ", plot, " / ", point_id))

  # fitted curve per replicate (only where C1/C2 available)
  fitted <- results %>%
    filter(!is.na(C1) & !is.na(C2)) %>%
    rowwise() %>%
    mutate(rep = paste0("Plot ", plot, " / ", point_id)) %>%
    ungroup()

  fit_lines <- do.call(rbind, lapply(seq_len(nrow(fitted)), function(i) {
    rr <- fitted[i, ]
    tmax <- max(obs$time_s[obs$rep == rr$rep], na.rm = TRUE)
    tg <- seq(0, tmax, length.out = 100)
    data.frame(rep = rr$rep, time_s = tg,
               I_cm = rr$C1 * sqrt(tg) + rr$C2 * tg, stringsAsFactors = FALSE)
  }))

  strip <- results %>%
    mutate(rep = paste0("Plot ", plot, " / ", point_id),
           lab = sprintf("%s\nK=%s cm/s  r2=%s  [%s]",
                         rep,
                         ifelse(is.na(K_cm_per_s), "NA", formatC(K_cm_per_s, format = "e", digits = 2)),
                         ifelse(is.na(r2), "NA", formatC(r2, digits = 3, format = "f")),
                         qc_flag))
  lab_map <- setNames(strip$lab, strip$rep)
  obs$panel <- lab_map[obs$rep]
  if (!is.null(fit_lines)) fit_lines$panel <- lab_map[fit_lines$rep]

  p <- ggplot(obs, aes(time_s, I_cm)) +
    geom_point(size = 1.3) +
    facet_wrap(~ panel, scales = "free") +
    labs(x = "Time (s)", y = "Cumulative infiltration (cm)",
         title = sprintf("%s  %s  —  %s",
                         results$site[1], results$date[1], results$soil_type[1])) +
    theme_bw(base_size = 8)
  if (!is.null(fit_lines) && nrow(fit_lines) > 0) {
    p <- p + geom_line(data = fit_lines, aes(time_s, I_cm), colour = "firebrick")
  }

  dir.create(dirname(pdf_path), showWarnings = FALSE, recursive = TRUE)
  n_pan <- length(unique(obs$panel))
  ncol <- min(3, max(1, n_pan))
  nrow_p <- ceiling(n_pan / ncol)
  ggsave(pdf_path, p, width = 3.2 * ncol, height = 2.8 * nrow_p, limitsize = FALSE)
}

#' Main driver.
#' @param clean_csv Path to a cleaned CSV from script 01.
run_calculate_infiltration <- function(clean_csv) {
  check_pipeline_config()
  ensure_logs_exist()
  write_session_info()

  if (!file.exists(clean_csv)) stop("Cleaned CSV not found: ", clean_csv)
  clean <- read.csv(clean_csv, stringsAsFactors = FALSE, colClasses = c(date = "character"))
  if (nrow(clean) == 0) stop("Cleaned CSV has no rows: ", clean_csv)

  vg <- load_vg_parameters()
  vg$soil_type <- tolower(trimws(vg$soil_type))
  radius_cm <- RADIUS_CM

  results <- clean %>%
    group_by(site, date, plot, point_id) %>%
    group_split() %>%
    map_dfr(~ .calc_replicate(.x, vg, radius_cm))

  # ---- logs: negative C1 -> exclusion; insufficient points -> unknown ----
  neg <- results %>% filter(qc_flag == "REVIEW_negative_C1")
  if (nrow(neg) > 0) {
    log_exclusions(data.frame(
      site_id = neg$site, variable = "K_cm_per_s",
      timestamp = "ALL", reason = "negative_C1",
      threshold = "C1>0", excluded_by = THIS_SCRIPT, stringsAsFactors = FALSE))
  }
  uns <- results %>% filter(qc_flag == "UNKNOWN_insufficient_points")
  if (nrow(uns) > 0) {
    log_unknowns(data.frame(
      record_id = paste(uns$site, uns$date, uns$plot, uns$point_id, sep = "_"),
      reason = sprintf("insufficient_fit_points (n<%d)", MIN_FIT_POINTS),
      logged_by = THIS_SCRIPT, stringsAsFactors = FALSE))
  }

  # ---- write one results CSV + curves PDF per soil type (split decision) ----
  dir.create(PATH_PROCESSED, showWarnings = FALSE, recursive = TRUE)
  out_paths <- character(0)
  for (st in sort(unique(results$soil_type))) {
    res_st   <- results %>% filter(soil_type == st)
    clean_st <- clean   %>% filter(soil_type == st)
    site_s <- .slug(res_st$site[1]); date_s <- .slug(res_st$date[1]); st_s <- .slug(st)

    csv_path <- file.path(PATH_PROCESSED,
      sprintf("%s_%s_%s_infiltration_results.csv", site_s, date_s, st_s))
    write.csv(res_st, csv_path, row.names = FALSE, na = "")
    write_meta(csv_path, input_sources = c(clean_csv, PATH_VG_PARAMS, PATH_RADII),
               notes = sprintf("soil_type=%s; split-per-soil-type output; MIN_FIT_R2=%.2f; MIN_FIT_POINTS=%d",
                               st, MIN_FIT_R2, MIN_FIT_POINTS))

    pdf_path <- file.path(PATH_FIGURES,
      sprintf("%s_%s_%s_curves.pdf", site_s, date_s, st_s))
    .write_curves_pdf(clean_st, res_st, pdf_path)
    write_meta(pdf_path, input_sources = c(clean_csv, PATH_VG_PARAMS, PATH_RADII),
               notes = sprintf("soil_type=%s; one panel per replicate", st))

    out_paths <- c(out_paths, csv_path)
  }

  n_ok <- sum(results$qc_flag == "OK")
  n_rev <- sum(grepl("^REVIEW", results$qc_flag))
  n_unk <- sum(grepl("^UNKNOWN", results$qc_flag))
  message(sprintf(
    "Script 02 complete: %d replicates (%d OK, %d review, %d unknown) across %d soil type file(s)",
    nrow(results), n_ok, n_rev, n_unk, length(out_paths)))
  for (p in out_paths) message("  -> ", p)

  invisible(out_paths)
}

if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) < 1) {
    stop("Usage: Rscript R/02_calculate_infiltration.R <cleaned_csv>")
  }
  run_calculate_infiltration(args[1])
}
