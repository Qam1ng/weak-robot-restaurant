# Weak Robot Restaurant: Experimental Variables, Models, and Logged Data

This document summarizes the variables currently manipulated in the codebase, the variables currently collected and exported, and the core formulas/models that govern system behavior. It is intended as a technical reference for methods writing and paper preparation.

## 1. Study Structure

The current game flow is:

1. Pre-game questions (TIPI questionnaire)
2. Trial session (tutorial / warm-up)
3. Formal session (Day 1 onward)

The current implementation therefore contains both:
- a **training phase** (`trial session`), and
- a **formal data-collection phase** (`formal session`).

This distinction is important for paper writing, because not all events before the formal session should necessarily be analyzed together with formal gameplay data.

## 2. Manipulated Variables

### 2.1 Dialogue / persuasion configuration
File: `scripts/ExperimentConfig.gd`

Current configurable experimental variables:

- `replay_logging_enabled: bool = true`
- `help_logging_enabled: bool = true`
- `llm_utterance_enabled: bool = true`
- `llm_model: String = "gpt-4o-mini"`
- `llm_temperature: float = 0.4`

### 2.2 Time structure and phase durations
File: `scripts/TimeManager.gd`

#### Core time conversion
- `real_to_game_ratio = 2.0`

This means:

```text
game_minutes_per_real_second = real_to_game_ratio × phase_multiplier
```

At default settings:

```text
game_minutes_per_real_second = 2.0
```

So:

```text
1 real minute = 120 game minutes = 2 game hours
```

#### Day start
- `start_hour = 6`
- `start_minute = 0`

A new day is triggered when the clock returns to `06:00`.

#### Phase schedule
Current phase schedule:

- Morning: `06:00–10:00`
- Lunch: `10:00–14:00`
- Afternoon: `14:00–17:00`
- Dinner: `17:00–23:00`
- Night: `23:00–06:00`

#### Real-time duration per phase
Given the `2.0` ratio, the current effective real durations are:

- Morning (`4` game hours) -> `2.0` minutes
- Lunch (`4` game hours) -> `2.0` minutes
- Afternoon (`3` game hours) -> `1.5` minutes
- Dinner (`6` game hours) -> `3.0` minutes
- Night (`7` game hours) -> `3.5` minutes

Total per in-game day:

```text
2.0 + 2.0 + 1.5 + 3.0 + 3.5 = 12.0 minutes
```

### 2.3 Busyness manipulation by phase
File: `scripts/TimeManager.gd`

Current busyness multipliers:

- Dinner = `1.5`
- Lunch = `1.5`
- Morning = `1.3`
- Afternoon = `1.3`
- Night = `1.1`

Formally:

```text
busyness(phase) =
  1.5  for dinner or lunch
  1.3  for morning or afternoon
  1.1  for night
```

These values affect the robot’s persuasion context and perceived environmental pressure.

### 2.4 Customer spawning manipulation
File: `scripts/CustomerSpawner.gd`

Current phase-specific spawn settings:

| Phase | Max active customers | Spawn interval | Batch size |
|---|---:|---|---|
| Morning | 2 | 30–60 s | 1 |
| Lunch | 5 | 15–25 s | 1–2 |
| Afternoon | 2 | 40–80 s | 1 |
| Dinner | 5 | 12–20 s | 1–2 |
| Night | 0 | 999 s | 0 |

Other parameters:

- `absolute_max_customers = 5`
- the first spawned customer is forced to have a drink order
- after spawning is re-enabled, if there are no active customers, the first formal-session customer appears immediately

### 2.5 Drink-order probability manipulation
File: `scripts/Customer.gd`

- `drink_order_probability = 0.50`
- `force_drink_order = false` by default
- the first spawned customer is forced to have a drink via the spawner

Current drink-order rule:

```text
drink_required =
  preset_drink exists
  OR force_drink_order = true
  OR rand() < 0.50
```

So under normal formal gameplay:
- first spawned customer: guaranteed drink order
- later customers: `50%` drink probability

### 2.6 Robot battery manipulation
File: `scripts/RobotServer.gd`

Battery parameters:

- `battery_capacity = 100.0`
- `battery_level = 100.0` initially
- `battery_drain_move_per_sec = 1.0`
- `battery_drain_idle_per_sec = 0.1`
- `battery_charge_per_sec = 14.0`
- `battery_conserve_threshold = 50.0`
- `battery_emergency_threshold = 20.0`
- `EMERGENCY_RECHARGE_RESUME_LEVEL = 55.0`

