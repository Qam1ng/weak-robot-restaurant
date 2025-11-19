# TaskBus.gd  —— 全局事件总线（Autoload）
extends Node

# 任务结构：用字典即可（id, customer, type, payload, state）
signal customer_new_request(task)
signal robot_claimed(task)
signal robot_failed(task)
signal player_help_completed(task)

func post_customer_request(task: Dictionary) -> void:
	emit_signal("customer_new_request", task)

func post_robot_claimed(task: Dictionary) -> void:
	emit_signal("robot_claimed", task)

func post_robot_failed(task: Dictionary) -> void:
	emit_signal("robot_failed", task)

func post_player_help_completed(task: Dictionary) -> void:
	emit_signal("player_help_completed", task)
