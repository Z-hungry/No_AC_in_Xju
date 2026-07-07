# 对话UI脚本
extends CanvasLayer

# 节点引用
@onready var panel: Panel = $Panel
@onready var npc_name_label: Label = $Panel/NPCName
@onready var npc_title_label: Label = $Panel/NPCTitle
@onready var dialogue_text: RichTextLabel = $Panel/DialogueText
@onready var player_input: LineEdit = $Panel/PlayerInput
@onready var send_button: Button = $Panel/SendButton
@onready var close_button: Button = $Panel/CloseButton

# 当前对话的NPC
var current_npc_name: String = ""

# 是否正在等待 NPC 回复(等待期间锁定发送,防止 HTTPRequest 撞车)
var waiting_for_reply: bool = false

# API客户端引用
var api_client: Node = null

# 流式回复缓冲
var streaming_response: String = ""

func _ready():
	# 添加到对话系统组
	add_to_group("dialogue_system")

	# 初始隐藏
	visible = false

	# 连接按钮信号
	send_button.pressed.connect(_on_send_button_pressed)
	close_button.pressed.connect(_on_close_button_pressed)
	player_input.text_submitted.connect(_on_text_submitted)

	# 获取API客户端
	api_client = get_node_or_null("/root/APIClient")
	if api_client:
		api_client.chat_response_received.connect(_on_chat_response_received)
		api_client.chat_stream_chunk.connect(_on_chat_stream_chunk)
		api_client.chat_stream_done.connect(_on_chat_stream_done)
		api_client.chat_error.connect(_on_chat_error)

	print("[INFO] 对话UI初始化完成")

# ? 处理对话框快捷键
func _input(event: InputEvent):
	# 如果对话框不可见,不处理
	if not visible:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		# ESC键 - 关闭对话框 
		if event.keycode == KEY_ESCAPE:
			hide_dialogue()
			get_viewport().set_input_as_handled()
			print("[DEBUG] ESC键关闭对话框")
			return

		# 回车键 - 发送消息
		# 注意: LineEdit的text_submitted信号已经处理了回车。
		# 关键: 无论输入框是否有焦点,都必须消费掉回车事件,
		# 否则它会穿透到 player.gd 的 _input,重复触发 start_dialogue 导致对话被清空。
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			# 如果输入框有焦点,LineEdit 的 text_submitted 已负责发送,这里只消费事件
			if player_input.has_focus():
				get_viewport().set_input_as_handled()
				return
			# 否则手动发送
			send_message()
			get_viewport().set_input_as_handled()
			print("[DEBUG] 回车键发送消息")
			return

		# 屏蔽移动键和交互键,防止触发游戏操作 ? WASD键
		if event.keycode in [KEY_E, KEY_SPACE, KEY_W, KEY_A, KEY_S, KEY_D]:
			get_viewport().set_input_as_handled()
			# 只在第一次屏蔽时打印,避免刷屏
			match event.keycode:
				KEY_E:
					print("[DEBUG] 对话框中屏蔽了E键输入")
				KEY_SPACE:
					print("[DEBUG] 对话框中屏蔽了空格键输入")
				KEY_W:
					print("[DEBUG] 对话框中屏蔽了W键输入")
				KEY_A:
					print("[DEBUG] 对话框中屏蔽了A键输入")
				KEY_S:
					print("[DEBUG] 对话框中屏蔽了S键输入")
				KEY_D:
					print("[DEBUG] 对话框中屏蔽了D键输入")

func start_dialogue(npc_name: String):
	"""开始与NPC对话"""
	current_npc_name = npc_name

	# 重置等待状态,确保发送控件可用(避免上一轮残留的锁)
	_set_waiting(false)

	# 通知NPC进入交互状态 (停止移动) 
	var npc = get_npc_by_name(npc_name)
	if npc and npc.has_method("set_interacting"):
		npc.set_interacting(true)

	# 设置NPC信息
	npc_name_label.text = npc_name
	npc_title_label.text = Config.NPC_TITLES.get(npc_name, "")

	# 清空对话内容
	dialogue_text.clear()
	dialogue_text.append_text("[color=gray]与 " + npc_name + " 的对话开始...[/color]\n")

	# 清空输入框
	player_input.text = ""

	# 显示对话框
	show_dialogue()

	# 聚焦输入框
	player_input.grab_focus()

	print("[INFO] 开始对话: ", npc_name)

