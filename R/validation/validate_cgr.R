# Cook-Gelman-Rubin (CGR) / simulation-based calibration validation.
#
# For every (model x scenario x grid cell), checks whether each parameter's
# 95% posterior credible interval contains its known true simulated value at
# ~95% of replicates. This is the dissertation Section 6.1 "Correctness"
# proof: it answers "are estimated parameters showing correct frequentist
# coverage of their known true values" for every model x dataset combination,
# not just model4/model8 under nt.
#
# FIX vs previous version:
#   - PARAMETERS included "rate_loss", which is not a real logged column for
#     ANY model (see RateLossParams() in KnownAnswer.R) -- CredibleInterval()
#     silently returned NULL for every single call. Now uses the same
#     RateLossParams(modelID) lookup KnownAnswer.R uses, so model1 is
#     correctly skipped (fixed fnJC, nothing to test), model2/model3 test
#     gain_loss_ratio, and two-partition models test gain_loss_neo AND
#     gain_loss_trans as separate rows.
#   - EVAL_MODELS was hardcoded to c("model4","model8") under "nt" only.
#     Generalised to all MODEL_IDS across BOTH scenarios, since coverage can
#     fail differently under mk-generated vs nt-generated data and you want
#     that comparison, not just the nt case.

source("R/core/_setup.R")

# --- Configuration -------------------------------------------------------

EVAL_MODELS <- MODEL_IDS         # all 12, not just model4/model8
SCENARIOS   <- c("mk", "nt")     # both generative scenarios

cgr_rds <- file.path(OutputDir(), "results", "cgr_coverage.rds")
cgr_csv <- file.path(OutputDir(), "results", "cgr_coverage.csv")
dir.create(dirname(cgr_rds), showWarnings = FALSE, recursive = TRUE)

conv_rds <- file.path(OutputDir(), "results", "convergence_summary.rds")
if (!file.exists(conv_rds)) {
  stop("Convergence summary not found: ", conv_rds,
       "\nRun run/check_convergence.R first.")
}
conv_df <- readRDS(conv_rds)

# --- Per-model, per-scenario coverage check -------------------------------

cli::cli_h1("CGR / simulation-based calibration")

all_rows <- vector("list", 0L)

for (scen in SCENARIOS) {
  grid <- ScenarioGrid(scen)
  converged_scen <- conv_df[conv_df$pass & conv_df$scenario == scen, ]

  for (mid in EVAL_MODELS) {
    cli::cli_h2("{scen} / {mid}")
    conv_model <- converged_scen[converged_scen$modelID == mid, ]
    if (nrow(conv_model) == 0L) {
      cli::cli_alert_warning("No converged runs for {scen}/{mid}; skipping.")
      next
    }

    # tree_length always applies; rate parameter(s) depend on model structure
    rateCols <- RateLossParams(mid)
    params   <- c("tree_length", rateCols)

    for (gi in seq_len(nrow(grid))) {
      row     <- grid[gi, ]
      gridTag <- GridTag(row)

      true_vals <- list(tree_length = row$tree_length)
      for (col in rateCols) true_vals[[col]] <- 1 / row$gain_loss

      conv_cell <- conv_model[conv_model$gridTag == gridTag, ]
      n_cell    <- nrow(conv_cell)
      if (n_cell == 0L) next

      for (param in params) {
        covers <- vapply(seq_len(n_cell), function(ri) {
          repID <- conv_cell$repID[ri]
          ci <- tryCatch(
            CredibleInterval(scen, gridTag, repID, mid, param),
            error = function(e) NULL
          )
          CoversTrue(ci, true_vals[[param]])
        }, logical(1))

        all_rows[[length(all_rows) + 1L]] <- data.frame(
          scenario      = scen,
          modelID       = mid,
          gridTag       = gridTag,
          parameter     = param,
          true_value    = true_vals[[param]],
          coverage_rate = mean(covers, na.rm = TRUE),
          n_covers      = sum(covers %in% TRUE),
          n_total       = sum(!is.na(covers)),
          tree_length   = row$tree_length,
          gain_loss     = row$gain_loss,
          n_char        = row$n_char,
          stringsAsFactors = FALSE
        )
      }
    }
  }
}

cgr_df <- do.call(rbind, all_rows)
if (is.null(cgr_df) || nrow(cgr_df) == 0L) stop("No CGR coverage results produced.")

saveRDS(cgr_df, cgr_rds)
utils::write.csv(cgr_df, cgr_csv, row.names = FALSE)
cli::cli_alert_success("Saved: {cgr_rds}")
cli::cli_alert_success("Saved: {cgr_csv}")

# --- Console report (Table 6.1) -------------------------------------------

cli::cli_h2("Coverage rates by scenario x model (target: 0.95 +/- 0.05)")

target <- 0.95; tol <- 0.05
report <- do.call(rbind, lapply(split(cgr_df, list(cgr_df$scenario, cgr_df$modelID)), function(sub) {
  if (nrow(sub) == 0L) return(NULL)
  data.frame(
    scenario  = sub$scenario[1],
    modelID   = sub$modelID[1],
    mean_cov  = round(mean(sub$coverage_rate, na.rm = TRUE), 3),
    n_low     = sum(!is.na(sub$coverage_rate) & sub$coverage_rate < target - tol),
    n_high    = sum(!is.na(sub$coverage_rate) & sub$coverage_rate > target + tol),
    n_cells   = nrow(sub)
  )
}))
report <- report[order(report$scenario, report$modelID), ]
print(report, row.names = FALSE)

severe <- cgr_df[!is.na(cgr_df$coverage_rate) &
                   (cgr_df$coverage_rate < 0.80 | cgr_df$coverage_rate > 0.99), ]
if (nrow(severe) > 0L) {
  cli::cli_alert_warning("{nrow(severe)} grid cell(s) with severe coverage issues (<0.80 or >0.99)")
}
