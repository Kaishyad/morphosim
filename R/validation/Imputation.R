# R/Imputation.R
# Missing-data imputation accuracy
# Reads ancestral state posteriors from imp-mc3.Rev output (.states files),
# compares them to the known true character states, and computes accuracy
# metrics for each model × replicate × grid cell combination.
#
# Workflow per replicate:
#   1. MaskReplicate()    (in simFuncsImp.R) — mask neo.nex / trans.nex
#   2. imp-mc3.Rev        (on Hamilton)      — run inference on masked matrices
#   3. ScoreImputation()  (here)             — compare posteriors to true states
#   4. WilcoxonImputation() (here)           — pairwise test vs Mk baseline
#
# Depends on: R/_setup.R, R/FilePaths.R, R/simFuncsImp.R
# Used in: analysis/imputation.R


#' Read true character states from an unmasked nexus file
#'
#' @param nexPath Path to the original (unmasked) nexus file.
#' @return Character matrix with taxa as rows and characters as columns.
#' @export
ReadTrueStates <- function(nexPath) {
  if (!file.exists(nexPath)) stop("Nexus file not found: ", nexPath)
  do.call(rbind, read.nexus.data(nexPath))
}

#' Read masked positions from imp_ nexus file
#'
#' Returns a logical matrix: TRUE where character was masked ("?").
#'
#' @param impNexPath Path to the masked nexus file (imp_neo.nex or imp_trans.nex).
#' @return Logical matrix, same dimensions as the character matrix.
#' @export
MaskedPositions <- function(impNexPath) {
  if (!file.exists(impNexPath)) stop("Masked nexus not found: ", impNexPath)
  mat <- do.call(rbind, read.nexus.data(impNexPath))
  mat == "?"
}

#' Parse RevBayes ancestral state file for a single partition
#'
#' RevBayes mnJointConditionalAncestralState writes one row per tree sample,
#' with tip and node states. This function extracts the posterior mode state
#' at each tip across all samples (majority-rule reconstruction).
#'
#' @param statesFile  Path to the .states file from imp-mc3.Rev.
#' @param nTip        Number of tips in the tree.
#' @param burnFrac    Fraction of samples to discard as burnin (default 0.1).
#' @return Character matrix: taxa × characters, giving the MAP state at each
#'   masked position.
#' @export
ParseStatesFile <- function(statesFile, nTip, burnFrac = 0.1) {
  if (!file.exists(statesFile)) {
    warning("States file not found: ", statesFile)
    return(NULL)
  }
  
  raw   <- read.table(statesFile, header = TRUE, comment.char = "#",
                      stringsAsFactors = FALSE)
  n     <- nrow(raw)
  raw   <- raw[seq(floor(n * burnFrac) + 1L, n), ]
  
  # Tip columns: named "tip_01_state", "tip_02_state", etc.
  tipCols <- grep("^tip_", colnames(raw), value = TRUE)
  tipCols <- tipCols[grep("_state$", tipCols)]
  
  if (length(tipCols) == 0) {
    warning("No tip state columns found in ", statesFile)
    return(NULL)
  }
  
  # Majority-rule: most frequent state across posterior samples per tip
  apply(raw[, tipCols, drop = FALSE], 2, function(col) {
    tab <- table(col)
    names(tab)[which.max(tab)]
  })
}

