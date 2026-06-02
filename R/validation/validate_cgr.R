# Standalone Cook-Gelman-Rubin (CGR) coverage validation script.
# Loops over all converged replicates, extracts 95% posterior credible
# intervals for the two focal parameters (tree_length and gain-to-loss ratio),
# and checks whether each interval contains the known true simulated value.

#TO DO:
# -Load all converged .log files identified by analysis/check_convergence.R.
# -For each replicate: extract CI via KnownAnswer.R::CredibleInterval().
# -Compute coverage rate per grid cell via KnownAnswer.R::CoverageRate().
#   -Summarise across the full grid and export results for dissertation Section 6.1.



source("R/core/_setup.R")

# --- Configuration -----------------------------------------------------------

# Models for CGR validation (NT generative scenario; model4 = sp_nt_kv,
# model8 = full NT+RH, as specified in the dissertation plan).
EVAL_MODELS <- c("model4", "model8")
SCENARIO    <- "nt"
PARAMETERS  <- c("tree_length", "rate_loss")

# Output paths
cgr_rds <- file.path(OutputDir(), "results", "cgr_coverage.rds")
cgr_csv <- file.path(OutputDir(), "results", "cgr_coverage.csv")

dir.create(dirname(cgr_rds), showWarnings = FALSE, recursive = TRUE)

# --- Load convergence filter -------------------------------------------------

conv_rds <- file.path(OutputDir(), "results", "convergence_summary.rds")
if (!file.exists(conv_rds)) {
  stop("Convergence summary not found: ", conv_rds,
       "\nRun analysis/check_convergence.R first.")
}

conv_df   <- readRDS(conv_rds)
converged <- conv_df[conv_df$pass & conv_df$scenario == SCENARIO, ]
cli::cli_alert_info("{nrow(converged)} converged NT runs available for CGR validation.")

# --- Per-replicate coverage check --------------------------------------------

cli::cli_h1("CGR coverage validation")

all_rows <- vector("list", 0L)

for (mid in EVAL_MODELS) {
  cli::cli_h2("Model: {mid}")
  conv_model <- converged[converged$modelID == mid, ]

  if (nrow(conv_model) == 0L) {
    cli::cli_alert_warning("No converged runs for {mid}; skipping.")
    next
  }

  for (gi in seq_len(nrow(PARAM_GRID))) {
    row     <- PARAM_GRID[gi, ]
    gridTag <- GridTag(row)

    # True values for this grid cell
    true_vals <- list(
      tree_length = row$tree_length,
      rate_loss   = 1 / row$gain_loss   # rate_loss = 1 / gain_loss
    )

    conv_cell <- conv_model[conv_model$gridTag == gridTag, ]
    n_cell    <- nrow(conv_cell)

    for (param in PARAMETERS) {
      # Per-replicate CI coverage
      covers <- vapply(seq_len(n_cell), function(ri) {
        repID <- conv_cell$repID[ri]
        ci    <- tryCatch(
          CredibleInterval(SCENARIO, gridTag, repID, mid, param),
          error = function(e) {
            warning("CredibleInterval failed for ",
                    paste(mid, gridTag, repID, param, sep="/"),
                    ": ", conditionMessage(e))
            NULL
          }
        )
        CoversTrue(ci, true_vals[[param]])
      }, logical(1))

      coverage_rate <- mean(covers, na.rm = TRUE)
      n_valid       <- sum(!is.na(covers))

      all_rows[[length(all_rows) + 1L]] <- data.frame(
        modelID       = mid,
        gridTag       = gridTag,
        parameter     = param,
        true_value    = true_vals[[param]],
        coverage_rate = coverage_rate,
        n_covers      = sum(covers %in% TRUE),
        n_total       = n_valid,
        tree_length   = row$tree_length,
        gain_loss     = row$gain_loss,
        n_char        = row$n_char,
        stringsAsFactors = FALSE
      )
    }

    if (gi %% 16L == 0L) {
      cli::cli_alert_info("  {mid}: {gi}/{nrow(PARAM_GRID)} grid cells done...")
    }
  }
}

cgr_df <- do.call(rbind, all_rows)

# --- Save results ------------------------------------------------------------

if (is.null(cgr_df) || nrow(cgr_df) == 0L) {
  stop("No CGR coverage results produced.")
}

saveRDS(cgr_df, cgr_rds)
utils::write.csv(cgr_df, cgr_csv, row.names = FALSE)

cli::cli_alert_success("CGR coverage results saved to:")
cli::cli_alert_success("  RDS : {cgr_rds}")
cli::cli_alert_success("  CSV : {cgr_csv}")

# --- Console report (Table 6.1 preview) --------------------------------------

cli::cli_h2("CGR coverage rates (target: 0.95 ± 0.05)")

target <- 0.95
tol    <- 0.05

for (mid in EVAL_MODELS) {
  sub <- cgr_df[cgr_df$modelID == mid, ]
  if (nrow(sub) == 0L) next

  cli::cli_h3(mid)
  for (param in PARAMETERS) {
    p_sub     <- sub[sub$parameter == param, ]
    mean_cov  <- round(mean(p_sub$coverage_rate, na.rm = TRUE), 3)
    n_low     <- sum(!is.na(p_sub$coverage_rate) &
                       p_sub$coverage_rate < target - tol)
    n_high    <- sum(!is.na(p_sub$coverage_rate) &
                       p_sub$coverage_rate > target + tol)

    cli::cli_alert_info(
      "{param}: mean coverage = {mean_cov} ",
      "({n_low} cells below {target - tol}, {n_high} cells above {target + tol})"
    )
  }
}

# Flag severe coverage failures (< 0.80 or > 0.99)
severe <- cgr_df[!is.na(cgr_df$coverage_rate) &
                   (cgr_df$coverage_rate < 0.80 | cgr_df$coverage_rate > 0.99), ]
if (nrow(severe) > 0L) {
  cli::cli_alert_warning(
    "{nrow(severe)} grid cell(s) with severe coverage issues (< 0.80 or > 0.99)"
  )
  print(severe[, c("modelID", "gridTag", "parameter", "coverage_rate")])
}
