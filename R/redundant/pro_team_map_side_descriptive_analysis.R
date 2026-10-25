# Descriptive statistics: map, pro team, side, and match/round outcomes
# Input: rounds.csv (one row per round; columns verified from the project file)

library(readr)
library(dplyr)
library(tidyr)
library(stringr)

rounds <- read_csv("../data/analysis/rounds.csv", show_col_types = FALSE)

# Basic cleaning: keep reason_name missing as NA; do not recode it.
rounds_clean <- rounds %>%
  mutate(
    map = as.character(map),
    winner_side = as.character(winner_side),
    winner_team = as.character(winner_team),
    reason_name = as.character(reason_name),
    round_duration_s = as.numeric(round_duration_s),
    is_overtime = as.logical(is_overtime),
    is_pistol_round = as.logical(is_pistol_round)
  ) %>%
  distinct(match_id, round_num, map, .keep_all = TRUE)

# 1) Overall descriptive statistics by map
map_summary <- rounds_clean %>%
  group_by(map) %>%
  summarise(
    matches = n_distinct(match_id),
    rounds = n(),
    mean_round_duration_s = mean(round_duration_s, na.rm = TRUE),
    median_round_duration_s = median(round_duration_s, na.rm = TRUE),
    sd_round_duration_s = sd(round_duration_s, na.rm = TRUE),
    ct_round_wins = sum(winner_side == "counter-terrorist", na.rm = TRUE),
    t_round_wins = sum(winner_side == "terrorist", na.rm = TRUE),
    ct_win_pct = 100 * mean(winner_side == "counter-terrorist", na.rm = TRUE),
    t_win_pct = 100 * mean(winner_side == "terrorist", na.rm = TRUE),
    .groups = "drop"
  )

# 2) Team-by-map-by-side statistics.
# Each round contributes two rows: the CT team and the T team.
team_side_rounds <- bind_rows(
  rounds_clean %>%
    transmute(
      match_id, round_num, map,
      team = ct_team,
      side = "CT",
      side_won = winner_side == "counter-terrorist",
      team_won_round = winner_team == ct_team,
      winner_side, winner_team, reason_name,
      round_duration_s, is_overtime, is_pistol_round
    ),
  rounds_clean %>%
    transmute(
      match_id, round_num, map,
      team = t_team,
      side = "T",
      side_won = winner_side == "terrorist",
      team_won_round = winner_team == t_team,
      winner_side, winner_team, reason_name,
      round_duration_s, is_overtime, is_pistol_round
    )
) %>%
  filter(!is.na(team), team != "")

