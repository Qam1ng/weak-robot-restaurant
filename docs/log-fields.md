# Log Fields

## 1. Participant Log Fields

### 1.1 Participant identity and metadata
> 用于标识参与者本身，以及关联本次会话和构建版本。
- `participant_id`
- `session_id`
- `created_at`
- `platform`
- `build_version`

### 1.2 Raw TIPI responses
> 用于记录参与者在 TIPI 十个人格题目上的原始作答分数。
- `tipi_responses.tipi_response_1`
- `tipi_responses.tipi_response_2`
- `tipi_responses.tipi_response_3`
- `tipi_responses.tipi_response_4`
- `tipi_responses.tipi_response_5`
- `tipi_responses.tipi_response_6`
- `tipi_responses.tipi_response_7`
- `tipi_responses.tipi_response_8`
- `tipi_responses.tipi_response_9`
- `tipi_responses.tipi_response_10`

### 1.3 Derived personality fields
> 用于记录由 TIPI 十道题计算得到的五个人格维度分数，以及问卷完成情况。
- `tipi_scores.trait_O`
- `tipi_scores.trait_C`
- `tipi_scores.trait_E`
- `tipi_scores.trait_A`
- `tipi_scores.trait_N`
- `question_count`

## 2. Help-Request Log Fields

### 2.1 Request identity and lifecycle
> 用于记录每次求助请求的身份信息、所属会话/回合，以及从创建到结束的生命周期状态。
- `participant_id`
- `session_id`
- `episode_id`
- `request_id`
- `request_type`
- `status`
- `created_at_ms`
- `updated_at_ms`
- `cooldown_ms`
- `cooldown_until_ms`
- `final_response`
- `resolution_path`

### 2.2 Request task context
> 用于记录这次请求对应的是哪一个任务、哪种订单、需要什么物品、为什么发起，以及剩余时间压力。
- `task_id`
- `order_kind`
- `item_needed`
- `reason`
- `slack_ms`

### 2.3 Time and workload context
> 用于记录这次请求发生时的时间段和工作负荷状态，包括阶段、忙碌程度、紧急度和玩家当前任务数。
- `phase_name`
- `busyness`
- `urgency`
- `player_active_tasks`

### 2.4 Robot state context
> 用于记录这次请求发生时机器人的关键自身状态，包括电量和电量模式。
- `battery_level`
- `battery_mode`

### 2.5 Interaction-history context
> 用于记录在这次请求之前，玩家对机器人求助的历史响应情况。
- `acceptance_rate`
- `avg_latency_ms`

### 2.6 Personality context attached to each request
> 用于把参与者的人格测量结果附加到每一次请求上，便于后续分析不同人格条件下哪种策略更有效。
- `trait_O`
- `trait_C`
- `trait_E`
- `trait_A`
- `trait_N`

### 2.7 Strategy assignment
> 用于记录这次请求被分配到哪一种策略、分配时所处的分层 bucket，以及最终展示的话术。
- `strategy`
- `assignment_method`
- `assignment_buckets.request_type_bucket`
- `assignment_buckets.urgency_bucket`
- `assignment_buckets.busyness_bucket`
- `assignment_buckets.player_active_tasks_bucket`
- `assignment_buckets.battery_mode_bucket`
- `utterance`
- `utterance_source`
- `escalation_count`
- `max_escalation`

### 2.8 Immediate response
> 用于记录玩家对这次请求的即时响应及其响应耗时。
- `response`
- `response_latency_ms`

### 2.9 Downstream task outcome
> 用于记录这次请求在后续任务层面造成的结果，例如任务是否完成、由谁完成以及分数变化。
- `task_completed`
- `task_failed`
- `delivery_actor`
- `customer_timed_out`
- `score_delta`

## 3. Episode Summary Log Fields

### 3.1 Episode summary
> 用于记录每一轮完整服务过程的整体结果摘要，便于做 episode-level 汇总分析。
- `participant_id`
- `session_id`
- `episode_id`
- `timestamp`
- `success`
- `player_helped`
- `help_item`
- `duration_ms`
- `failure_reason`
