PARAMETERS \[DRY]:

Timeframe: 01.08.2026 - 11.10.2026

Teams: TOP 10 Between each other \[HLTV]

Games: LAN

Maps: Dust2, Mirage

Snapshots: Every 5 seconds, (320 ticks)

Variables: 

\[In-Game] Side, Coordinates, Health, Round time, Win condition, Economy, Weapons, Utilities, Alive/Dead, X vs. X, C4 Position 

\[Meta] Teams, Players, Player ranking, Team ranking, History

Goal: Round outcome prediction based on position \& other variables

H0: Round outcomes are random and independent on position \& other in-game variables

H1: Round outcomes are predictable and dependent on position \& other in-game variables



DESCRIPTION:



Our data mining research investigates a game of Counter-Strike 2 (CS 2 onwards) by trying to predict the outcome of the round based on player's position on the map and other important factors like health, weapons, team economy, etc. A single map is played until one of the teams win 13 rounds out of 24, or in case of a tie, 12-12, they play additional tie-breaker rounds.  Each map is played differently due to different geometry that produces unique game situations, timings and optimal positions for each side, so in order to predict a round-win outcome all of this must be taken into consideration and can't translate from map to map and must be evaluated for each map separately.



The core premise of why researching CS 2 is particularly intresting is because the players in the game itself operate on limited knowledge under certain fog-of-war and intrisically perform probabilistic estimations about the intentions and the positions of the enemy team. While dueling is a completely mechanical skill, and may take a second to end, estimations about enemy positions and optimal ways to counter them are purely informational and take up the majority of the game. So probabilistic models might shine light not only about some extrinsic qualities of the game, like what factors determine win outcomes the most, but also give insights into how the game is played in itself. Other games also have similar qualities like fog-of-war or prediction of the opposing team's intentions, however, CS 2 is unique in the fact that due to it's digital nature, every event and facet of the game is stored as information and can be extracted as data and reproduced near-verbatim, making it a desirable medium for data mining.



In the game there are two distinct sides, CT (Counter-Terrorists) and T (Terrorists). Round win conditions for each side are different. For Ts it's 1. Planting the bomb at Bombsites and successfully running out the timer of the bomb, 2. Eliminating all CTs. For CTs it's 1. Defusing the planted bomb, 2. Eliminating all Ts, 3. Running out the round timer. Due to this dynamic, Ts are considered and attacking team, and CTs the defending team. Round win-rates are usually more skewed towards CT side on most maps, while some retain equal side win-distribution \[optional: add statistic here].



For our research, we chose to investigate professional games of the Top 10 teams playing each other based on hltv.org CS Rating 3.0 which is, if not one of the most robust rating systems, at least the most widely accepted and used. Hltv.org database evaluates whether the teams at the time of their match were in Top 10 and filters out only these results. Of all types of matches, only LAN (Local Area Network) tournament matches were selected. The timeframe ranges from 2026.08.01 to 2026.10.11, during which 60 overall matches were played, of which great majority of them were BO3 (Best of 3), BO5 rarely, and BO1 once. During these matches, 150 maps overall were played. We've used convenient in-built data filtering options in hltv.org/stats for queries and slicing.



We chose two of the most played maps, Dust2 and Mirage, which, out of 7 maps in the map pool, were played by Top 10 teams 30 times each during set period, which is 40% of the time. Out of all 60 matches, one of these two maps were played 33 times, both of these maps 14, and 13 matches where neither of them were played. Altogether, out of 60 matches, 47 times at least one of the maps were played, which is 78.33%. Other than the popularity, there were other reasons that these two maps were picked that we will go down into below.



Dust2 CT/T round win-rate distribution is 49.7%/50.3% respectively, almost an ideal 50-50 "coin-toss", so to say, and Mirage has greater variance, with 55.8%/44.2% distribution. We find this difference an interesting point of investigation, by trying to see how our model will fare for maps which have side-oriented and side-independent round outcomes. These two maps are well-known in pro-play and have been played for decades, so win-rate distribution isn't a sort of recency-bias, but a well set-in "quality" about the map itself. While analyzing all maps would've been ideal, only two maps were picked because of the sheer amount of data it might've produced and the requirements to handle it all properly, we assumed a more leaner approach that might still investigate the differences between maps.



