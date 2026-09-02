# checks ess, r-hat, and trace plots for a single inference run
# usage:
#   Rscript run/misc/check_single_run.R --scenario mk --model model1 --grid tl1.00_gl0.10_c25 --rep sim001

source("R/core/_setup.R")

args_cli <- commandArgs(trailingOnly = TRUE)
scenario <- args_cli[which(args_cli == "--scenario") + 1]
modelID  <- args_cli[which(args_cli == "--model")    + 1]
gridTag  <- args_cli[which(args_cli == "--grid")     + 1]
repID    <- args_cli[which(args_cli == "--rep")      + 1]

# defaults for interactive use
if (is.na(scenario)) scenario <- "mk"
if (is.na(modelID))  modelID  <- "model1"
if (is.na(gridTag))  gridTag  <- "tl1.00_gl0.10_c25"
if (is.na(repID))    repID    <- "sim001"

message(sprintf("Checking: %s / %s / %s / %s", scenario, gridTag, repID, modelID))

rhat <- ComputeRhat(scenario, gridTag, repID, modelID)
ess  <- ComputeESS(scenario, gridTag, repID, modelID)

cat("\n--- R-hat (target < 1.02) ---\n")
print(round(rhat, 4))

cat("\n--- ESS (target > 256) ---\n")
print(round(ess, 0))

# trace plots
log1 <- read.table(
  ParamLogFile(scenario, gridTag, repID, modelID, run = 1),
  header = TRUE, comment.char = "#", fill = TRUE
)
log2 <- read.table(
  ParamLogFile(scenario, gridTag, repID, modelID, run = 2),
  header = TRUE, comment.char = "#", fill = TRUE
)

outFile <- file.path(OutputDir(), "diagnostics",
                     paste0(scenario, "_", gridTag, "_", repID, "_", modelID, "_trace.pdf"))
dir.create(dirname(outFile), showWarnings = FALSE, recursive = TRUE)

pdf(outFile, width = 10, height = 8)

params <- setdiff(colnames(log1), "Iteration")
par(mfrow = c(length(params), 1), mar = c(2, 4, 2, 1))

for (p in params) {
  yrange <- range(c(log1[[p]], log2[[p]]), na.rm = TRUE)
  plot(log1[[p]], type = "l", col = "#0072B2", lwd = 1,
       main = p, ylab = p, xlab = "Iteration",
       ylim = yrange, frame.plot = FALSE)
  lines(log2[[p]], col = "#D55E00", lwd = 1)
  legend("topright", bty = "n", lwd = 1,
         col = c("#0072B2", "#D55E00"),
         legend = c("Run 1", "Run 2"))
  abline(v = floor(nrow(log1) * 0.1), lty = 2, col = "grey50")   # mark 10% burnin
}

dev.off()
cat(sprintf("\nTrace plot saved to: %s\n", outFile))
