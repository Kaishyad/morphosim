# R/TreeAnalysis.R
# Tree accuracy functions
# Computes Clustering Information Distance (CID) between posterior tree
# samples and the known true simulated tree for each replicate and model.
#
# CID is preferred over Robinson-Foulds because it is sensitive to partial
# topological similarity, does not treat all errors as equally severe, and
# avoids saturation and imprecision problems (Smith 2019, 2020, 2022).
#
# Adapted from TreeAnalysis.R (supervisor / neotrans).
# Kept and adapted: Dispersion() for within-run convergence diagnostics.

# Used in: analysis/tree_accuracy.R

# --- Tree accuracy

#' Compute CID between posterior tree samples and the true tree
#'
#' Reads the posterior tree file for a replicate and model, roots all trees
#' on the first tip, and computes the normalised Clustering Information
#' Distance between each posterior sample and the known true tree.
#'
#' @param scenario  "nt" or "mk"
#' @param gridTag   Grid tag from GridTag()
#' @param repID     Replicate ID e.g. "sim001"
#' @param modelID   Model script name e.g. "model1"
#' @param nRuns     Number of MCMC runs (default 2)
#' @param burnFrac  Fraction of trees to discard as burnin (default 0.1)
#' @return Numeric vector of CID values (one per posterior tree sample),
#'   or NULL if the tree file is missing.
#' @importFrom ape read.tree
#' @importFrom TreeTools RootTree
#' @importFrom TreeDist ClusteringInfoDistance
#' @export
TreeAccuracy <- function(scenario, gridTag, repID, modelID,
                         nRuns = 2, burnFrac = 0.1) {
  
  # Read true tree
  trueFile <- SimTreeFile(scenario, gridTag, repID)
  if (!file.exists(trueFile)) {
    warning("True tree not found: ", trueFile)
    return(NULL)
  }
  trueTree <- ape::read.tree(trueFile)
  
  # Read and pool posterior trees across runs
  postTrees <- unlist(lapply(seq_len(nRuns), function(run) {
    gz <- TreeGzFile(scenario, gridTag, repID, modelID, run)
    tr <- sub("\\.tar\\.gz$", ".trees", gz)
    
    treeFile <- if (file.exists(gz)) {
      tmp <- tempfile(fileext = ".trees")
      system(paste("tar -xzf", shQuote(gz), "-O >", shQuote(tmp)))
      tmp
    } else if (file.exists(tr)) {
      tr
    } else {
      NULL
    }
    
    if (is.null(treeFile)) return(NULL)
    trees <- ape::read.tree(treeFile)
    n     <- length(trees)
    trees[seq(floor(n * burnFrac) + 1L, n)]
  }), recursive = FALSE)
  
  if (length(postTrees) == 0) {
    warning("No posterior trees found for ", modelID, " ", gridTag, " ", repID)
    return(NULL)
  }
  
  # Root all trees on first tip label for consistent comparison
  rootTip  <- trueTree$tip.label[[1]]
  trueTree <- TreeTools::RootTree(trueTree, rootTip)
  postTrees<- lapply(postTrees, TreeTools::RootTree, outgroupTip = rootTip)
  
  # CID between each posterior sample and the true tree
  vapply(postTrees, function(pt) {
    TreeDist::ClusteringInfoDistance(trueTree, pt, normalize = TRUE)
  }, numeric(1))
}

#' Summarise tree accuracy across all replicates for one model and grid cell
#'
#' Returns median and IQR of CID values, following the reporting convention
#' in the literature review (Wright & Hillis 2014; Wright et al. 2016).
#'
#' @param scenario "nt" or "mk"
#' @param gridTag  Grid tag
#' @param modelID  Model script name
#' @param nRep     Replicates per cell (default N_REP)
#' @return Data frame with columns: scenario, gridTag, modelID, median_cid,
#'   iqr_cid, n_reps (number of replicates with valid results).
#' @export
TreeAccuracySummary <- function(scenario, gridTag, modelID,
                                nRep = N_REP) {
  cids <- unlist(lapply(seq_len(nRep), function(rep) {
    TreeAccuracy(scenario, gridTag, SimID(rep), modelID)
  }))
  
  data.frame(
    scenario   = scenario,
    gridTag    = gridTag,
    modelID    = modelID,
    median_cid = median(cids, na.rm = TRUE),
    iqr_cid    = IQR(cids,    na.rm = TRUE),
    n_reps     = sum(!is.na(cids)),
    stringsAsFactors = FALSE
  )
}

# --- Dispersion

#' Summarise dispersion of tree distances within and between runs
#'
#' Used as a convergence diagnostic: large between-run distances relative to
#' within-run distances indicate the two chains have not mixed.
#' Adapted from Dispersion() (supervisor / neotrans TreeAnalysis.R) — kept
#' as-is since it has no empirical project dependencies.
#'
#' @param d A distance matrix from ClusteringInfoDistance() with trees from
#'   both runs concatenated (run 1 first, run 2 second, equal length).
#' @return Named list with elements treePairs (data frame), spread (matrix),
#'   mdmd (median-to-median distance), sil (silhouette width).
#' @importFrom TreeDist DistanceFromMedian MeanMSTEdge MeanNN
#' @importFrom cluster silhouette
#' @export
Dispersion <- function(d) {
  if (is.null(d)) return(NULL)
  
  dMat  <- as.matrix(d)
  n     <- dim(dMat)[[1]] / 2
  runID <- rep(1:2, each = n)
  
  mat11 <- dMat[runID == 1, runID == 1]; kk <- mat11[lower.tri(mat11)]
  mat22 <- dMat[runID == 2, runID == 2]; nn <- mat22[lower.tri(mat22)]
  nk    <- dMat[runID == 1, runID == 2]
  
  df <- data.frame(
    dist = c(kk, as.vector(nk), nn),
    comp = rep(c("1 vs 1", "1 vs 2", "2 vs 2"),
               c(length(kk), length(nk), length(nn)))
  )
  
  medianIndex <- c(which.min(colSums(unname(mat11))),
                   which.min(colSums(unname(mat22))))
  
  spread <- cbind(
    mdI = medianIndex,
    mst = MeanMSTEdge(d, cluster = runID),
    nn  = MeanNN(d,  cluster = runID, Average = median),
    mad = DistanceFromMedian(d, cluster = runID, Average = median)
  )
  
  list(
    treePairs = df,
    spread    = spread,
    mdmd      = dMat[medianIndex[[1]], n + medianIndex[[2]]],
    sil       = mean(cluster::silhouette(dist = d, runID)[, 3])
  )
}