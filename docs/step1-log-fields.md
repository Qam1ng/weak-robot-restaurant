# Step-1 Log Fields

This document lists the Step-1 log fields currently persisted by the system.

## 1. Help-Request Analytic Log Fields

### 1.1 Request identity and lifecycle
> 用于记录每次求助请求从创建到结束的身份信息和生命周期时间戳。
- `request_id`
- `request_type`
- `status`
- `created_at_ms`
- `updated_at_ms`
- `cooldown_ms`
- `cooldown_until_ms`
- `final_response`
- `final_path`

### 1.2 Context snapshot
> 用于完整保存这次请求发生时的上下文快照，便于后续复算、审计和补充特征提取。
- `context_snapshot.robot.battery_level`
- `context_snapshot.robot.battery_mode`
- `context_snapshot.player.active_tasks`
- `context_snapshot.environment.urgency`
- `context_snapshot.environment.busyness`
- `context_snapshot.environment.slack_ms`
- `context_snapshot.environment.phase_name`
- `context_snapshot.history.acceptance_rate`
- `context_snapshot.history.avg_latency_ms`
- `context_snapshot.personality.tipi_responses`
- `context_snapshot.personality.tipi_scores`
- `context_snapshot.personality.question_count`

### 1.3 Strategy assignment
> 用于记录这次请求被分配到哪一种策略、所处的分层 bucket，以及最终展示的话术。
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

### 1.4 Immediate response
> 用于记录玩家对这次请求的即时响应及其响应耗时。
- `response`
- `response_latency_ms`

### 1.5 Downstream task outcome
> 用于记录这次请求在后续任务层面造成的结果，例如任务是否完成、由谁完成以及分数变化。
- `task_completed`
- `task_failed`
- `delivery_actor`
- `customer_timed_out`
- `score_delta`

### 1.6 Audit fields
> 用于保留调试、复盘和日志拼接所需的辅助字段，不作为老师查看的核心研究变量。
- `payload`
- `experiment`
- `extra`
- `episode_id`
- `event_type`
- `event_seq`
- `timestamp`
- `timestamp_ms`

## 2. Episode Summary Log Fields

> 用于记录每一轮完整服务过程的整体结果摘要，便于做 episode-level 汇总分析。
- `episode_id`
- `timestamp`
- `success`
- `player_helped`
- `help_item`
- `duration_ms`
- `failure_reason`
