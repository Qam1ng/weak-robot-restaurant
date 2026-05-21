# Core Experimental Variables and Models

## 1. Core Manipulated Variables

### 1.1 Time structure, busyness, and spawn density by phase
Files: `scripts/TimeManager.gd`, `scripts/CustomerSpawner.gd`

Global settings:
- `real_to_game_ratio = 2.0`
- `start_hour = 6`
- `start_minute = 0`
- `absolute_max_customers = 6`

Core time formula:

```text
game_minutes_per_real_second = real_to_game_ratio × phase_multiplier
```

Default:

```text
game_minutes_per_real_second = 2.0
1 real minute = 120 game minutes = 2 game hours
```

Total per in-game day:

```text
12.0 minutes
```

Phase summary:

| Phase | Clock time | Real-time duration | Busyness | Max active customers | Spawn interval | Batch size |
|---|---|---:|---:|---:|---|---|
| Morning | `06:00–10:00` | `2.0 min` | `1.3` | `4` | `22–38 s` | `1–2` |
| Lunch | `10:00–14:00` | `2.0 min` | `1.6` | `6` | `10–18 s` | `2` |
| Afternoon | `14:00–17:00` | `1.5 min` | `1.3` | `4` | `24–42 s` | `1–2` |
| Dinner | `17:00–23:00` | `3.0 min` | `1.6` | `6` | `9–16 s` | `2` |
| Night | `23:00–06:00` | `3.5 min` | `1.0` | `3` | `36–60 s` | `1` |

The first spawned customer is forced to have a drink order. When formal spawning is re-enabled and the restaurant is empty, the first customer appears immediately.

### 1.2 Drink-order generation
File: `scripts/Customer.gd`

- `drink_order_probability = 0.50`
- first spawned customer is forced to have a drink order

Rule:

```text
drink_required =
  preset_drink exists
  OR force_drink_order = true
  OR rand() < 0.50
```

### 1.3 Service deadlines
File: `scripts/TaskBoard.gd`

- `SERVE_WINDOW_MS = 90_000`
- `DRINK_WINDOW_MS = 60_000`

Interpretation:
- food deadline = `90 s`
- drink deadline = `60 s`

### 1.4 Robot battery and energy pressure
File: `scripts/RobotServer.gd`

- `battery_capacity = 100.0`
- `battery_drain_move_per_sec = 1.0`
- `battery_drain_idle_per_sec = 0.1`
- `battery_charge_per_sec = 14.0`
- `battery_conserve_threshold = 50.0`
- `battery_emergency_threshold = 20.0`
- `EMERGENCY_RECHARGE_RESUME_LEVEL = 55.0`

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

### 1.5 Scoring and failure pressure
File: `scripts/HUD.gd`

- food success = `+2`
- food failure = `-6`
- drink success = `+1`
- drink failure = `-3`
- game-over threshold = `-30`

Formula:

```text
score += 2   for successful food delivery
score -= 6   for failed food delivery
score += 1   for successful drink delivery
score -= 3   for failed drink delivery
```

Game over:

```text
score <= -30
```

## 2. Core Collected Variables

### 2.1 Survey responses and derived personality variables
Files: `scripts/PlayerProfile.gd`, `scripts/HUD.gd`

Collected:
- 10 TIPI responses (`1–7` scale)
- 5 derived Big Five scores
- 6 derived persuasion strategy-affinity scores

Stored profile structure:

```text
{
  tipi_scores,
  question_count,
  strategy_affinity
}
```

### 2.2 Delegation / help-request records
Files: `scripts/HelpRequestManager.gd`, `scripts/EpisodeLogger.gd`

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
- `context_snapshot`
- `episode_id`
- `timestamp`
- `event_type`

These records are the primary source for analyzing delegation behavior.

### 2.3 Episode-level behavioral data
File: `scripts/EpisodeLogger.gd`

Episode summary fields:
- `episode_id`
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

Episode JSON additionally contains:
- action/event stream
- path waypoints
- task identity
- robot movement distance

### 2.4 Task-level gameplay outcomes
Files: `scripts/TaskBoard.gd`, `scripts/HUD.gd`, `scripts/Customer.gd`

Derivable outcome variables:
- completed food tasks
- failed food tasks
- completed drink tasks
- failed drink tasks
- score trajectory
- whether a request was accepted / declined / later
- whether delivery was performed by the player vs. robot
- whether a customer timed out

## 3. Core Models and Formulas

### 3.1 TIPI scoring model
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

### 3.2 Strategy-affinity model from personality
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

### 3.3 Persuasion strategy scoring model
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

