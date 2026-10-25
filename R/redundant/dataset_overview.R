
# ============================================================
# CS2 DATASET OVERVIEW AND INITIAL ANALYSIS
# Sections 2, 2.1, 2.2, 2.3, 3 and 4
# ============================================================

# 0. Packages -------------------------------------------------

library(tidyverse)
library(arrow)

# Input files should be in getwd()
rounds_file <- "../data/analysis/rounds.parquet"
states_file <- "../data/analysis/round_states.parquet"
enriched_file <- "../data/analysis/round_states_enriched.parquet"

# Output folder for tables and plots
output_dir <- "dataset_overview_output"
dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

# Read datasets
rounds <- read_parquet(rounds_file) |> as_tibble()
round_states <- read_parquet(states_file) |> as_tibble()
round_states_enriched <- read_parquet(enriched_file) |> as_tibble()

# Basic checks
stopifnot(all(c("match_id", "map", "round_num") %in% names(rounds)))
stopifnot(all(c("match_id", "map", "round_num", "tick", "seconds",
                "ct_alive", "t_alive", "ct_win") %in% names(round_states)))
stopifnot(all(c("match_id", "map", "round_num") %in%
                names(round_states_enriched)))

# Helper: save a table as CSV
save_table <- function(data, filename) {
  write_csv(data, file.path(output_dir, filename), na = "")
}

# Helper: save a plot
save_plot <- function(plot, filename, width = 9, height = 6) {
  ggsave(
    filename = file.path(output_dir, filename),
    plot = plot,
    width = width,
    height = height,
    dpi = 300
  )
}


# ============================================================
# 2. DATASET STRUCTURE
# ============================================================

# Number of rows, columns and missing values in each dataset
dataset_overview <- tibble(
  dataset = c(
    "rounds",
    "round_states",
    "round_states_enriched"
  ),
  rows = c(
    nrow(rounds),
    nrow(round_states),
    nrow(round_states_enriched)
  ),
  columns = c(
    ncol(rounds),
    ncol(round_states),
    ncol(round_states_enriched)
  ),
  missing_cells = c(
    sum(is.na(rounds)),
    sum(is.na(round_states)),
    sum(is.na(round_states_enriched))
  ),
  unique_matches = c(
    n_distinct(rounds$match_id),
    n_distinct(round_states$match_id),
    n_distinct(round_states_enriched$match_id)
  ),
  unique_rounds = c(
    nrow(distinct(rounds, match_id, round_num)),
    nrow(distinct(round_states, match_id, round_num)),
    nrow(distinct(round_states_enriched, match_id, round_num))
  )
)

print(dataset_overview)
save_table(dataset_overview, "02_dataset_overview.csv")

# Save the names and data types of all columns
column_overview <- bind_rows(
  tibble(
    dataset = "rounds",
    column = names(rounds),
    data_type = map_chr(rounds, ~ paste(class(.x), collapse = "/"))
  ),
  tibble(
    dataset = "round_states",
    column = names(round_states),
    data_type = map_chr(round_states, ~ paste(class(.x), collapse = "/"))
  ),
  tibble(
    dataset = "round_states_enriched",
    column = names(round_states_enriched),
    data_type = map_chr(
      round_states_enriched,
      ~ paste(class(.x), collapse = "/")
    )
  )
)

save_table(column_overview, "02_dataset_columns.csv")

# Distinct maps and teams
map_overview <- rounds |>
  group_by(map) |>
  summarise(
    rounds = n(),
    matches = n_distinct(match_id),
    .groups = "drop"
  )

print(map_overview)
save_table(map_overview, "02_maps.csv")

team_overview <- bind_rows(
  rounds |> transmute(team = ct_team),
  rounds |> transmute(team = t_team)
) |>
  filter(!is.na(team)) |>
  distinct(team) |>
  arrange(team)

print(team_overview)
save_table(team_overview, "02_teams.csv")


# ============================================================
# 2.1 ROUND-LEVEL DATA: rounds.parquet
# ============================================================

# Each row should represent one round
round_key_check <- rounds |>
  count(match_id, round_num, name = "rows_per_round") |>
  filter(rows_per_round > 1)

cat("\nDuplicate round keys:", nrow(round_key_check), "\n")

if (nrow(round_key_check) > 0) {
  print(round_key_check)
}