#' Score imputation accuracy for one replicate and one partition
#'
#' Compares MAP reconstructed states at masked positions to the known true
#' states from the original (unmasked) nexus file.
#'
#' @param scenario  "nt" or "mk"
#' @param gridTag   Grid tag
#' @param repID     Replicate ID
#' @param modelID   Model script name
#' @param partition "neo" or "trans"
#' @param nRuns     Number of MCMC runs (default 2)
#' @return Scalar accuracy: proportion of masked positions correctly recovered,
#'   or NA if required files are missing.
#' @export
ScoreImputation <- function(scenario, gridTag, repID, modelID,
                            partition = c("neo", "trans"),
                            nRuns     = 2) {
  partition <- match.arg(partition)
  simDir    <- SimDirAbs(scenario, gridTag, repID)
  
  trueFile  <- file.path(simDir, paste0(partition, ".nex"))
  impFile   <- file.path(simDir, paste0("imp_", partition, ".nex"))
  
  trueStates <- ReadTrueStates(trueFile)
  masked     <- MaskedPositions(impFile)
  
  if (!any(masked)) {
    warning("No masked positions found in ", impFile)
    return(NA_real_)
  }
  
  # Pool reconstructed states across runs
  allRecov <- lapply(seq_len(nRuns), function(run) {
    statesFile <- file.path(simDir,
                            paste0("imp_", modelID, "_run_", run, ".states"))
    ParseStatesFile(statesFile, nTip = nrow(trueStates))
  })
  allRecov <- allRecov[!vapply(allRecov, is.null, logical(1))]
  
  if (length(allRecov) == 0) return(NA_real_)
  
  # Use majority-rule across runs for each tip
  # allRecov is a list of named vectors (one per tip); pool and take mode
  tipNames <- names(allRecov[[1]])
  recov <- vapply(tipNames, function(tip) {
    states <- unlist(lapply(allRecov, `[[`, tip))
    tab    <- table(states)
    names(tab)[which.max(tab)]
  }, character(1))
  
  # Compare to true states at masked positions only
  # trueStates is a matrix: rows = taxa, cols = characters
  # recov is a named vector indexed by tip_XX_state column names
  # masked is a logical matrix matching trueStates dimensions
  correct <- 0L
  total   <- 0L
  
  for (tipCol in tipNames) {
    # tip column name format: "tip_01_state" -> taxon "tip_01"
    taxon <- sub("_state$", "", tipCol)
    if (!taxon %in% rownames(trueStates)) next
    
    # Find which characters are masked for this taxon
    maskedChars <- which(masked[taxon, ])
    if (length(maskedChars) == 0) next
    
    # Compare reconstructed state to true state
    # RevBayes encodes states as integers starting from 0
    trueChar <- trueStates[taxon, maskedChars]
    recovState <- recov[[tipCol]]
    
    correct <- correct + sum(trueChar == recovState, na.rm = TRUE)
    total   <- total   + length(maskedChars)
  }
  
  if (total == 0) return(NA_real_)
  correct / total
}

#' Imputation accuracy summary across all replicates for one model × grid cell
#'
#' @param scenario "nt" or "mk"
#' @param gridTag  Grid tag
#' @param modelID  Model script name
#' @param nRep     Replicates per cell (default N_REP)
#' @return Data frame with median and IQR of accuracy across replicates,
#'   for neo and trans partitions separately and combined.
#' @export
ImputationSummary <- function(scenario, gridTag, modelID, nRep = N_REP) {
  acc <- lapply(seq_len(nRep), function(rep) {
    repID <- SimID(rep)
    list(
      neo   = ScoreImputation(scenario, gridTag, repID, modelID, "neo"),
      trans = ScoreImputation(scenario, gridTag, repID, modelID, "trans")
    )
  })
  
  neoAcc   <- vapply(acc, `[[`, numeric(1), "neo")
  transAcc <- vapply(acc, `[[`, numeric(1), "trans")
  allAcc   <- (neoAcc + transAcc) / 2
  
  data.frame(
    scenario        = scenario,
    gridTag         = gridTag,
    modelID         = modelID,
    median_acc      = median(allAcc,   na.rm = TRUE),
    iqr_acc         = IQR(allAcc,      na.rm = TRUE),
    median_acc_neo  = median(neoAcc,   na.rm = TRUE),
    median_acc_trans= median(transAcc, na.rm = TRUE),
    n_reps          = sum(!is.na(allAcc)),
    stringsAsFactors = FALSE
  )
}

#' Pairwise Wilcoxon signed-rank test: model vs Mk baseline (Model 1)
#'
#' Compares imputation accuracy distributions between a given model and
#' the Mk baseline across replicates within one grid cell.
#' Uses paired test since both models run on the same replicates.
#'
#' @param scenario   "nt" or "mk"
#' @param gridTag    Grid tag
#' @param modelID    Model to compare against baseline
#' @param baselineID Baseline model ID (default "model1")
#' @param nRep       Replicates per cell
#' @return Named list: statistic, p.value, direction ("better"/"worse"/"same")
#' @importFrom stats wilcox.test
#' @export
WilcoxonImputation <- function(scenario, gridTag,
                               modelID,
                               baselineID = "model1",
                               nRep       = N_REP) {
  .Acc <- function(mid) {
    vapply(seq_len(nRep), function(rep) {
      repID    <- SimID(rep)
      neo      <- ScoreImputation(scenario, gridTag, repID, mid, "neo")
      trans    <- ScoreImputation(scenario, gridTag, repID, mid, "trans")
      mean(c(neo, trans), na.rm = TRUE)
    }, numeric(1))
  }
  
  accModel    <- .Acc(modelID)
  accBaseline <- .Acc(baselineID)
  
  keep <- !is.na(accModel) & !is.na(accBaseline)
  if (sum(keep) < 5) {
    return(list(statistic = NA, p.value = NA, direction = NA))
  }
  
  wt <- wilcox.test(accModel[keep], accBaseline[keep],
                    paired = TRUE, exact = FALSE)
  
  direction <- if (wt$p.value < 0.05) {
    if (median(accModel[keep]) > median(accBaseline[keep])) "better" else "worse"
  } else {
    "same"
  }
  
  list(statistic = wt$statistic, p.value = wt$p.value, direction = direction)
}