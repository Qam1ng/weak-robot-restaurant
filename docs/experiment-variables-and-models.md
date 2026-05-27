# Step-1 Data Collection Fields

This document lists only the fields to be collected for Step 1 policy learning.

## 1. Participant-Level Fields

### 1.1 Raw TIPI responses
- `tipi_response_1`
- `tipi_response_2`
- `tipi_response_3`
- `tipi_response_4`
- `tipi_response_5`
- `tipi_response_6`
- `tipi_response_7`
- `tipi_response_8`
- `tipi_response_9`
- `tipi_response_10`

### 1.2 Derived personality fields
- `trait_O`
- `trait_C`
- `trait_E`
- `trait_A`
- `trait_N`
- `question_count`

## 2. Per-Request Context Fields

### 2.1 Request identity and task context
- `request_id`
- `request_type`
- `robot_instance_id`
- `task_id`
- `order_kind`
- `item_needed`
- `reason`
- `slack_ms`

### 2.2 Time and workload context
- `phase_name`
- `phase_is_peak`
- `busyness`
- `urgency`
- `player_active_tasks`
- `player_max_active_tasks`
- `player_task_load`

### 2.3 Robot state context
- `battery_level`
- `battery_mode`
- `waiting_for_help`
- `active_step`

### 2.4 Interaction-history context
- `acceptance_rate`
- `avg_latency_ms`
- `annoyance`

### 2.5 Personality context attached to each request
- `tipi_responses`
- `tipi_scores`
- `question_count`

## 3. Strategy-Assignment Fields

- `strategy`
- `assignment_method`
- `assignment_stratum`
- `assignment_buckets`
- `assignment_buckets.request_type_bucket`
- `assignment_buckets.urgency_bucket`
- `assignment_buckets.busyness_bucket`
- `assignment_buckets.player_load_bucket`
- `assignment_buckets.battery_mode_bucket`
- `message_context`
- `message_context.request_type`
- `message_context.strategy`
- `message_context.urgency_level`
- `message_context.escalation_count`
- `utterance`
- `utterance_source`
- `escalation_count`
- `max_escalation`

## 4. Per-Request Response Fields

- `status`
- `created_at_ms`
- `updated_at_ms`
- `last_prompt_ms`
- `cooldown_ms`
- `cooldown_until_ms`
- `response`
- `response_latency_ms`
- `final_response`
- `final_path`
- `resolution_path`

## 5. Per-Request Downstream Outcome Fields

- `task_completed`
- `task_failed`
- `delivery_actor`
- `customer_timed_out`
- `score_delta`

## 6. Episode-Level Behavioral Fields

- `episode_id`
- `success`
- `failure_reason`
- `player_helped`
- `help_item`
- `duration_ms`
- `stuck_count`
- `stuck_total_ms`
- `evasion_count`
- `action_count`
- `total_distance`
- `food_item`
- `customer_seat`