# Round-level summary by map
rounds_by_map <- rounds |>
  group_by(map) |>
  summarise(
    rounds = n(),
    matches = n_distinct(match_id),
    pistol_rounds = sum(is_pistol_round %in% TRUE, na.rm = TRUE),
    overtime_rounds = sum(is_overtime %in% TRUE, na.rm = TRUE),
    planted_rounds = sum(bomb_planted %in% TRUE, na.rm = TRUE),
    planted_pct = 100 * mean(bomb_planted %in% TRUE, na.rm = TRUE),
    mean_duration_s = mean(round_duration_s, na.rm = TRUE),
    median_duration_s = median(round_duration_s, na.rm = TRUE),
    .groups = "drop"
  )

print(rounds_by_map)
save_table(rounds_by_map, "21_rounds_by_map.csv")

# Match length: how many rounds each match contains
rounds_per_match <- rounds |>
  distinct(match_id, map, round_num) |>
  count(match_id, map, name = "rounds_in_match")

match_length_summary <- rounds_per_match |>
  summarise(
    matches = n(),
    min_rounds = min(rounds_in_match),
    q1_rounds = quantile(rounds_in_match, 0.25),
    median_rounds = median(rounds_in_match),
    mean_rounds = mean(rounds_in_match),
    q3_rounds = quantile(rounds_in_match, 0.75),
    max_rounds = max(rounds_in_match)
  )

print(match_length_summary)
save_table(match_length_summary, "21_match_length_summary.csv")

# Round outcome by map and winning side
round_outcomes <- rounds |>
  count(map, winner_side, name = "rounds") |>
  group_by(map) |>
  mutate(
    percentage = 100 * rounds / sum(rounds)
  ) |>
  ungroup()

print(round_outcomes)
save_table(round_outcomes, "21_round_outcomes.csv")

p_round_outcomes <- ggplot(
  round_outcomes,
  aes(x = map, y = percentage, fill = winner_side)
) +
  geom_col(position = "stack") +
  geom_text(
    aes(label = sprintf("%.1f%%", percentage)),
    position = position_stack(vjust = 0.5),
    size = 3.5
  ) +
  labs(
    title = "Round outcomes by map",
    x = "Map",
    y = "Percentage of rounds",
    fill = "Winning side"
  ) +
  theme_minimal()

print(p_round_outcomes)
save_plot(p_round_outcomes, "21_round_outcomes_by_map.png")


# ============================================================
# 2.2 ROUND-STATE DATA: round_states.parquet
# ============================================================

# Each row represents a snapshot of one round at a particular tick/time.
# Snapshots within the same round are repeated observations, not
# independent rounds.

# Snapshot count per round
snapshots_per_round <- round_states |>
  count(match_id, map, round_num, name = "snapshots")

snapshot_count_summary <- snapshots_per_round |>
  summarise(
    rounds = n(),
    min_snapshots = min(snapshots),
    q1_snapshots = quantile(snapshots, 0.25),
    median_snapshots = median(snapshots),
    mean_snapshots = mean(snapshots),
    q3_snapshots = quantile(snapshots, 0.75),
    max_snapshots = max(snapshots)
  )

print(snapshot_count_summary)
save_table(snapshot_count_summary, "22_snapshot_count_summary.csv")

# Snapshot timing range
snapshot_timing <- round_states |>
  summarise(
    min_seconds = min(seconds, na.rm = TRUE),
    median_seconds = median(seconds, na.rm = TRUE),
    max_seconds = max(seconds, na.rm = TRUE),
    min_time_remaining = min(time_remaining_s, na.rm = TRUE),
    max_time_remaining = max(time_remaining_s, na.rm = TRUE)
  )

print(snapshot_timing)
save_table(snapshot_timing, "22_snapshot_timing.csv")

# Missingness in the snapshot dataset
snapshot_missingness <- tibble(
  column = names(round_states),
  missing_values = map_int(round_states, ~ sum(is.na(.x))),
  missing_pct = 100 * missing_values / nrow(round_states)
) |>
  arrange(desc(missing_values))

print(snapshot_missingness)
save_table(snapshot_missingness, "22_snapshot_missingness.csv")