Interpretation:
- moving: lose `1.0` percentage point per second
- idle: lose `0.1` percentage point per second
- charging: gain `14.0` percentage points per second

Battery update rule:

```text
battery_level(t + dt) = battery_level(t) - drain_rate × dt + charge_rate × dt
```

with:

```text
drain_rate = 1.0 if moving
           = 0.1 if idle
charge_rate = 14.0 if charging, else 0
```

### 2.7 Scoring manipulation
File: `scripts/HUD.gd`

Current score rule:

- food success = `+2`
- food failure = `-6`
- drink success = `+1`
- drink failure = `-3`
- game-over threshold = `-30`

Formally:

```text
score += 2   for successful food delivery
score -= 6   for failed food delivery
score += 1   for successful drink delivery
score -= 3   for failed drink delivery
```

Game over is triggered when:

```text
score <= -30
```

### 2.8 Task deadlines
File: `scripts/TaskBoard.gd`

Current service windows:

- food serve window: `90,000 ms` (`90 s`)
- drink serve window: `60,000 ms` (`60 s`)

These are currently hard-coded constants:

- `SERVE_WINDOW_MS = 90_000`
- `DRINK_WINDOW_MS = 60_000`

### 2.9 Player inventory constraints
Files: `scripts/HumanServer.gd`, `scripts/RobotServer.gd`

Current player-side handling constraints:

- inventory capacity = `3`
- item TTL in player inventory = `120,000 ms` (`120 s`)
- player interaction radius = `48`
- player pickup-station radius = `72`
- `player_max_active_tasks = 3` (soft threshold; used in persuasion context, not hard blocking)

## 3. Measured / Collected Variables

### 3.1 Survey responses and personality scores
Files: `scripts/PlayerProfile.gd`, `scripts/HUD.gd`

The system collects:
- 10 TIPI responses (`1–7` scale)
- 5 derived Big Five trait scores
- 6 derived persuasion strategy-affinity values

Stored profile structure:

```text
{
  tipi_scores,
  question_count,
  strategy_affinity
}
```

### 3.2 Help-request records
Files: `scripts/HelpRequestManager.gd`, `scripts/EpisodeLogger.gd`

Help-request logs are written to:
- `user://data/help_requests/help_requests.jsonl`

Per-record fields include:
- `request_id`
- `request_type`
- `status`
- `strategy`
- `strategy_scores`
- `dialogue_intent`
- `utterance`
- `response`
- `response_latency_ms`
- `escalation_count`
- `max_escalation`
- `final_response`
- `final_path`
- `payload`
- `robot_instance_id`
- `context_snapshot`
- `experiment`
- `episode_id`
- `timestamp`
- `event_type`

This is the main source for analyzing delegation requests and user responses.

### 3.3 Episode-level behavioral data
File: `scripts/EpisodeLogger.gd`

Episode summary CSV path:
- `user://data/episodes_summary.csv`

CSV columns:

- `episode_id`
- `timestamp`
- `food_item`
- `customer_seat`
- `success`
- `player_helped`
- `help_item`
- `duration_ms`
- `stuck_count`
- `stuck_total_ms`
- `evasion_count`
- `action_count`
- `total_distance`
- `failure_reason`

Episode JSON contains:
- task identity
- success/failure outcome
- player-help flag
- action/event stream
- path waypoints
- robot movement distance
- stuck/evasion/action metrics

### 3.4 Replay events
File: `scripts/EpisodeLogger.gd`

Replay logs are written to:
- `user://data/replay/replay_events.jsonl`

These logs store timestamped replay events, allowing reconstruction of key interaction steps.

### 3.5 Formal gameplay outcomes implicitly measurable from tasks
Files: `scripts/TaskBoard.gd`, `scripts/HUD.gd`, `scripts/Customer.gd`

The system also makes it possible to derive:
- number of completed food tasks
- number of failed food tasks
- number of completed drink tasks
- number of failed drink tasks
- player score trajectory
- whether a request was accepted / declined / later
- whether a delivery was performed by the player vs. robot
- whether a customer timed out

## 4. Core Models and Formulas

### 4.1 TIPI scoring model
File: `scripts/PlayerProfile.gd`

Responses are on a `1–7` scale.
Reverse scoring rule:

```text
reverse(x) = 8 - x
```

Trait formulas:

```text
E = (item1 + reverse(item6)) / 2
A = (reverse(item2) + item7) / 2
C = (item3 + reverse(item8)) / 2
N = (item4 + reverse(item9)) / 2
O = (item5 + reverse(item10)) / 2
```

