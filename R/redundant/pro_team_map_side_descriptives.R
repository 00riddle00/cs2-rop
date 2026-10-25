# ============================================================
# DESCRIPTIVE STATISTICS: VISUALISATIONS AND PDF EXPORT
# ============================================================

library(tidyverse)
library(scales)

# Load descriptive statistics CSV files
map_summary <- read_csv("descriptive_map_summary.csv", show_col_types = FALSE)
team_map_side_summary <- read_csv("descriptive_team_map_side_summary.csv",
                                  show_col_types = FALSE)
side_outcome_summary <- read_csv("descriptive_side_outcomes.csv",
                                 show_col_types = FALSE)
win_condition_summary <- read_csv("descriptive_win_conditions.csv",
                                  show_col_types = FALSE)
team_round_outcomes <- read_csv("descriptive_team_round_outcomes.csv",
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
ggsave("01_map_round_wins.pdf", plot = p1,
       device = "pdf", width = 11, height = 8.5)

ggsave("02_team_performance.pdf", plot = p2,
       device = "pdf", width = 14, height = 10)

ggsave("03_side_outcomes.pdf", plot = p3,
       device = "pdf", width = 11, height = 8.5)

ggsave("04_win_conditions.pdf", plot = p4,
       device = "pdf", width = 14, height = 8.5)

ggsave("05_team_round_wins.pdf", plot = p5,
       device = "pdf", width = 14, height = 10)