# Player-count advantage at snapshot level
# Positive difference means CT has more living players.
# Negative difference means T has more living players.
state_advantage <- round_states |>
  mutate(
    alive_difference = ct_alive - t_alive,
    alive_advantage = case_when(
      alive_difference > 0 ~ "CT advantage",
      alive_difference < 0 ~ "T advantage",
      alive_difference == 0 ~ "Equal alive players",
      TRUE ~ NA_character_
    )
  )

advantage_by_outcome <- state_advantage |>
  filter(!is.na(ct_win), !is.na(alive_advantage)) |>
  group_by(alive_advantage) |>
  summarise(
    snapshots = n(),
    ct_round_win_pct = 100 * mean(ct_win, na.rm = TRUE),
    .groups = "drop"
  )

print(advantage_by_outcome)
save_table(advantage_by_outcome, "22_alive_advantage_by_outcome.csv")

p_alive_advantage <- ggplot(
  advantage_by_outcome,
  aes(x = alive_advantage, y = ct_round_win_pct)
) +
  geom_col() +
  geom_text(
    aes(label = sprintf("%.1f%%", ct_round_win_pct)),
    vjust = -0.3
  ) +
  scale_y_continuous(
    limits = c(0, 100),
    expand = expansion(mult = c(0, 0.08))
  ) +
  labs(
    title = "CT round-win percentage by alive-player advantage",
    subtitle = "Snapshot-level descriptive comparison",
    x = "Player-count state",
    y = "CT round wins (%)"
  ) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 15, hjust = 1))

print(p_alive_advantage)
save_plot(p_alive_advantage, "22_alive_advantage_by_outcome.png")


# ============================================================
# 2.3 ENRICHED ROUND-STATE DATA
# ============================================================

# Check whether enrichment preserved the snapshot row count
enrichment_comparison <- tibble(
  dataset = c("round_states", "round_states_enriched"),
  rows = c(nrow(round_states), nrow(round_states_enriched)),
  columns = c(ncol(round_states), ncol(round_states_enriched)),
  unique_rounds = c(
    nrow(distinct(round_states, match_id, round_num)),
    nrow(distinct(round_states_enriched, match_id, round_num))
  )
)

print(enrichment_comparison)
save_table(enrichment_comparison, "23_enrichment_comparison.csv")

# Check duplicate snapshot keys
snapshot_key_check <- round_states_enriched |>
  count(match_id, round_num, tick, name = "rows_per_snapshot") |>
  filter(rows_per_snapshot > 1)

cat("\nDuplicate match-round-tick keys in enriched data:",
    nrow(snapshot_key_check), "\n")

if (nrow(snapshot_key_check) > 0) {
  print(snapshot_key_check)
}

# Verify that every enriched snapshot has a corresponding round
unmatched_rounds <- round_states_enriched |>
  distinct(match_id, round_num) |>
  anti_join(
    rounds |> distinct(match_id, round_num),
    by = c("match_id", "round_num")
  )

cat("\nEnriched round keys not found in rounds dataset:",
    nrow(unmatched_rounds), "\n")

# Missingness in the enriched dataset
enriched_missingness <- tibble(
  column = names(round_states_enriched),
  missing_values = map_int(
    round_states_enriched,
    ~ sum(is.na(.x))
  ),
  missing_pct = 100 * missing_values / nrow(round_states_enriched)
) |>
  arrange(desc(missing_values))

print(enriched_missingness)
save_table(enriched_missingness, "23_enriched_missingness.csv")

# Check whether round-level fields are constant within each round
# These fields should normally remain constant across snapshots
round_level_fields <- intersect(
  c(
    "winner_side", "winner_team", "reason_name",
    "is_overtime", "is_pistol_round", "bomb_planted",
    "ct_buy_type", "t_buy_type", "first_death_side",
    "round_duration_s"
  ),
  names(round_states_enriched)
)

round_constant_checks <- map_dfr(
  round_level_fields,
  function(field) {
    round_states_enriched |>
      group_by(match_id, round_num) |>
      summarise(
        distinct_values = n_distinct(.data[[field]], na.rm = FALSE),
        .groups = "drop"
      ) |>
      summarise(
        field = field,
        rounds_with_multiple_values = sum(distinct_values > 1),
        .groups = "drop"
      )
  }
)

print(round_constant_checks)
save_table(round_constant_checks, "23_round_level_consistency.csv")


# ============================================================
# 3. INITIAL DESCRIPTIVE CHARACTERISTICS
# ============================================================

