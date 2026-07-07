# 可交互物体脚本
# 玩家靠近按 E 触发,向后端任务系统上报 interact_object 事件
extends Area2D

# 物体配置(在编辑器里为每个实例配置)
@export var object_id: String = "meeting_room_file"  # 后端匹配用的唯一ID
@export var display_name: String = "需求文件"          # 显示名
@export var one_shot: bool = false                    # 是否只可交互一次

@export var object_id: String = "meeting_room_file"  # 后端匹配用的唯一ID
@export var display_name: String = "需求文件"          # 显示名
@export var one_shot: bool = false                    # 是否只可交互一次

@export var object_id: String = "meeting_room_file"  # 后端匹配用的唯一ID
@export var display_name: String = "需求文件"          # 显示名
@export var one_shot: bool = false                    # 是否只可交互一次

@export var object_id: String = "meeting_room_file"  # 后端匹配用的唯一ID
@export var display_name: String = "需求文件"          # 显示名
@export var one_shot: bool = false                    # 是否只可交互一次
# 节点引用
@onready var name_label: Label = $NameLabel

# 交互提示 (可选节点)
var interaction_hint: Label = null

# 玩家引用
var player: Node = null

# 是否已被交互过 (配合 one_shot)
var used: bool = false

func _ready():
	# 加入 interactables 组,供 player.gd 识别
	add_to_group("interactables")

	# 设置显示名
	if name_label:
		name_label.text = display_name

	# Area2D 自身即检测区
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# 尝试获取交互提示节点 (可选)
	interaction_hint = get_node_or_null("InteractionHint")
	if interaction_hint:
		interaction_hint.text = "按E交互"
		interaction_hint.visible = false

	print("[INFO] 可交互物体初始化: ", object_id)

func _on_body_entered(body: Node2D):
	"""玩家进入交互范围"""
	if body.is_in_group("player"):
		player = body
		print("[INFO] ✅ 玩家进入物体范围: ", object_id)
		if body.has_method("set_nearby_interactable"):
			body.set_nearby_interactable(self)
		if interaction_hint:
			interaction_hint.visible = true

func _on_body_exited(body: Node2D):
	"""玩家离开交互范围"""
	if body.is_in_group("player"):
		print("[INFO] ❌ 玩家离开物体范围: ", object_id)
		if player != null and player.has_method("set_nearby_interactable"):
			player.set_nearby_interactable(null)
		player = null
		if interaction_hint:
			interaction_hint.visible = false

func interact():
	"""玩家按 E 时由 player.gd 调用"""
	if one_shot and used:
		print("[INFO] 物体已交互过(one_shot): ", object_id)
		return
	used = true

	# fire-and-forget 上报后端任务系统
	var api = get_node_or_null("/root/APIClient")
	if api and api.has_method("send_quest_action"):
		api.send_quest_action("interact_object", object_id)

	print("[INFO] 交互物体: ", object_id)

func get_object_id() -> String:
	return object_id
