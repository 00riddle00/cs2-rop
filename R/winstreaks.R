library(arrow)
library(tidyverse)
test_round <- read_parquet("./data/analysis/rounds.parquet")
offset <- 0
test_round <-  test_round %>% mutate(t_start_streak = 0, ct_start_streak = 0)
for (x in unique(test_round$match_id)){
  temp <- subset(test_round, match_id == x)
  team_ct_start <- temp[1, "ct_team"]
  team_t_start <- temp[1, "t_team"]
  if (team_t_start == temp[1, "winner_team"]){
    test_round[1 + offset, "t_start_streak"] = 1
  }
  else{
    test_round[1 + offset, "ct_start_streak"] = 1
  }
  for (z in 2:nrow(temp)){
    y = z + offset
    if(temp[z, "winner_team"] == temp[z - 1, "winner_team"]) {
      if(temp[z, "winner_team"] == team_t_start){
        test_round[y, "t_start_streak"] = test_round[y - 1, "t_start_streak"] + 1
        test_round[y, "ct_start_streak"] = 0
      }
      else{
        test_round[y, "ct_start_streak"] = test_round[y - 1, "ct_start_streak"] + 1
        test_round[y, "t_start_streak"] = 0
      }
    }
    else{
      if(temp[z, "winner_team"] == team_t_start){
        test_round[y, "t_start_streak"] = 1
      }
      else{
        test_round[y, "ct_start_streak"] = 1
      }
    }
  }
  offset <- offset + nrow(temp)
}
winstreaks <- test_round %>% select(match_id, round_num, ct_team, t_team, t_start_streak, ct_start_streak)
write_csv(winstreaks, "./data/analysis/winstreaks.csv")