# Overall descriptive statistics
overall_summary <- rounds |>
  summarise(
    matches = n_distinct(match_id),
    rounds = n(),
    maps = n_distinct(map),
    teams_ct = n_distinct(ct_team),
    teams_t = n_distinct(t_team),
    planted_rounds = sum(bomb_planted %in% TRUE, na.rm = TRUE),
    planted_round_pct = 100 * mean(bomb_planted %in% TRUE, na.rm = TRUE),
    pistol_rounds = sum(is_pistol_round %in% TRUE, na.rm = TRUE),
    overtime_rounds = sum(is_overtime %in% TRUE, na.rm = TRUE),
    mean_round_duration_s = mean(round_duration_s, na.rm = TRUE),
    median_round_duration_s = median(round_duration_s, na.rm = TRUE)
  )

print(overall_summary)
save_table(overall_summary, "03_overall_summary.csv")

# Round duration distribution
p_duration <- ggplot(
  rounds |> filter(!is.na(round_duration_s)),
  aes(x = round_duration_s)
) +
  geom_histogram(bins = 30) +
  labs(
    title = "Distribution of round duration",
    x = "Round duration (seconds)",
    y = "Number of rounds"
  ) +
  theme_minimal()

print(p_duration)
save_plot(p_duration, "03_round_duration_distribution.png")

# Bomb plant rate by map
plant_summary <- rounds |>
  group_by(map) |>
  summarise(
    total_rounds = n(),
    planted_rounds = sum(bomb_planted %in% TRUE, na.rm = TRUE),
    plant_rate_pct = 100 * mean(bomb_planted %in% TRUE, na.rm = TRUE),
    .groups = "drop"
  )

print(plant_summary)
save_table(plant_summary, "03_bomb_plant_rate.csv")

p_plant_rate <- ggplot(
  plant_summary,
  aes(x = map, y = plant_rate_pct)
) +
  geom_col() +
  geom_text(
    aes(label = sprintf("%.1f%%", plant_rate_pct)),
    vjust = -0.3
  ) +
  scale_y_continuous(
    limits = c(0, 100),
    expand = expansion(mult = c(0, 0.08))
  ) +
  labs(
    title = "Bomb plant rate by map",
    x = "Map",
    y = "Rounds with a bomb plant (%)"
  ) +
  theme_minimal()

print(p_plant_rate)
save_plot(p_plant_rate, "03_bomb_plant_rate.png")

# Distribution of buy types at round level
buy_type_summary <- bind_rows(
  rounds |>
    count(map, buy_type = ct_buy_type, name = "rounds") |>
    mutate(side = "CT"),
  rounds |>
    count(map, buy_type = t_buy_type, name = "rounds") |>
    mutate(side = "T")
) |>
  group_by(map, side) |>
  mutate(percentage = 100 * rounds / sum(rounds)) |>
  ungroup()

print(buy_type_summary)
save_table(buy_type_summary, "03_buy_type_distribution.csv")

p_buy_types <- ggplot(
  buy_type_summary,
  aes(x = buy_type, y = percentage, fill = side)
) +
  geom_col(position = "dodge") +
  labs(
    title = "Buy-type distribution by map and side",
    x = "Buy type",
    y = "Percentage of rounds",
    fill = "Side"
  ) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 30, hjust = 1))

print(p_buy_types)
save_plot(p_buy_types, "03_buy_type_distribution.png")


# ============================================================
# 4. INITIAL ANALYSIS IDEAS
# ============================================================

# IMPORTANT:
# Use one row per round for round-level comparisons.
# Snapshot-level observations within the same round are dependent.
# The analyses below are descriptive, not causal.

# 4.1 Bomb plant and round outcome ----------------------------

plant_outcomes <- rounds |>
  mutate(
    plant_status = case_when(
      bomb_planted %in% TRUE ~ "Planted",
      bomb_planted %in% FALSE ~ "Not planted",
      TRUE ~ "Unknown"
    )
  ) |>
  group_by(map, plant_status) |>
  summarise(
    rounds = n(),
    ct_win_pct = 100 * mean(ct_win, na.rm = TRUE),
    .groups = "drop"
  )

print(plant_outcomes)
save_table(plant_outcomes, "04_1_plant_status_outcomes.csv")