Selection rule:

```text
selected_strategy = argmax_s score(s)
```

### 3.4 Task slack model
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

### 3.5 Robot delivery-priority model
File: `scripts/RobotServer.gd`

Robot delivery tasks are prioritized using:

```text
priority_score = slack_ms + distance_to_customer
```

The robot chooses the task with the **minimum** score.

Lower scores are prioritized.

### 3.6 Robot overload / delegation trigger model
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

## 4. Open Methodological Issues

The following table summarizes the parts of the current implementation that are still under-specified, only pilot-tuned, or not yet justified in a paper-ready way.

| Topic | Current value / implementation | Why it is still open | Recommended paper-facing treatment |
|---|---|---|---|
| Robot overload threshold | `robot_handoff_threshold_tasks() = 5` | This is currently a hand-tuned trigger for delegation, not a theory-driven threshold. | Describe it as a **pilot-tuned workload threshold** unless you want to justify it through pretesting. |
| Deadline-based handoff trigger | `DEADLINE_HANDOFF_TRIGGER_MS = 45,000` | This is currently a heuristic urgency cutoff. | Describe it as a **pilot-tuned urgency threshold** or add a pretest-based rationale. |
| Food service deadline | `SERVE_WINDOW_MS = 90,000` | The main-dish deadline appears to be chosen for pacing/balance rather than derived from an external standard. | Present it as a **pilot-calibrated service window**. |
| Drink service deadline | `DRINK_WINDOW_MS = 60,000` | Same issue as above; currently a design calibration rather than a justified experimental constant. | Present it as a **pilot-calibrated service window**. |
| Battery thresholds | `50 / 20 / 55` for conserve / emergency / resume | These thresholds are operationally sensible, but not yet formally justified in the current write-up. | State that they were **chosen to produce visible low-battery delegation pressure without making the robot unusable**. |
| Score weights | `+2 / -6 / +1 / -3` and fail threshold `-30` | These values reflect gameplay balancing and asymmetry between food and drink importance, but are not yet documented as such. | State that scores were **designed to weight food errors more heavily than drink errors** and tuned during pilot balancing. |
| Phase busyness values | `Dinner/Lunch = 1.6`, `Morning/Afternoon = 1.3`, `Night = 1.0` | These are behavior-shaping coefficients, but they are currently author-set rather than empirically fit. | Present them as **phase-dependent demand-pressure coefficients tuned for workload variation across the day**. |
| Drink-order probability | `0.50` plus first-customer forced drink | The probability is currently a design choice to ensure enough player-facing drink activity. | State that it was **set to ensure frequent enough drink-order interaction during the session**. |
| Customer spawn intervals and caps | Phase-specific ranges and maxima in `CustomerSpawner.gd` | These directly shape pacing and congestion, but currently read as engineering settings rather than study parameters. | Describe them as **pilot-tuned pacing parameters controlling perceived busyness across phases**. |
| Episode definition | Robot-centered food-service episode logged in `EpisodeLogger` | This is implied by the code but not yet crisply stated in paper language. | Explicitly define an episode as a **robot food-service attempt associated with one customer main-dish task**. |
| Delegation definition | `HelpRequest` of type `HANDOFF` with user response and resolution path | The code is clear, but the concept should be operationalized in the write-up. | Define delegation as a **robot-initiated handoff request requiring an accept / decline / later response**. |
| Acceptance-rate definition | Derived from `HelpRequestManager` interaction model | The metric exists, but the exact numerator/denominator should be made explicit. | Define it explicitly, e.g. **accepted requests / all surfaced requests** over the analysis window. |
| Player-helped definition | Episode outcome flag set when the player assists item flow | The meaning is implicit in code and logs but should be stated explicitly. | Define it as **whether the player materially assisted the robot’s service episode through item exchange or takeover**. |
| Trial vs. formal session boundary | Trial session is scripted and precedes formal Day 1 | Trial events are behaviorally different and should not be mixed casually into formal-session analysis. | State explicitly that the **trial session is excluded from formal behavioral analysis unless separately analyzed**. |
| Food/drink coordination rule | Customer starts eating only after food arrives, and if drink was ordered, after drink also arrives | This is a behavioral design choice, not an assumed real-world truth. | State it as an **implemented customer-state rule** rather than a realism claim. |
| Dialogue-generation architecture | Rule-based persuasion policy with optional LLM surface realization and fallback templates | Without explanation, readers may incorrectly assume a fully generative dialogue system. | Describe it as a **rule-based persuasion engine with optional LLM-based wording realization**. |
