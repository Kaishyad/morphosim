## check_improvement_range.R
##
## Diagnostic for interpreting NA rows in threshold_summary_{scenario}.csv.
## For each (scenario, modelID), computes the range of `improvement`
## (= CID_Mk - CID_NT, per replicate) across the whole simulated grid, and
## labels each model as:
##   "always better"  - improvement > 0 everywhere (NT beats Mk in every
##                       simulated condition)
##   "always worse"    - improvement < 0 everywhere
##   "mixed / crosses" - improvement changes sign somewhere (this is the
##                       case where ExtractThreshold() should have found a
##                       real threshold; if the threshold table shows NA
##                       here, worth re-checking that model's GAM fit)
##
## Run from the morphosim project root:
##   Rscript run/check_improvement_range.R
## or interactively:
##   source("R/core/_setup.R"); source("run/check_improvement_range.R")

source("R/core/_setup.R")

cid_rep_rds <- file.path(OutputDir(), "results", "tree_accuracy_per_rep.rds")
if (!file.exists(cid_rep_rds)) {
  stop("Can't find ", cid_rep_rds, " - run tree_accuracy.R first.")
}
cid_data <- readRDS(cid_rep_rds)

scenarios <- c("mk", "nt")
all_models <- setdiff(unique(cid_data$modelID), "model1")  # exclude baseline itself

results <- do.call(rbind, lapply(scenarios, function(scn) {
  do.call(rbind, lapply(all_models, function(mid) {
    impr_df <- tryCatch(
      ComputeImprovement(cid_data, modelID = mid, baselineID = "model1", scenario = scn),
      error = function(e) NULL
    )

    if (is.null(impr_df) || nrow(impr_df) == 0L) {
      return(data.frame(
        scenario = scn, modelID = mid, n_reps = 0L,
        min_improvement = NA_real_, max_improvement = NA_real_,
        mean_improvement = NA_real_, pct_positive = NA_real_,
        label = "no data", stringsAsFactors = FALSE
      ))
    }

    imp <- impr_df$improvement
    imp <- imp[!is.na(imp)]

    if (length(imp) == 0L) {
      return(data.frame(
        scenario = scn, modelID = mid, n_reps = 0L,
        min_improvement = NA_real_, max_improvement = NA_real_,
        mean_improvement = NA_real_, pct_positive = NA_real_,
        label = "no data", stringsAsFactors = FALSE
      ))
    }

    lab <- if (all(imp > 0)) {
      "always better"
    } else if (all(imp < 0)) {
      "always worse"
    } else {
      "mixed / crosses"
    }

    data.frame(
      scenario         = scn,
      modelID          = mid,
      n_reps           = length(imp),
      min_improvement  = min(imp),
      max_improvement  = max(imp),
      mean_improvement = mean(imp),
      pct_positive     = round(100 * mean(imp > 0), 1),
      label            = lab,
      stringsAsFactors = FALSE
    )
  }))
}))

results <- results[order(results$scenario, results$modelID), ]
rownames(results) <- NULL

print(results, row.names = FALSE)

out_csv <- file.path(OutputDir(), "results", "improvement_range_summary.csv")
utils::write.csv(results, out_csv, row.names = FALSE)
cli::cli_alert_success("Saved: {out_csv}")