Trait normalization:

```text
normalized_trait = clamp((raw_trait - 4.0) / 3.0, -1.0, 1.0)
```

### 4.2 Strategy-affinity model from personality
File: `scripts/PlayerProfile.gd`

Current weighted affinities:

```text
reciprocity = 0.7 × A
authority   = 0.6 × C
liking      = 0.45 × A + 0.35 × E
commitment  = 0.75 × C
social_proof= 0.6 × E + 0.2 × O
scarcity    = 0.7 × N
```

If the questionnaire is incomplete, all affinities default to `0.0`.

### 4.3 Persuasion strategy scoring model
File: `scripts/PersuasionEngine.gd`

Inputs:
- `urgency`
- `busyness`
- `player.task_load`
- `history.acceptance_rate`
- `history.annoyance`
- `robot.battery_level`
- `robot.battery_mode`
- `personality.strategy_affinity`

Battery pressure:

```text
battery_pressure = clamp((100 - battery_level) / 100, 0, 1)
if battery_mode = emergency: battery_pressure = 1.0
if battery_mode = conserve: battery_pressure = max(battery_pressure, 0.6)
```

Strategy formulas:

```text
scarcity
= 2.2·urgency + 1.8·battery_pressure - 1.2·player_task_load + 0.5·personality_boost

authority
= 1.7·urgency + 1.2·busyness + 1.0·battery_pressure - 1.0·player_task_load + 0.5·personality_boost

commitment
= 1.8·acceptance_rate + 0.6·urgency - 0.6·annoyance - 0.4·player_task_load + 0.5·personality_boost

reciprocity
= 1.2·acceptance_rate + 0.8·(1 - player_task_load) + 0.5·busyness - 0.6·annoyance - 0.5·player_task_load + 0.5·personality_boost

social_proof
= 1.6·busyness + 0.8·urgency - 0.7·player_task_load + 0.5·personality_boost

liking
= 1.4·annoyance + 0.8·(1 - player_task_load) + 0.4·acceptance_rate - 0.3·player_task_load + 0.5·personality_boost
```

The selected strategy is simply the maximum-scoring strategy:

```text
selected_strategy = argmax_s score(s)
```

### 4.4 Task slack model
File: `scripts/TaskBoard.gd`

Current task slack:

```text
slack_ms = deadline_ms - now_ms
```

If no deadline exists, the code returns a large sentinel value:

```text
2,000,000,000
```

which effectively means “not urgent yet.”

### 4.5 Robot delivery-priority model
File: `scripts/RobotServer.gd`

Robot delivery tasks are prioritized using:

```text
priority_score = slack_ms + distance_to_customer
```

The robot chooses the task with the **minimum** score.

This means both urgency and spatial cost jointly determine delivery order.

### 4.6 Robot overload / delegation trigger model
File: `scripts/RobotServer.gd`

Current robot handoff threshold:

```text
robot_handoff_threshold_tasks() = 5
```

A post-order overload-based handoff may be triggered when assigned task count reaches this threshold.

Another deadline-based handoff trigger constant is:

```text
DEADLINE_HANDOFF_TRIGGER_MS = 45,000
```

So tasks whose remaining slack falls below `45 s` become candidates for critical handoff.

## 5. Operational Definitions

To write the paper cleanly, the following operational definitions are consistent with the current code.

### 5.1 What counts as an episode?
An `episode` currently refers to a robot food-service episode logged by `EpisodeLogger`, centered on serving a customer’s main dish.

### 5.2 What counts as player help?
`player_helped = true` is logged when the player provides item-level help within an episode, e.g. handing over or taking over a relevant item during robot execution.

### 5.3 What counts as success vs. failure?
- **Food success**: the food-delivery task is completed.
- **Food failure**: the task times out or the customer leaves before service completion.
- **Drink success**: the drink task is completed.
- **Drink failure**: the drink task times out or otherwise fails.

### 5.4 What counts as a delegation / handoff?
A delegation request is represented by a `HelpRequest` of type `HANDOFF`, and includes:
- robot state/context,
- urgency,
- persuasion strategy,
- a natural-language request utterance,
- user response (`accept`, `decline`, `later`), and
- final resolution path.

## 6. Open Methodological Issues

This section lists the parts of the current implementation that are still under-specified, only pilot-tuned, or not yet justified in a paper-ready way.

