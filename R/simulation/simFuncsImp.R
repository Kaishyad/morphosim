#imputation masking utilities.
#.AmbDist() profiles ambiguity in a nexus file; .DecodeTips() reorders tips to match RevBayes index conventions;
#.Invariant() identifies invariant characters in imputed matrices.
#
# MaskReplicate() produces the imp_neo.nex / imp_trans.nex files that
# imp-mc3.Rev reads. See run/imputation/mask_replicates.R for the driver.

#' Mask a proportion of observed character states to simulate missing data
#'
#' Reads the unmasked neo.nex / trans.nex nexus files for one replicate,
#' randomly replaces a proportion of OBSERVED (non-"?") cells with "?", and
#' writes imp_neo.nex / imp_trans.nex to the same simulation directory.
#' Masked positions don't need to be tracked separately -- they're recovered
#' later just by re-reading the imp_ file and checking which cells are "?"
#' (see MaskedPositions() in R/validation/Imputation.R).
#'
#' @param scenario  "nt" or "mk"
#' @param gridTag   Grid tag
#' @param repID     Replicate ID
#' @param propMask  Proportion of OBSERVED cells to mask, per partition (default 0.1)
#' @param seed      Optional seed for reproducible masking
#' @return Invisibly, a named list with the count of cells masked per partition
#' @export
MaskReplicate <- function(scenario, gridTag, repID, propMask = 0.1, seed = NULL) {
  if (!is.null(seed)) set.seed(seed)
  simDir <- SimDirAbs(scenario, gridTag, repID)

  .MaskOne <- function(partition) {
    trueFile <- file.path(simDir, paste0(partition, ".nex"))
    impFile  <- file.path(simDir, paste0("imp_", partition, ".nex"))

    if (!file.exists(trueFile)) {
      warning("No ", trueFile, " -- run the simulation for this replicate first")
      return(0L)
    }

    mat <- do.call(rbind, read.nexus.data(trueFile))

    observed <- which(mat != "?", arr.ind = TRUE)
    nMask <- round(propMask * nrow(observed))

    if (nMask == 0L) {
      warning("propMask too small to mask any cells in ", trueFile)
    } else {
      pick      <- observed[sample.int(nrow(observed), nMask), , drop = FALSE]
      mat[pick] <- "?"
    }

    seqData <- setNames(
      lapply(seq_len(nrow(mat)), function(i) mat[i, ]),
      rownames(mat)
    )
    ape::write.nexus.data(seqData, impFile, format = "standard", interleaved = FALSE)
    nMask
  }

  invisible(list(neo = .MaskOne("neo"), trans = .MaskOne("trans")))
}

#' @export
.AmbDist <- function(path) {
  if (file.exists(path)) {
    chars <- ReadCharacters(path)
    chars[] <- chars %in% 0:9
    mode(chars) <- "logical"
    list(
      nChar = length(chars),
      nAmb = sum(!chars),
      pChar = colSums(!chars) / dim(chars)[[1]],
      pTax = rowSums(!chars) / dim(chars)[[2]]
    )
  } else {
    warning("No file at ", path)
    vector("list", 4)
  }
}


# Equivalently:
# .DecodeTips <- function(n, row = 2) {
#   tr0 <- readLines(MkPath(sprintf("sim%03d", n), "imp_sp_nt_kv_run_1.trees"), row)[[row]]
#   tipTop <- strsplit(tr0, "tip_")[[1]][-1]
#   tip <- gsub("^(\\d+).*", "\\1", tipTop)
#   idx <- gsub("^\\d+\\[&index=(\\d+)\\].*", "\\1", tipTop)
#   # ti <- as.numeric(tip)[order(as.numeric(idx))] # ti[2] = 10 because end_2 is tip 10
#   it <- as.numeric(idx)[order(as.numeric(tip))] # it[10] = 2 because tip 10 is end_2
# }
#' @export
.DecodeTips <- function(nTip) {
  order(order(as.character(seq_len(nTip))))
}

#' @export
.Invariant <- function(sim, nex) {
  impDat <- do.call(rbind, read.nexus.data(
    MkPath(sprintf("sim%03d", sim), nex)))
  impDat[impDat == "?"] <- NA
  impStates <- apply(`mode<-`(impDat, "integer") + 1, 2, tabulate, 2)
  structure(which(colSums(impStates == 0) > 0), nChar = ncol(impStates))
}

#' Pool runs within each replicate, then summarise per replicate
#' Each cell of `accuracy` is a list of nTip vectors (one per tip);
#' c() concatenates the two runs' values for the same tip.
#' @export
.PoolRuns <- function(r1, r2) {
  Map(c, r1, r2)
}

#' Mean accuracy across all tips and characters for one replicate
#' @export
.MeanAcc <- function(pooled) {
  mean(unlist(pooled), na.rm = TRUE)
}