team_map_side_summary <- team_side_rounds %>%
  group_by(map, team, side) %>%
  summarise(
    matches = n_distinct(match_id),
    rounds_played = n(),
    rounds_won_on_side = sum(side_won, na.rm = TRUE),
    side_round_win_pct = 100 * mean(side_won, na.rm = TRUE),
    mean_round_duration_s = mean(round_duration_s, na.rm = TRUE),
    median_round_duration_s = median(round_duration_s, na.rm = TRUE),
    sd_round_duration_s = sd(round_duration_s, na.rm = TRUE),
    pistol_rounds = sum(is_pistol_round %in% TRUE, na.rm = TRUE),
    overtime_rounds = sum(is_overtime %in% TRUE, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  arrange(map, team, side)

# 3) Round outcomes by map and winning side.
side_outcome_summary <- rounds_clean %>%
  group_by(map, winner_side) %>%
  summarise(
    rounds = n(),
    pct_of_map_rounds = 100 * n() / sum(
      rounds_clean$map == first(map), na.rm = TRUE
    ),
    .groups = "drop"
  )

# 4) Round win conditions by map. NA reason_name remains NA.
win_condition_summary <- rounds_clean %>%
  group_by(map, reason_name) %>%
  summarise(rounds = n(), .groups = "drop_last") %>%
  mutate(pct_of_map_rounds = 100 * rounds / sum(rounds)) %>%
  ungroup()

# 5) Which team won each match/map? This is a descriptive count of round-level
# winner_team values, not a reconstructed match winner.
team_round_outcomes <- rounds_clean %>%
  filter(!is.na(winner_team), winner_team != "") %>%
  count(map, winner_team, name = "rounds_won") %>%
  group_by(map) %>%
  mutate(pct_of_map_rounds_won = 100 * rounds_won / sum(rounds_won)) %>%
  ungroup() %>%
  arrange(map, desc(rounds_won))

# Print summaries
print(map_summary)
print(team_map_side_summary)
print(side_outcome_summary)
print(win_condition_summary)
print(team_round_outcomes)

# Save outputs for later analysis
write_csv(map_summary, "descriptive_map_summary.csv")
write_csv(team_map_side_summary, "../data/analysis/descriptive_team_map_side_summary.csv")
write_csv(side_outcome_summary, "../data/analysis/descriptive_side_outcomes.csv")
write_csv(win_condition_summary, "../data/analysis/descriptive_win_conditions.csv")
write_csv(team_round_outcomes, "../data/analysis/descriptive_team_round_outcomes.csv")

# ============================================================
# DESCRIPTIVE STATISTICS: VISUALISATIONS AND PDF EXPORT
# ============================================================

library(tidyverse)
library(scales)

# Load descriptive statistics CSV files
map_summary <- read_csv("descriptive_map_summary.csv", show_col_types = FALSE)
team_map_side_summary <- read_csv("../data/analysis/descriptive_team_map_side_summary.csv",
                                  show_col_types = FALSE)
side_outcome_summary <- read_csv("../data/analysis/descriptive_side_outcomes.csv",
                                 show_col_types = FALSE)
win_condition_summary <- read_csv("../data/analysis/descriptive_win_conditions.csv",
                                  show_col_types = FALSE)
team_round_outcomes <- read_csv("../data/analysis/descriptive_team_round_outcomes.csv",
                                show_col_types = FALSE)

# 1. Round wins by map and side
map_wins_long <- map_summary %>%
  select(map, ct_round_wins, t_round_wins) %>%
  pivot_longer(
    cols = c(ct_round_wins, t_round_wins),
    names_to = "side",
    values_to = "rounds_won"
  ) %>%
  mutate(
    side = recode(
      side,
      ct_round_wins = "Counter-Terrorist",
      t_round_wins = "Terrorist"
    )
  )

p1 <- ggplot(map_wins_long,
             aes(x = map, y = rounds_won, fill = side)) +
  geom_col(position = "dodge") +
  labs(
    title = "Round Wins by Map and Side",
    x = "Map",
    y = "Rounds Won",
    fill = "Side"
  ) +
  theme_minimal()

# 2. Team performance by map and side
p2 <- ggplot(
  team_map_side_summary,
  aes(x = reorder(team, side_round_win_pct),
      y = side_round_win_pct, fill = side)
) +
  geom_col() +
  coord_flip() +
  facet_wrap(~ map, scales = "free_y") +
  scale_y_continuous(
    labels = label_percent(scale = 1),
    limits = c(0, 100)
  ) +
  labs(
    title = "Pro Team Round-Win Percentage by Map and Side",
    x = "Team",
    y = "Rounds Won on Side (%)",
    fill = "Side"
  ) +
  theme_minimal()

# 3. Round outcomes by map and winning side
p3 <- ggplot(
  side_outcome_summary,
  aes(x = map, y = rounds, fill = winner_side)
) +
  geom_col(position = "dodge") +
  labs(
    title = "Round Outcomes by Map and Winning Side",
    x = "Map",
    y = "Rounds",
    fill = "Winning Side"
  ) +
  theme_minimal()

# 4. Win conditions by map
p4 <- ggplot(
  win_condition_summary,
  aes(x = map, y = pct_of_map_rounds, fill = reason_name)
) +
  geom_col() +
  geom_text(
    aes(label = if_else(
      pct_of_map_rounds >= 4,
      sprintf("%.1f%%", pct_of_map_rounds),
      ""
    )),
    position = position_stack(vjust = 0.5),
    size = 3
  ) +
  scale_y_continuous(
    labels = label_percent(scale = 1),
    limits = c(0, 100),
    expand = c(0, 0)
  ) +
  labs(
    title = "Round-Win Percentage by Map and Win Condition",
    x = "Map",
    y = "Rounds (%)",
    fill = "Win Condition"
  ) +
  theme_minimal()

# 5. Team round wins by map
p5 <- ggplot(
  team_round_outcomes,
  aes(x = reorder(winner_team, rounds_won), y = rounds_won)
) +
  geom_col() +
  coord_flip() +
  facet_wrap(~ map, scales = "free_y") +
  labs(
    title = "Round Wins by Pro Team and Map",
    x = "Team",
    y = "Rounds Won"
  ) +
  theme_minimal()

# Display each plot once
print(p1)
print(p2)
print(p3)
print(p4)
print(p5)

# Export each distinct plot to its own PDF
ggsave("../reports/figures/01_map_round_wins.pdf", plot = p1,
       device = "pdf", width = 11, height = 8.5)

ggsave("../reports/figures/02_team_performance.pdf", plot = p2,
       device = "pdf", width = 14, height = 10)

ggsave("../reports/figures/03_side_outcomes.pdf", plot = p3,
       device = "pdf", width = 11, height = 8.5)

ggsave("../reports/figures/04_win_conditions.pdf", plot = p4,
       device = "pdf", width = 14, height = 8.5)

ggsave("../reports/figures/05_team_round_wins.pdf", plot = p5,
       device = "pdf", width = 14, height = 10)