### 6.1 Heuristic parameters that currently lack formal justification
The following values are currently engineering constants rather than theory-driven or pre-registered parameters:

- `robot_handoff_threshold_tasks = 5`
- `DEADLINE_HANDOFF_TRIGGER_MS = 45,000`
- `SERVE_WINDOW_MS = 90,000`
- `DRINK_WINDOW_MS = 60,000`
- battery thresholds `50 / 20 / 55`
- score weights `+2 / -6 / +1 / -3`
- busyness values `1.5 / 1.3 / 1.1`
- drink probability `0.50`
- customer spawn intervals and per-phase customer caps

#### Recommended treatment
For each of these, the paper should do one of the following:
- explicitly label it as a **pilot-tuned parameter**, or
- provide a principled rationale (e.g. balancing target difficulty, ecological plausibility, or pretest calibration).

### 6.2 Operational definitions that should be made explicit
The current codebase implies the following constructs, but the paper should define them explicitly:

- what counts as a `delegation` event
- what counts as `acceptance rate`
- what counts as `player helped`
- what counts as an `episode`
- whether `trial session` data are excluded from formal analysis
- whether one customer can contribute multiple analyzable task outcomes

#### Recommended treatment
Add a small operational-definition table in the appendix or methods section so that these quantities are unambiguous.

### 6.3 Internal food/drink coordination logic is behaviorally specific
Current customer logic requires:
- food must arrive before eating begins; and
- if a drink was ordered, drink must also arrive before eating begins.

Formally:

```text
start_eating if and only if
  has_received_food = true
  AND (drink_not_required OR has_received_drink = true)
```

This is a design choice, not a natural law. If the paper discusses customer realism, this rule should be stated explicitly.

### 6.4 Trial session and formal session should be separated analytically
The tutorial/trial session now includes:
- scripted customer flow,
- scripted drink request,
- scripted handoff scenario,
- special gating and prompts.

These events should not be mixed naively with formal-session behavior in analysis.

#### Recommended treatment
For exported data and paper methods, explicitly distinguish:
- trial session events,
- formal session events.

### 6.5 Dialogue generation is hybrid, not fully generative
Dialogue generation currently uses a hybrid approach:
- first create template-level intent and wording,
- optionally call the backend / OpenAI model,
- fallback to template wording on failure.

This means the system is not “LLM-only,” but rather “template + LLM realization + fallback.”

#### Recommended treatment
In the paper, describe the dialogue policy as a **rule-based persuasion model with optional LLM surface realization**, rather than a purely generative dialogue system.

## 7. Recommended Paper-Ready Refinements

To make the study description more rigorous, the following changes would be worthwhile.

### 7.1 Define one explicit independent-variable table
Suggested structure:

| Variable | Type | Levels / Range | Current implementation |
|---|---|---|---|
| LLM utterance | manipulated IV | on / off | implemented |
| Drink probability | environment manipulation | 0.50 | implemented |
| Phase busyness | environment manipulation | 1.1–1.5 | implemented |
| Battery drain | environment manipulation | move 1.0, idle 0.1 | implemented |
| Trial session presence | procedural manipulation | yes | implemented |

### 7.2 Define one dependent-variable table
Suggested DVs:

- acceptance rate of handoff requests
- response latency to handoff requests
- task completion rate
- drink failure rate
- score trajectory
- episode duration
- robot stuck count / evasion count
- total robot path distance
- personality-derived strategy affinity

### 7.3 Explicitly distinguish manipulated vs merely contextual variables
Some current variables are:
- **manipulated** (set by experimenter / code configuration)
- **contextual** (emerge from gameplay)
- **logged outcomes**

This distinction should be explicit in the paper.

## 8. Proposed Short Methods Summary

A compact paper-ready summary of the current system would be:

> Participants complete a pre-game TIPI questionnaire, then enter a brief tutorial session followed by a formal gameplay session. The game simulates a restaurant with time-varying customer demand across five daily phases. The robot autonomously serves main-dish orders and may delegate tasks to the participant when workload, time pressure, or battery constraints increase. Help requests are generated using a persuasion model combining urgency, busyness, player load, interaction history, robot battery state, and personality-derived strategy affinities. The system logs questionnaire responses, help requests, episode metrics, replay events, and task outcomes for later analysis.

## 9. Suggested Next Step

The current codebase is now well enough specified to produce a formal appendix table. The most useful next step would be to derive from this document a cleaner paper-facing version with three tables:

1. manipulated variables
2. dependent / logged variables
3. core formulas and decision rules