# Plant-site outcomes among rounds with a recorded plant site
plant_site_outcomes <- rounds |>
  filter(
    bomb_planted %in% TRUE,
    !is.na(plant_site)
  ) |>
  group_by(map, plant_site) |>
  summarise(
    planted_rounds = n(),
    ct_win_pct = 100 * mean(ct_win, na.rm = TRUE),
    .groups = "drop"
  )

print(plant_site_outcomes)
save_table(plant_site_outcomes, "04_1_plant_site_outcomes.csv")


# 4.2 Alive-player advantage and round outcome ----------------

# Select one snapshot per round at a consistent point in time:
# latest available snapshot at or before 30 seconds.
# Rounds without such a snapshot are omitted from this comparison.

state_at_30s <- round_states_enriched |>
  filter(seconds <= 30) |>
  group_by(match_id, round_num) |>
  slice_max(order_by = seconds, n = 1, with_ties = FALSE) |>
  ungroup() |>
  mutate(
    alive_difference = ct_alive - t_alive,
    alive_advantage = case_when(
      alive_difference > 0 ~ "CT has more alive",
      alive_difference < 0 ~ "T has more alive",
      alive_difference == 0 ~ "Equal alive players",
      TRUE ~ NA_character_
    )
  )

alive_outcome_30s <- state_at_30s |>
  filter(!is.na(ct_win), !is.na(alive_advantage)) |>
  group_by(alive_advantage) |>
  summarise(
    rounds = n(),
    ct_win_pct = 100 * mean(ct_win, na.rm = TRUE),
    .groups = "drop"
  )

print(alive_outcome_30s)
save_table(alive_outcome_30s, "04_2_alive_advantage_at_30s.csv")

# 4.3 Equipment and economy advantage -------------------------

economy_summary <- round_states_enriched |>
  mutate(
    equipment_difference = ct_equipment - t_equipment,
    money_difference = ct_money - t_money
  ) |>
  group_by(match_id, round_num) |>
  # Use a snapshot near the 30-second mark, where available
  filter(seconds <= 30) |>
  slice_max(order_by = seconds, n = 1, with_ties = FALSE) |>
  ungroup() |>
  filter(
    !is.na(ct_win),
    !is.na(equipment_difference),
    !is.na(money_difference)
  ) |>
  mutate(
    equipment_advantage = case_when(
      equipment_difference > 0 ~ "CT higher equipment",
      equipment_difference < 0 ~ "T higher equipment",
      equipment_difference == 0 ~ "Equal equipment"
    )
  ) |>
  group_by(equipment_advantage) |>
  summarise(
    rounds = n(),
    ct_win_pct = 100 * mean(ct_win, na.rm = TRUE),
    mean_equipment_difference = mean(equipment_difference, na.rm = TRUE),
    mean_money_difference = mean(money_difference, na.rm = TRUE),
    .groups = "drop"
  )

print(economy_summary)
save_table(economy_summary, "04_3_equipment_advantage.csv")

# 4.4 Health and armor advantage ------------------------------

health_armor_summary <- round_states_enriched |>
  mutate(
    hp_difference = ct_hp - t_hp,
    armor_difference = ct_armor - t_armor
  ) |>
  group_by(match_id, round_num) |>
  filter(seconds <= 30) |>
  slice_max(order_by = seconds, n = 1, with_ties = FALSE) |>
  ungroup() |>
  filter(!is.na(ct_win)) |>
  mutate(
    hp_advantage = case_when(
      hp_difference > 0 ~ "CT higher HP",
      hp_difference < 0 ~ "T higher HP",
      hp_difference == 0 ~ "Equal HP",
      TRUE ~ NA_character_
    )
  ) |>
  group_by(hp_advantage) |>
  summarise(
    rounds = n(),
    ct_win_pct = 100 * mean(ct_win, na.rm = TRUE),
    mean_hp_difference = mean(hp_difference, na.rm = TRUE),
    mean_armor_difference = mean(armor_difference, na.rm = TRUE),
    .groups = "drop"
  )

print(health_armor_summary)
save_table(health_armor_summary, "04_4_health_armor_advantage.csv")


# ============================================================
# FINISHED
# ============================================================

cat(
  "\nAnalysis complete. Tables and plots were saved in:\n",
  normalizePath(output_dir, winslash = "/", mustWork = FALSE),
  "\n"
)
