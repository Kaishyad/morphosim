# Adds scale-normalized error columns so tree_length and gain-loss rate MSE
# can be compared on the same footing (raw MSE cannot -- gain-loss rate true
# values run 1-10, tree_length true values run 1-5, so raw squared error is
# mechanically larger for the rate parameter regardless of estimation quality).
#
# Normalization is done PER GRID CELL (not from a single global mean), using
# each row's own true tree_length, since MSE already varies by which grid
# cell each row summarises.
#
# True rate-loss value is derived as 1/gain_loss (the model's own tracked
# "gain_loss_neo" true_value follows this pattern -- verify this matches
# your Rev model's own parameterisation before trusting the derived column;
# it was reverse-engineered from cgr_coverage.rds's true_value column, not
# read directly from the RevBayes spec).

library(dplyr)
library(readr)

source("R/core/_setup.R")
source("run/shared/config_theme.R")

ka <- readRDS(PATHS$known_answer)

ka <- ka %>%
  mutate(
    true_rate_loss = 1 / gain_loss,
    # Relative MSE = MSE / true_value^2, equivalent to (RMSE / true_value)^2.
    # This puts both parameters on a unitless, comparable scale.
    rel_mse_tree_len  = mse_tree_len  / (tree_length^2),
    rel_mse_rate_loss = mse_rate_loss / (true_rate_loss^2)
  )

summary_normalized <- ka %>%
  group_by(modelID, scenario) %>%
  summarise(
    mean_mse_tree_len      = mean(mse_tree_len, na.rm = TRUE),
    mean_rel_mse_tree_len  = mean(rel_mse_tree_len, na.rm = TRUE),
    mean_mse_rate_loss     = mean(mse_rate_loss, na.rm = TRUE),
    mean_rel_mse_rate_loss = mean(rel_mse_rate_loss, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(scenario, mean_rel_mse_tree_len)

print(summary_normalized, n = Inf)

write_csv(summary_normalized,
          file.path(PATHS$results_dir, "known_answer", "table4_mse_summary_normalized.csv"))
