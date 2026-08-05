# Prepares the runs listed in results/requeue_list.txt (written bycheck_convergence.R / merge_convergence.R) for resubmission via slurm/Infer.R.

# So a convergence-failed cell looks identical to a finished one and gets
# skipped forever unless its existing output is moved out of the way first.
#Rscript run/requeue_failed.R        dry run
#Rscript run/requeue_failed.R --run    actual 

source("R/core/_setup.R")

args_cli <- commandArgs(trailingOnly = TRUE)
do_move  <- "--run" %in% args_cli

requeue_f <- file.path(OutputDir(), "results", "requeue_list.txt")
if (!file.exists(requeue_f)) {
  stop("Requeue list not found: ", requeue_f,
       "\nRun run/check_convergence.R (and merge_convergence.R if per-model) first.")
}

lines  <- readLines(requeue_f)
lines  <- lines[!grepl("^#", lines) & nchar(trimws(lines)) > 0]

if (length(lines) == 0L) {
  message("Requeue list is empty -- nothing to do.")
  quit(save = "no", status = 0L)
}

run_df <- do.call(rbind, lapply(lines, function(l) {
  parts <- strsplit(l, "\t")[[1]]
  if (length(parts) != 4L) return(NULL)
  data.frame(scenario = parts[1], gridTag = parts[2],
             repID    = parts[3], modelID  = parts[4],
             stringsAsFactors = FALSE)
}))

cli::cli_alert_info("{nrow(run_df)} failed run(s) to requeue.")

stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
archive_root <- file.path(OutputDir(), "results", "_requeued_stale", stamp)

moved <- 0L
missing <- 0L

for (ri in seq_len(nrow(run_df))) {
  row <- run_df[ri, ]
  src <- InferDirAbs(row$scenario, row$gridTag, row$repID, row$modelID)

  if (!dir.exists(src)) {
    missing <- missing + 1L
    next
  }

  dest <- file.path(archive_root, row$scenario, row$gridTag, row$repID, row$modelID)

  if (do_move) {
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    file.rename(src, dest)
  } else {
    message(sprintf("[DRY RUN] would move %s -> %s", src, dest))
  }
  moved <- moved + 1L
}

cli::cli_alert_success(sprintf(
  "%s %d cell(s)%s. %d row(s) had no existing output dir (already clear).",
  if (do_move) "Moved" else "Would move", moved,
  if (do_move) paste(" to", archive_root) else "", missing
))

# Print the Infer.R commands needed to pick these back up
combos <- unique(run_df[, c("scenario", "modelID")])
cli::cli_h2("Next: resubmit with Infer.R, scoped to the affected scenario/model combos")
for (i in seq_len(nrow(combos))) {
  cli::cli_alert_info(sprintf(
    "Rscript slurm/Infer.R --run --scenario %s --model %s",
    combos$scenario[i], combos$modelID[i]
  ))
}

if (!do_move) {
  cli::cli_alert_warning("This was a dry run -- pass --run to actually move the stale output directories.")
}
