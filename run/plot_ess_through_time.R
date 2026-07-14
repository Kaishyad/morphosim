#Plot ESS through time for a single run
#Distinguishes slow-climb vs trapped-in-local-optimum failure modes
#Usage: Rscript run/plot_ess_through_time.R --scenario mk --gridtag tl1.0_gl0.1_pr1.0_nc25 --rep sim001 --model model1

source("R/core/_setup.R")

args_cli    <- commandArgs(trailingOnly = TRUE)
.flag       <- function(f) args_cli[which(args_cli == f) + 1]

SCENARIO <- .flag("--scenario"); if (is.na(SCENARIO)) SCENARIO <- "mk"
GRID_TAG <- .flag("--gridtag");  if (is.na(GRID_TAG)) stop("--gridtag required")
REP_ID   <- .flag("--rep");      if (is.na(REP_ID))   REP_ID   <- "sim001"
MODEL_ID <- .flag("--model");    if (is.na(MODEL_ID)) MODEL_ID <- "model1"
N_RUNS   <- 2L

.ESS1 <- function(x) {
  n  <- length(x)
  ac <- acf(x, lag.max = n - 1, plot = FALSE)$acf[-1]
  pairs  <- ac[seq(1, length(ac) - 1, 2)] + ac[seq(2, length(ac), 2)]
  cutoff <- which(pairs < 0)[1]
  if (is.na(cutoff)) cutoff <- length(pairs)
  rho_sum <- 1 + 2 * sum(ac[seq_len(2 * cutoff - 1)])
  max(1, n / rho_sum)
}

all_rows <- vector("list", N_RUNS)

for (run in seq_len(N_RUNS)) {
  f <- ParamLogFile(SCENARIO, GRID_TAG, REP_ID, MODEL_ID, run)
  if (!file.exists(f)) {
    warning("Missing: ", f)
    next
  }

  trace  <- read.table(f, header = TRUE, comment.char = "#")
  params <- setdiff(colnames(trace), "Iteration")

  # Drop burnin (10%)
  trace <- tail(trace, round(nrow(trace) * 0.9))

  step    <- max(1L, floor(nrow(trace) / 50L))   # ~50 points per run
  windows <- seq(10L, nrow(trace), by = step)

  rows <- lapply(params, function(p) {
    ess_vals <- vapply(windows, function(w) .ESS1(trace[[p]][seq_len(w)]), numeric(1))
    data.frame(window = windows, param = p, ess = ess_vals, run = run,
               stringsAsFactors = FALSE)
  })

  all_rows[[run]] <- do.call(rbind, rows)
}

ess_df <- do.call(rbind, all_rows[!vapply(all_rows, is.null, logical(1))])
ess_df$run <- factor(paste0("run", ess_df$run))

title_str <- paste(SCENARIO, GRID_TAG, REP_ID, MODEL_ID, sep = " | ")

p <- ggplot(ess_df, aes(x = window, y = ess, colour = param, linetype = run)) +
  geom_line(linewidth = 0.6) +
  geom_hline(yintercept = ESS_MIN, linetype = "dashed", colour = "black", linewidth = 0.4) +
  annotate("text", x = min(ess_df$window), y = ESS_MIN * 1.05,
           label = paste("ESS_MIN =", ESS_MIN), hjust = 0, size = 3) +
  scale_colour_viridis_d(option = "turbo") +
  labs(title    = "ESS through time",
       subtitle = title_str,
       x        = "Samples included (post burn-in)",
       y        = "ESS",
       colour   = "Parameter",
       linetype = "Run") +
  theme_minimal(base_size = 11) +
  theme(legend.position = "right")

out_dir <- file.path(OutputDir(), "results", "diagnostics")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

fname <- paste0("ess_through_time_", SCENARIO, "_", GRID_TAG, "_",
                REP_ID, "_", MODEL_ID, ".pdf")
out_path <- file.path(out_dir, fname)

ggsave(out_path, plot = p, width = 10, height = 6)
cli::cli_alert_success("Saved: {out_path}")
