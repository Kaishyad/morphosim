#how all 12 models rank against EACH OTHER within a scenario, or
#how a given model performs on nt-generated vs mk-generated data 
#whether model complexity helps when it should (nt-generated)
#without hurting when it shouldn't (mk-generated), 

#' All-models-against-each-other comparison, within one scenario
#'
#' Runs a Friedman test (non-parametric repeated-measures ANOVA analogue,
#' appropriate since the same grid cells are shared across models) to test
#' whether CID differs across the 12 models at all, then pairwise Wilcoxon
#' signed-rank tests between every model pair with Holm correction for
#' multiple comparisons. Models are also ranked by median CID (lower =
#' more accurate).
#'
#' @param cid_data  Data frame from run/tree_accuracy.R.
#' @param scenario  "mk" or "nt".
#' @param models    Models to include (default: all MODEL_IDS present).
#' @return List with: `friedman` (htest), `pairwise` (data frame of
#'   pairwise p-values), `ranking` (data frame of median CID per model,
#'   sorted best to worst).
#' @export
AllModelsComparison <- function(cid_data, scenario, models = NULL) {
  sub <- cid_data[cid_data$scenario == scenario, ]
  if (is.null(models)) models <- sort(unique(sub$modelID))
  sub <- sub[sub$modelID %in% models, ]

  
  wide <- reshape(
    sub[, c("gridTag", "repID", "modelID", "median_cid")],
    idvar     = c("gridTag", "repID"),
    timevar   = "modelID",
    direction = "wide"
  )
  names(wide) <- sub("^median_cid\\.", "", names(wide))
  complete <- wide[stats::complete.cases(wide[, models]), ]

  n_dropped <- nrow(wide) - nrow(complete)
  if (n_dropped > 0L) {
    warning(sprintf(
      "%d/%d grid-cell replicates dropped from %s comparison (missing data for >=1 model -- likely model7/model9 gaps)",
      n_dropped, nrow(wide), scenario
    ))
  }
  if (nrow(complete) < 3L) {
    stop("Fewer than 3 complete blocks available for ", scenario,
         " -- cannot run Friedman test. Fill in missing model runs first.")
  }

  mat <- as.matrix(complete[, models])

  friedman <- stats::friedman.test(mat)

  # Pairwise Wilcoxon (paired, since same grid cell/replicate under each
  # model), Holm-corrected across all pairs.
  pairwise <- stats::pairwise.wilcox.test(
    x = as.vector(mat),
    g = factor(rep(models, each = nrow(mat)), levels = models),
    paired = TRUE,
    p.adjust.method = "holm"
  )

  ranking <- data.frame(
    modelID    = models,
    median_cid = vapply(models, function(m) stats::median(complete[[m]], na.rm = TRUE), numeric(1)),
    iqr_cid    = vapply(models, function(m) stats::IQR(complete[[m]], na.rm = TRUE), numeric(1)),
    n          = nrow(complete),
    stringsAsFactors = FALSE
  )
  ranking <- ranking[order(ranking$median_cid), ]
  ranking$rank <- seq_len(nrow(ranking))

  list(friedman = friedman, pairwise = pairwise, ranking = ranking,
       n_dropped = n_dropped, n_complete = nrow(complete))
}

#' A single model vs itself: nt-generated data vs mk-generated data
#'
#' Answers whether model complexity helps when it should (data generated
#' under NT) without hurting when it shouldn't (data generated under
#' symmetric Mk),, which up to now has only been implicit in separate
#' per-scenario tables rather than tested directly against each other.
#'
#' Matching is done on the axes shared by both scenario grids
#' (tree_length, gain_loss, n_char, n_taxa); nt's extra part_rate axis is
#' pooled over (median across part_rate levels per matched cell) since mk
#' has no such axis to match against.
#'
#' @param cid_data  Data frame from run/tree_accuracy.R.
#' @param modelID   Model to test.
#' @return List with: `wilcox` (paired Wilcoxon signed-rank htest),
#'   `summary` (median CID under each scenario + the paired difference).
#' @export
ScenarioContrast <- function(cid_data, modelID) {
  sub <- cid_data[cid_data$modelID == modelID, ]

  match_cols <- c("tree_length", "gain_loss", "n_char", "n_taxa")

  nt_grid <- ScenarioGrid("nt"); nt_grid$gridTag <- apply(nt_grid, 1, function(r) GridTag(as.list(r)))
  mk_grid <- ScenarioGrid("mk"); mk_grid$gridTag <- apply(mk_grid, 1, function(r) GridTag(as.list(r)))

  nt_cid <- merge(sub[sub$scenario == "nt", ], nt_grid[, c("gridTag", match_cols)], by = "gridTag")
  mk_cid <- merge(sub[sub$scenario == "mk", ], mk_grid[, c("gridTag", match_cols)], by = "gridTag")

  # Pool nt across part_rate per matched cell (median), then match on the
  # shared axes only.
  nt_pooled <- stats::aggregate(median_cid ~ tree_length + gain_loss + n_char + n_taxa,
                                data = nt_cid, FUN = stats::median)

  matched <- merge(nt_pooled, mk_cid[, c(match_cols, "median_cid")],
                   by = match_cols, suffixes = c("_nt", "_mk"))

  if (nrow(matched) < 3L) {
    stop("Fewer than 3 matched grid cells between nt and mk for ", modelID,
         " -- check that both scenarios have converged runs for this model.")
  }

  wilcox <- stats::wilcox.test(matched$median_cid_nt, matched$median_cid_mk, paired = TRUE)

  summary_df <- data.frame(
    modelID          = modelID,
    n_matched_cells  = nrow(matched),
    median_cid_nt    = stats::median(matched$median_cid_nt),
    median_cid_mk    = stats::median(matched$median_cid_mk),
    median_diff      = stats::median(matched$median_cid_nt - matched$median_cid_mk),
    p_value          = wilcox$p.value,
    stringsAsFactors = FALSE
  )

  list(wilcox = wilcox, summary = summary_df, matched = matched)
}