The reason why above mentioned parameters were chosen is because all of them are expected produce a greater consistency in data, while also removing uninformative randomness. The zero hypothesis of this research is that round outcomes are random and don't depend on positions and other in-game factors, therefore it is required to remove out-of-game random factors as much as possible in order not to conflict the two. As with all games, there's an element of randomness, which must be controlled in order for a game to be considered competetive (i.e. skill-based) and predictable. It is a somewhat desirable quality for a game or a sport to be predictable "on-paper", where quantitative features inform the outcome of the game, and statistics are often used for this reason. 



In CS2, the professional play in general terms is more consistent by nature than public games because of regular team roster, high individual skill, etc. Top 10 teams have greater parity with each other and consistently outperform teams outside Top10. Top 10, no matter the period, are a benchmark of of 'how the game should be played' at the highest skill-level. Same goes for matches played in LAN tournaments as opposed to On-Line games, where match outcomes are less predictable due to poorer connectivity quality and other factors which are harder to define quantitavely, like motivation (due to lesser stakes). A short timeframe of 72 days was chosen due to the ever-changing nature of competetive video games, where some updates might alter the game more drastically. This timeframe also coincides with a recent update to the map-pool, where Cache was added and Overpass was removed, the games start right after a summer player break that followed a Major tournament (IEM Cologne 2026). The recency of the data was chosen more for relevance reasons rather than unique set of quality within the data itself, as in, the findings might be of more importance in the field rather than the findings from data gathered from a few years ago. It should be taken into account that despite all this, some changes within the game, team rosters, tactics, etc. do occur over time and cannot be avoided completely. All of these decisions can be backed more robustly with various separate analyses, but it falls outside the scope due to the constraints of this research and should be considered as expert curation that comes from many years in the field. This doesn't not mean that it shouldn't be questioned or that it is immune to critique. 



In general, many of the decisions were also driven by the fact that our approach will require ML training so we had to narrow it all down before we do that step, so as to not get overwhelmed by sheer amount of data that it might produce, as we assume it might be quite a lot (for instance, in an initial data test, a single map produced 1,600,000 rows of unfiltered tabular info). It is assumed that the amount of possible interactions between variables will be extremely high, and making a dataset more narrow will make it more manageable for the intended scope of our research.



\#METHODOLOGY:



possible training models

Logistic Regression

KNN

XGBoost

MLP

LSTM



https://github.com/markus-wa/demoinfocs-golang \[Go Demo-parser]

https://github.com/pnxenopoulos/awpy \[Python-based demo data analysis]

https://github.com/ratulsarker/CS2\_RoundPrediction \[Deep-Learning, a good example]

https://github.com/Gary2005/cs-net \[Transformer-based round win prediction, predicts movement]

https://github.com/wyn0n0/CSMapWinPredict \[Replay and prediction with a display]



1\. go parser that allows to collate data from demo files based on events. Oriented towards efficiency and speed.

2\. similar to go parser and based on go parser, does splicing and other functions with different semantics, creates dataframes, etc. Perhaps less efficient but more user-friendly, has some features that go parser doesnt. \[check what specifically] 

The question of "Why these two? Why not one or the other?"

3\. CS2\_RoundPrediction. Uses Deep-Learning methods. Unknown license, so for now might only inspect. Can't use deep learning in our project.

4\. Cs-net: Transformer-based path prediction \& game-state forecasting for Counter-Strike 2. 3 key parts: path prediction, spatial-only models, 3D visualizer. Has pretrain functions. Uses 4 second windows. Documentation in Chinese, so unreliable information through translator.

5\. CsMapWinPredict: CS Demo Map is a Counter-Strike 2 replay and win-probability analysis project. It turns .dem recordings into an interactive radar replay, showing match progress alongside round-win estimates based on player status, equipment and the bomb situation. The model uses information available at the current point in the recording, with estimates usually updated about once per second. The prediction target is the current round winner, not the final result of the map or match. Last update 2026-10-18, Mirage-only.

