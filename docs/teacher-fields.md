# Teacher Fields

## 1. Participant-Level Fields

### 1.1 Derived personality fields
> 用于记录由 TIPI 十道题计算得到的五个人格维度分数。
- `trait_O`
- `trait_C`
- `trait_E`
- `trait_A`
- `trait_N`

## 2. Per-Request Context Fields

### 2.1 Request identity and task context
> 用于标识每次机器人发起的请求，以及该请求对应的任务类型、物品需求、触发原因和剩余时间压力。
- `request_id`
- `request_type`
- `task_id`
- `order_kind`
- `item_needed`
- `reason`
- `slack_ms`

### 2.2 Time and workload context
> 用于记录这次请求发生时的时间段和工作负荷状态，包括当前阶段、系统忙碌程度和玩家当前任务数量。
- `phase_name`
- `busyness`
- `urgency`
- `player_active_tasks`

### 2.3 Robot state context
> 用于记录这次请求发生时机器人的关键自身状态，包括当前电量和电量模式。
- `battery_level`
- `battery_mode`

### 2.4 Interaction-history context
> 用于记录在这次请求之前，玩家对机器人求助的历史响应情况，包括接受比例和平均响应时延。
- `acceptance_rate`
- `avg_latency_ms`

## 3. Strategy-Assignment Fields

> 用于记录这次请求被分配到哪一种策略、分配时所处的分层条件，以及实际展示给玩家的话术内容。
- `strategy`
- `assignment_method`
- `assignment_buckets.urgency_bucket`
- `assignment_buckets.busyness_bucket`
- `assignment_buckets.player_active_tasks_bucket`
- `assignment_buckets.battery_mode_bucket`
- `utterance`
- `utterance_source`
- `escalation_count`
- `max_escalation`

## 4. Per-Request Response Fields

> 用于记录玩家对这次请求的直接回应、回应耗时，以及该请求最终是以什么响应路径结束的。
- `response`
- `response_latency_ms`
- `final_response`
- `resolution_path`

## 5. Per-Request Downstream Outcome Fields

> 用于记录玩家回应这次请求之后，对后续任务结果造成的影响，例如任务是否完成、由谁完成，以及分数变化。
- `task_completed`
- `task_failed`
- `delivery_actor`
- `customer_timed_out`
- `score_delta`
