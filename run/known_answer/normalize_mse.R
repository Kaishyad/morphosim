
library(dplyr)
library(readr)

source("R/core/_setup.R")
source("run/shared/config_theme.R")

ka <- readRDS(PATHS$known_answer)

ka <- ka %>%
  mutate(
    true_rate_loss = 1 / gain_loss,
    #relative MSE = MSE / true_value^2, equivalent to (RMSE / true_value)^2.
    #puts both parameters on a comparable scale
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
