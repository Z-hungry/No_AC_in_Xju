# 任务日志 UI
# 显示当前任务及目标进度,按 J 切换显隐
extends CanvasLayer

@onready var quest_list: VBoxContainer = $Panel/QuestList

var api_client: Node = null

func _ready():
	add_to_group("quest_log")

	# 默认显示(玩家一进游戏就能看到任务)
	visible = true

	api_client = get_node_or_null("/root/APIClient")
	if api_client:
		api_client.quest_list_received.connect(_on_quest_list_received)
		# 启动拉一次
		api_client.get_quest_list()
	else:
		print("[ERROR] 任务日志: API客户端未找到")

	print("[INFO] 任务日志 UI 初始化完成")

func _input(event: InputEvent):
	# 按 J 键切换任务日志显隐
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_J:
			visible = not visible
			if visible and api_client:
				api_client.get_quest_list()  # 打开时刷新
			get_viewport().set_input_as_handled()

func _on_quest_list_received(quests: Array):
	"""收到任务列表,重建显示"""
	# 清空旧内容
	for child in quest_list.get_children():
		child.queue_free()

	if quests.is_empty():
		var empty = Label.new()
		empty.text = "暂无任务"
		quest_list.add_child(empty)
		return

	for q in quests:
		# 任务标题
		var title = Label.new()
		var status_tag = ""
		if q.status == "completed":
			status_tag = "  (已完成)"
		title.text = "【" + str(q.title) + "】" + status_tag
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		quest_list.add_child(title)

		# 各目标
		var objectives = q.objectives
		for i in range(objectives.size()):
			var obj = objectives[i]
			var mark = ""
			if obj.completed:
				mark = "[✓] "
			elif i == q.current_index and q.status != "completed":
				mark = "[▶] "
			else:
				mark = "[  ] "

			var line = Label.new()
			line.text = "    " + mark + str(obj.description)
			if obj.completed:
				line.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
			quest_list.add_child(line)
