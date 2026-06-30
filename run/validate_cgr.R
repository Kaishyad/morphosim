# Standalone Cook-Gelman-Rubin (CGR) coverage validation script.
# Loops over all converged replicates, extracts 95% posterior credible
# intervals for the two focal parameters (tree_length and gain-to-loss ratio),
# and checks whether each interval contains the known true simulated value.

source("R/core/_setup.R")

# --- Configuration -----------------------------------------------------------

args_cli      <- commandArgs(trailingOnly = TRUE)
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
model_flag    <- args_cli[which(args_cli == "--model")    + 1]

# FIX: accept --scenario and --model flags instead of hardcoding
SCENARIO    <- if (!is.na(scenario_flag[1])) scenario_flag else "nt"
EVAL_MODELS <- if (!is.na(model_flag[1]))    model_flag    else MODEL_IDS
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
cli::cli_alert_info("{nrow(converged)} converged {SCENARIO} runs available for CGR validation.")

# FIX: use scenario-specific grid
grid <- ScenarioGrid(SCENARIO)

# --- Load existing CGR results to append (not overwrite) ---------------------

existing_cgr <- if (file.exists(cgr_rds)) readRDS(cgr_rds) else NULL

.AlreadyDone <- function(mid, gt, param) {
  if (is.null(existing_cgr)) return(FALSE)
  any(existing_cgr$modelID   == mid   &
      existing_cgr$gridTag   == gt    &
      existing_cgr$parameter == param &
      existing_cgr$scenario  == SCENARIO)
}

# --- Per-replicate coverage check --------------------------------------------

cli::cli_h1("CGR coverage validation — scenario: {SCENARIO}")

all_rows <- vector("list", 0L)

for (mid in EVAL_MODELS) {
  cli::cli_h2("Model: {mid}")
  conv_model <- converged[converged$modelID == mid, ]

  if (nrow(conv_model) == 0L) {
    cli::cli_alert_warning("No converged runs for {mid}; skipping.")
    next
  }

  for (gi in seq_len(nrow(grid))) {
    row     <- grid[gi, ]
    gridTag <- GridTag(row)

    true_vals <- list(
      tree_length = row$tree_length,
      rate_loss   = 1 / row$gain_loss
    )

    conv_cell <- conv_model[conv_model$gridTag == gridTag, ]
    n_cell    <- nrow(conv_cell)

    for (param in PARAMETERS) {
      if (.AlreadyDone(mid, gridTag, param)) next

      covers <- vapply(seq_len(n_cell), function(ri) {
        repID <- conv_cell$repID[ri]
        ci    <- tryCatch(
          CredibleInterval(SCENARIO, gridTag, repID, mid, param),
          error = function(e) {
            warning("CredibleInterval failed for ",
                    paste(mid, gridTag, repID, param, sep = "/"),
                    ": ", conditionMessage(e))
            NULL
          }
        )
        CoversTrue(ci, true_vals[[param]])
      }, logical(1))

      coverage_rate <- mean(covers, na.rm = TRUE)
      n_valid       <- sum(!is.na(covers))

      all_rows[[length(all_rows) + 1L]] <- data.frame(
        scenario      = SCENARIO,
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
      cli::cli_alert_info("  {mid}: {gi}/{nrow(grid)} grid cells done...")
    }
  }
}

# --- Combine with existing and save ------------------------------------------

new_cgr <- if (length(all_rows) > 0L) do.call(rbind, all_rows) else NULL
cgr_df  <- if (!is.null(existing_cgr) && !is.null(new_cgr)) {
  rbind(existing_cgr, new_cgr)
} else if (!is.null(existing_cgr)) {
  existing_cgr
} else {
  new_cgr
}

if (is.null(cgr_df) || nrow(cgr_df) == 0L) {
  stop("No CGR coverage results produced.")
}

saveRDS(cgr_df, cgr_rds)
utils::write.csv(cgr_df, cgr_csv, row.names = FALSE)

cli::cli_alert_success("CGR coverage results saved to:")
cli::cli_alert_success("  RDS : {cgr_rds}")
cli::cli_alert_success("  CSV : {cgr_csv}")

# --- Console report ----------------------------------------------------------

cli::cli_h2("CGR coverage rates (target: 0.95 ± 0.05)")

target <- 0.95
tol    <- 0.05

for (mid in EVAL_MODELS) {
  sub <- cgr_df[cgr_df$modelID == mid & cgr_df$scenario == SCENARIO, ]
  if (nrow(sub) == 0L) next

  cli::cli_h3(mid)
  for (param in PARAMETERS) {
    p_sub    <- sub[sub$parameter == param, ]
    mean_cov <- round(mean(p_sub$coverage_rate, na.rm = TRUE), 3)
    n_low    <- sum(!is.na(p_sub$coverage_rate) &
                      p_sub$coverage_rate < target - tol)
    n_high   <- sum(!is.na(p_sub$coverage_rate) &
                      p_sub$coverage_rate > target + tol)

    cli::cli_alert_info(
      "{param}: mean coverage = {mean_cov} ",
      "({n_low} cells below {target - tol}, {n_high} cells above {target + tol})"
    )
  }
}

severe <- cgr_df[!is.na(cgr_df$coverage_rate) &
                   (cgr_df$coverage_rate < 0.80 | cgr_df$coverage_rate > 0.99), ]
if (nrow(severe) > 0L) {
  cli::cli_alert_warning(
    "{nrow(severe)} grid cell(s) with severe coverage issues (< 0.80 or > 0.99)"
  )
  print(severe[, c("scenario", "modelID", "gridTag", "parameter", "coverage_rate")])
}
