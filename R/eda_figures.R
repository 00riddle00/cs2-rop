#!/usr/bin/env Rscript
# Initial data analysis for the first draft.
#
# Reads the two analysis tables in data/analysis/ (Parquet if the arrow package
# is installed, otherwise the CSV copies), prints a dataset summary and writes
# four figures as PDF to reports/figures/:
#
#   fig_side_win_rate.pdf    CT and T round win rate per map
#   fig_alive_heatmap.pdf    CT win rate by number of players alive on each side
#   fig_buy_types.pdf        CT win rate by the buy types of both sides
#   fig_bomb_plant.pdf       T win rate with and without a bomb plant, by site
#
# Run from the repository root:
#   Rscript R/eda_figures.R
#
# Packages: dplyr, tidyr, ggplot2, and arrow or readr.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

data_dir <- "data/analysis"
out_dir <- "reports/figures"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

read_table <- function(name) {
  parquet <- file.path(data_dir, paste0(name, ".parquet"))
  if (requireNamespace("arrow", quietly = TRUE) && file.exists(parquet)) {
    return(as_tibble(arrow::read_parquet(parquet)))
  }
  readr::read_csv(file.path(data_dir, paste0(name, ".csv")), show_col_types = FALSE)
}

map_label <- function(x) tools::toTitleCase(sub("^de_", "", x))
percent <- scales::label_percent(accuracy = 1)

save_plot <- function(plot, name, width = 6.5, height = 4) {
  path <- file.path(out_dir, name)
  ggsave(path, plot, width = width, height = height)
  cat("Written:", path, "\n")
}

theme_set(theme_minimal(base_size = 11))

rounds <- read_table("rounds") |> mutate(map = map_label(map))
states <- read_table("round_states") |> mutate(map = map_label(map))

# --- Dataset summary ------------------------------------------------------------
# Numbers for the dataset description table in the report.
summary_tbl <- rounds |>
  group_by(map) |>
  summarise(
    games = n_distinct(match_id),
    rounds = n(),
    overtime_games = n_distinct(match_id[is_overtime]),
    ct_win_rate = mean(ct_win),
    .groups = "drop"
  ) |>
  left_join(count(states, map, name = "states"), by = "map")
cat("\nDataset summary\n")
print(summary_tbl)
cat("Total:", n_distinct(rounds$match_id), "games,", nrow(rounds), "rounds,",
    nrow(states), "states\n\n")

# --- Figure 1: side win rate per map ---------------------------------------------
side <- rounds |>
  group_by(map) |>
  summarise(CT = mean(ct_win), T = 1 - mean(ct_win), n = n(), .groups = "drop") |>
  pivot_longer(c(CT, T), names_to = "side", values_to = "win_rate")

p1 <- ggplot(side, aes(map, win_rate, fill = side)) +
  geom_col(position = position_dodge(width = 0.8), width = 0.7) +
  geom_text(aes(label = percent(win_rate)),
            position = position_dodge(width = 0.8), vjust = -0.4, size = 3.5) +
  geom_hline(yintercept = 0.5, linetype = "dashed", colour = "grey40") +
  scale_y_continuous(labels = percent, limits = c(0, 1)) +
  scale_fill_manual(values = c(CT = "#4a7fb5", T = "#d9a03f")) +
  labs(x = NULL, y = "Round win rate", fill = "Side",
       title = "Round win rate by side and map")
save_plot(p1, "fig_side_win_rate.pdf", width = 5.5)

# --- Figure 2: CT win rate by players alive ---------------------------------------
# Each round counts once per alive-count combination it passed through, so long
# stretches of a round do not outweigh short ones.
min_rounds <- 20
alive <- states |>
  distinct(map, match_id, part, round_num, ct_alive, t_alive, ct_win) |>
  group_by(map, ct_alive, t_alive) |>
  summarise(ct_win_rate = mean(ct_win), n = n(), .groups = "drop") |>
  filter(n >= min_rounds)

p2 <- ggplot(alive, aes(t_alive, ct_alive, fill = ct_win_rate)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = percent(ct_win_rate)), size = 2.8) +
  scale_fill_gradient2(low = "#d9a03f", mid = "white", high = "#4a7fb5",
                       midpoint = 0.5, limits = c(0, 1), labels = percent) +
  scale_x_continuous(breaks = 0:5) +
  scale_y_continuous(breaks = 0:5) +
  coord_equal() +
  facet_wrap(~map) +
  labs(x = "T players alive", y = "CT players alive", fill = "CT win rate",
       title = "CT win rate by players alive",
       caption = sprintf("Cells with fewer than %d rounds are left out.", min_rounds))
save_plot(p2, "fig_alive_heatmap.pdf", width = 7.5, height = 4.2)

# --- Figure 3: CT win rate by buy types ---------------------------------------------
buy_levels <- c("pistol", "eco", "force", "full")
buy_levels <- c(buy_levels,
                setdiff(unique(c(rounds$ct_buy_type, rounds$t_buy_type)),
                        c(buy_levels, NA)))
buy <- rounds |>
  filter(!is.na(ct_buy_type), !is.na(t_buy_type)) |>
  mutate(across(c(ct_buy_type, t_buy_type), \(x) factor(x, levels = buy_levels))) |>
  group_by(ct_buy_type, t_buy_type) |>
  summarise(ct_win_rate = mean(ct_win), n = n(), .groups = "drop")

p3 <- ggplot(buy, aes(t_buy_type, ct_buy_type, fill = ct_win_rate)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = sprintf("%s\nn = %d", percent(ct_win_rate), n)), size = 3) +
  scale_fill_gradient2(low = "#d9a03f", mid = "white", high = "#4a7fb5",
                       midpoint = 0.5, limits = c(0, 1), labels = percent) +
  coord_equal() +
  labs(x = "T buy type", y = "CT buy type", fill = "CT win rate",
       title = "CT win rate by buy types",
       caption = "Buy types at freeze end; rounds without a buy type are left out.")
save_plot(p3, "fig_buy_types.pdf", width = 5.5, height = 4.5)

# --- Figure 4: bomb plant and T win rate ---------------------------------------------
bomb <- rounds |>
  mutate(plant = if_else(bomb_planted,
                         paste0("Planted ", coalesce(plant_site, "?")),
                         "Not planted")) |>
  group_by(map, plant) |>
  summarise(t_win_rate = 1 - mean(ct_win), n = n(), .groups = "drop")

p4 <- ggplot(bomb, aes(plant, t_win_rate)) +
  geom_col(fill = "#d9a03f", width = 0.7) +
  geom_text(aes(label = sprintf("%s\nn = %d", percent(t_win_rate), n)),
            vjust = -0.2, size = 3) +
  scale_y_continuous(labels = percent, limits = c(0, 1.1),
                     breaks = seq(0, 1, 0.25)) +
  facet_wrap(~map) +
  labs(x = NULL, y = "T round win rate",
       title = "T win rate with and without a bomb plant")
save_plot(p4, "fig_bomb_plant.pdf", width = 7, height = 4)