func show_dialogue():
	"""显示对话框"""
	visible = true

	# 通知玩家进入交互状态 (禁用移动)
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_interacting"):
		player.set_interacting(true)

func hide_dialogue():
	"""隐藏对话框"""
	visible = false

	# 通知NPC退出交互状态 (恢复移动) 
	if current_npc_name != "":
		var npc = get_npc_by_name(current_npc_name)
		if npc and npc.has_method("set_interacting"):
			npc.set_interacting(false)

	current_npc_name = ""

	# 通知玩家退出交互状态 (启用移动)
	var player = get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_interacting"):
		player.set_interacting(false)

func _on_send_button_pressed():
	"""发送按钮点击"""
	send_message()

func _on_text_submitted(_text: String):
	"""输入框回车"""
	send_message()

func send_message():
	"""发送消息"""
	# 上一条还没回复时,禁止再发,避免 HTTPRequest 撞车(ERR_BUSY)
	if waiting_for_reply:
		print("[WARN] 正在等待上一条回复,忽略本次发送")
		return

	var message = player_input.text.strip_edges()

	if message.is_empty():
		return

	if current_npc_name.is_empty():
		print("[ERROR] 没有选择NPC")
		return

	# 显示玩家消息
	dialogue_text.append_text("\n[color=cyan]玩家:[/color] " + message + "\n")

	# 清空输入框
	player_input.text = ""

	# 显示NPC名称(准备接收流式回复)
	dialogue_text.append_text("\n[color=yellow]" + current_npc_name + ":[/color] ")

	# 清空流式缓冲
	streaming_response = ""

	# 加锁并禁用发送控件,直到收到回复或出错
	_set_waiting(true)

	# 发送流式API请求
	if api_client:
		api_client.send_chat_stream(current_npc_name, message)
	else:
		print("[ERROR] API客户端未找到")
		_set_waiting(false)

func _set_waiting(waiting: bool):
	"""设置等待回复状态(锁定/解锁发送)"""
	waiting_for_reply = waiting
	send_button.disabled = waiting
	player_input.editable = not waiting
	if not waiting:
		player_input.grab_focus()

func _on_chat_response_received(npc_name: String, message: String):
	"""收到NPC回复(非流式)"""
	if npc_name.strip_edges() != current_npc_name.strip_edges():
		print("[WARN] 收到回复的NPC(", npc_name, ")与当前对话NPC(", current_npc_name, ")不一致,已忽略")
		return

	dialogue_text.append_text("\n[color=yellow]" + npc_name + ":[/color] " + message + "\n")
	dialogue_text.scroll_to_line(dialogue_text.get_line_count() - 1)
	_set_waiting(false)

	if api_client and api_client.has_method("send_quest_action"):
		api_client.send_quest_action("talk_to_npc", current_npc_name)

func _on_chat_stream_chunk(npc_name: String, chunk: String):
	"""收到流式回复片段(打字机效果)"""
	if npc_name.strip_edges() != current_npc_name.strip_edges():
		return

	streaming_response += chunk
	dialogue_text.append_text(chunk)
	dialogue_text.scroll_to_line(dialogue_text.get_line_count() - 1)

func _on_chat_stream_done(npc_name: String, message: String, title: String):
	"""流式回复完成"""
	if npc_name.strip_edges() != current_npc_name.strip_edges():
		return

	dialogue_text.append_text("\n")
	dialogue_text.scroll_to_line(dialogue_text.get_line_count() - 1)
	_set_waiting(false)

	if api_client and api_client.has_method("send_quest_action"):
		api_client.send_quest_action("talk_to_npc", current_npc_name)

func _on_chat_error(error_message: String):
	"""对话错误"""
	dialogue_text.append_text("[color=red]错误: " + error_message + "[/color]\n")
	# 解锁,允许重试
	_set_waiting(false)

func _on_close_button_pressed():
	"""关闭按钮点击"""
	hide_dialogue()

# ? 根据名字获取NPC节点
func get_npc_by_name(npc_name: String) -> Node:
	"""根据名字获取NPC节点"""
	var npcs = get_tree().get_nodes_in_group("npcs")
	for npc in npcs:
		if npc.npc_name == npc_name:
			return npc
	return null
