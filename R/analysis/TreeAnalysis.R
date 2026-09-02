#computes clustering information distance (cid) between posterior tree samples and the known true simulated tree, for each replicate and model.
#adapted from TreeAnalysis.R in neotrans (smith, 2026)

#reads the posterior tree file for a replicate and model, roots all trees on the first tip, and computes the normalised cid between each posterior
#sample and the known true tree
TreeAccuracy <- function(scenario, gridTag, repID, modelID,
                         nRuns = 2, burnFrac = 0.1) {

  # read true tree
  trueFile <- SimTreeFile(scenario, gridTag, repID)
  if (!file.exists(trueFile)) {
    warning("True tree not found: ", trueFile)
    return(NULL)
  }
  trueTree <- ape::read.tree(trueFile)

  #read and pool posterior trees across runs
  postTrees <- unlist(lapply(seq_len(nRuns), function(run) {
    gz <- TreeGzFile(scenario, gridTag, repID, modelID, run)
    tr <- sub("\\.tar\\.gz$", ".trees", gz)

    if (file.exists(gz)) {
      tmp <- tempfile(fileext = ".trees",
                      tmpdir  = TmpDir())
      on.exit(unlink(tmp), add = TRUE)
      system(paste("tar -xzf", shQuote(gz), "-O >", shQuote(tmp)))
      trees <- tryCatch(ape::read.tree(tmp), error = function(e) NULL)
    } else if (file.exists(tr)) {
      trees <- tryCatch(ape::read.tree(tr), error = function(e) NULL)
    } else {
      return(NULL)
    }

    if (is.null(trees)) return(NULL)
    n <- length(trees)
    trees[seq(floor(n * burnFrac) + 1L, n)]
  }), recursive = FALSE)

  if (length(postTrees) == 0) {
    warning("No posterior trees found for ", modelID, " ", gridTag, " ", repID)
    return(NULL)
  }

  #root all trees on first tip label for consistent comparison
  rootTip   <- trueTree$tip.label[[1]]
  trueTree  <- TreeTools::RootTree(trueTree, rootTip)
  postTrees <- lapply(postTrees, TreeTools::RootTree, outgroupTip = rootTip)

  #cid between each posterior sample and the true tree
  vapply(postTrees, function(pt) {
    TreeDist::ClusteringInfoDistance(trueTree, pt, normalize = TRUE)
  }, numeric(1))
}

#summarises tree accuracy across all replicates for one model and grid
#median and iqr of cid values, following the the (wright & hillis 2014; wright et al. 2016)
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

# summarises dispersion of tree distances within and between runs; large
# between-run distances relative to within-run distances indicate the two
# chains haven't mixed. adapted from Dispersion() (supervisor / neotrans
# TreeAnalysis.R). d is a distance matrix from ClusteringInfoDistance() with
# trees from both runs concatenated (run 1 first, run 2 second, equal length).
Dispersion <- function(d) {
  if (is.null(d)) return(NULL)

  dMat  <- as.matrix(d)
  n <- dim(dMat)[[1]] / 2
  runID <- rep(1:2, each = n)

  mat11 <- dMat[runID == 1, runID == 1]; kk <- mat11[lower.tri(mat11)]
  mat22 <- dMat[runID == 2, runID == 2]; nn <- mat22[lower.tri(mat22)]
  nk <- dMat[runID == 1, runID == 2]

  df <- data.frame(
    dist = c(kk, as.vector(nk), nn),
    comp = rep(c("1 vs 1", "1 vs 2", "2 vs 2"),
               c(length(kk), length(nk), length(nn)))
  )

  medianIndex <- c(which.min(colSums(unname(mat11))), which.min(colSums(unname(mat22))))

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
