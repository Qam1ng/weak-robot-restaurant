# scripts/HUD.gd
extends CanvasLayer

## 这个脚本需要被附加到你的 scenes/HUD.tscn 场景的根节点上。
## 它的工作是在游戏开始时，向全局的 GameManager “注册”自己。

# 确保你的 HUD.tscn 场景中有一个叫做 "InteractionLabel" 的 Label 节点
@onready var interaction_label: Label = $InteractionLabel


func _ready():
	# 1. 检查 GameManager 是否存在 (它已经被 Autoload 了)
	if Engine.has_singleton("GameManager"):
		# 2. 调用 GameManager 的注册函数，把自己 (self) 交给它
		GameManager.register_hud(self)
	else:
		print_rich("[color=red]严重错误[/color]: GameManager 尚未被 Autoload！HUD 无法注册。")

	# 默认隐藏提示标签
	if interaction_label:
		interaction_label.hide()
	else:
		# 确保 InteractionLabel 节点存在
		print_rich("[color=red]HUD 错误[/color]: 找不到名为 'InteractionLabel' 的子节点。请在 HUD.tscn 中添加一个 Label 节点并将其重命名为 'InteractionLabel'。")


## 这是 Carryable.gd 脚本将连接到的“统一函数”
func on_interaction_prompt(show: bool, text: String):
	if not interaction_label:
		print_rich("[color=red]HUD 错误[/color]: 尝试显示提示，但 'InteractionLabel' 不存在。")
		return # 如果标签不存在，直接返回

	if show:
		interaction_label.text = text
		interaction_label.show()
	else:
		interaction_label.hide()
