#Submits inference jobs 

#Rscript slurm/Infer.R  # dry run, all models, both scenarios
# Rscript slurm/Infer.R --run   # submit all
#Rscript slurm/Infer.R --run --scenario mk  # mk only
#Rscript slurm/Infer.R --run --scenario mk --model model1   # mk + model1 only
# Rscript slurm/Infer.R --run --imputation   # imputation runs instead of
#   standard inference -- requires imp_neo.nex/imp_trans.nex to already
#   exist (run/imputation/mask_replicates.R first)

source("R/core/_setup.R")

# --- Safety parameters 
MAX_QUEUE_DEPTH  <- 70L    
POLL_INTERVAL_SEC <- 120L
SUBMIT_PAUSE_SEC  <- 0.5

# --- Argument parsing
args_cli      <- commandArgs(trailingOnly = TRUE)
dry_run       <- !("--run" %in% args_cli)
imputation    <- "--imputation" %in% args_cli
scenario_flag <- args_cli[which(args_cli == "--scenario") + 1]
model_flag    <- args_cli[which(args_cli == "--model")    + 1]

scenarios <- if (!is.na(scenario_flag[1])) scenario_flag else c("nt", "mk")
models    <- if (!is.na(model_flag[1]))    model_flag    else paste0("model", 1:12)

if (dry_run) message("Dry run — pass --run to submit jobs")
message(sprintf("Scenarios: %s | Models: %s%s",
                paste(scenarios, collapse = ", "),
                paste(models,    collapse = ", "),
                if (imputation) " | IMPUTATION run" else ""))

# --- Paths 
remote_dir <- getOption("ntRemoteDir")          
rb_mpi     <- RbBinary()
morphosim  <- file.path(remote_dir, "morphosim")
matrix_dir <- file.path(remote_dir, "the-matrix")
log_dir    <- file.path(morphosim, "logs")
infer_script <- file.path(morphosim, "rbScripts", "Inference",
                          if (imputation) "imp-mc3.Rev" else "sim-mc3.Rev")
# imp-mc3.Rev reads imp_neo.nex/imp_trans.nex (produced by MaskReplicate())
# instead of neo.nex/trans.nex, and every output file it writes gets an
# imp_ prefix so it can coexist in the same results/ directory as a normal
# inference run of the same model.
data_file    <- if (imputation) "imp_neo.nex" else "neo.nex"
out_prefix   <- if (imputation) "imp_" else ""

# --- Queue helpers 
.queue_depth <- function() {
  out <- tryCatch(
    system("squeue -u \"$USER\" -h -o '%i' 2>/dev/null | wc -l",
           intern = TRUE, ignore.stderr = TRUE),
    error = function(e) "0"
  )
  as.integer(trimws(out[length(out)]))
}

.wait_for_slot <- function() {
  repeat {
    depth <- .queue_depth()
    if (depth < MAX_QUEUE_DEPTH) return(invisible(NULL))
    message(sprintf("  Queue depth %d >= limit %d — waiting %ds ...",
                    depth, MAX_QUEUE_DEPTH, POLL_INTERVAL_SEC))
    Sys.sleep(POLL_INTERVAL_SEC)
  }
}

# --- Inference loop
submitted <- 0L
skipped   <- 0L
failed    <- 0L

for (scenario in scenarios) {

  # Mk ignores part_rate 
  grid <- if (scenario == "mk") {
    unique(PARAM_GRID[, c("tree_length", "gain_loss", "n_char",
                          "n_taxa", "n_neo", "n_trans")])
  } else {
    PARAM_GRID
  }

  for (gi in seq_len(nrow(grid))) {
    row     <- grid[gi, ]
    gridTag <- GridTag(row)

    for (rep in seq_len(N_REP)) {
      repID     <- SimID(rep)
      simDirAbs <- SimDirAbs(scenario, gridTag, repID)

      #Skip if simulated (or, for imputation, masked) data doesn't exist
      if (!file.exists(file.path(simDirAbs, data_file))) {
        skipped <- skipped + 1L
        next
      }

      for (scriptID in models) {

        job_name <- paste0(if (imputation) "impinf_" else "inf_",
                           scenario, "_", gridTag, "_", repID,
                           "_", scriptID)
        out_log  <- file.path(log_dir, paste0(job_name, ".out"))
        err_log  <- file.path(log_dir, paste0(job_name, ".err"))

        #Skip only if inference is actually complete for both runs.
        
        inferDirAbs <- InferDirAbs(scenario, gridTag, repID, scriptID)
        if (JobLogsComplete(scenario, gridTag, repID, scriptID, prefix = out_prefix)) {
          skipped <- skipped + 1L
          next
        }

        #Create inference output directory
        if (!dir.exists(inferDirAbs)) dir.create(inferDirAbs, recursive = TRUE)

        #Pass both simDirAbs (data) and inferDirAbs (outputs) to sim-mc3.Rev
        rb_args <- InferArgs(simDirAbs, inferDirAbs, scriptID, minEss = 333L, seed = rep)

        if (dry_run) {
          message(sprintf("[DRY RUN] %s | %s | %s | %s",
                          scenario, gridTag, repID, scriptID))
          message("  rb_args: ", paste(rb_args, collapse = " "))
          next
        }

        .wait_for_slot()

        #no git push done by push_when_done.sh actually
        infer_subdir <- file.path("results", scenario, gridTag, repID, scriptID)

        wrap_cmd <- paste(
          "module load gcc/11.2 boost/1.78.0 openmpi/4.1.1;",
          "cd", shQuote(morphosim), ";",
          "echo Starting", scriptID, "on", scenario, gridTag, repID, "at $(date);",
          "mpirun", shQuote(rb_mpi),
            shQuote(infer_script),
            paste(sapply(rb_args, shQuote), collapse = " "), ";",
          "cd", shQuote(file.path(matrix_dir, infer_subdir)), ";",
          "for f in ", paste0(out_prefix, scriptID, "_run_*.trees;"),
            "do [ -f \"$f\" ] &&",
            "tar -czf \"${f%.trees}.tar.gz\" \"$f\" &&",
            "rm \"$f\";",
          "done;",
          "echo Done at $(date)"
        )

        slurmCmd <- paste(
          "sbatch",
          "--ntasks=16",      
          "--nodes=1",        
          "--mem=4G",
          "--time=23:45:00",
          "--gres=tmp:16G",
          "-p shared",
          "--job-name", shQuote(job_name),
          "--output",   shQuote(out_log),
          "--error",    shQuote(err_log),
          "--wrap",     shQuote(wrap_cmd)
        )

        result <- system(slurmCmd, ignore.stdout = TRUE)

        if (result == 0L) {
          submitted <- submitted + 1L
        } else {
          warning("sbatch failed for ", job_name)
          failed <- failed + 1L
        }

        Sys.sleep(SUBMIT_PAUSE_SEC)
      }
    }
  }
}

message(sprintf(
  "Submitted: %d  |  Skipped: %d  |  Failed: %d",
  submitted, skipped, failed
))
