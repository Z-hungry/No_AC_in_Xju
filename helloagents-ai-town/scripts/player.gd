# 玩家控制脚本
extends CharacterBody2D

# 移动速度
@export var speed: float = 200.0

# 当前可交互的NPC
var nearby_npc: Node = null

# 当前可交互的物体
var nearby_interactable: Node = null

# 交互状态 (交互时禁用移动)
var is_interacting: bool = false

# 节点引用
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var camera: Camera2D = $Camera2D

# 音效引用 ⭐ 
@onready var interact_sound: AudioStreamPlayer = null  # 交互音效
@onready var running_sound: AudioStreamPlayer = null  # 走路音效

# 走路音效状态 ⭐ 
var is_playing_running_sound: bool = false

func _ready():
	# 添加到player组 (重要!NPC需要通过这个组来识别玩家)
	add_to_group("player")

	# 获取音效节点 (可选,如果不存在也不会报错) ⭐ 
	interact_sound = get_node_or_null("InteractSound")
	running_sound = get_node_or_null("RunningSound")

	if interact_sound:
		print("[INFO] 玩家交互音效已启用")
	else:
		print("[WARN] 玩家没有InteractSound节点,交互音效已禁用")

	if running_sound:
		print("[INFO] 玩家走路音效已启用")
	else:
		print("[WARN] 玩家没有RunningSound节点,走路音效已禁用")

	Config.log_info("玩家初始化完成")
	# 启用相机
	camera.enabled = true
	# 播放默认动画
	if animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation("idle"):
		animated_sprite.play("idle")

func _physics_process(_delta: float):
	# 如果正在交互,禁用移动
	if is_interacting:
		velocity = Vector2.ZERO
		move_and_slide()
		# 播放idle动画
		if animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation("idle"):
			animated_sprite.play("idle")
		# 停止走路音效 ⭐ 
		stop_running_sound()
		return

	# 获取输入方向
	var input_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	# 设置速度
	velocity = input_direction * speed

	# 移动
	move_and_slide()

	# 更新动画和朝向
	update_animation(input_direction)

	# 更新走路音效 ⭐ 
	update_running_sound(input_direction)

func update_animation(direction: Vector2):
	"""更新角色动画 (支持4方向)"""
	if animated_sprite.sprite_frames == null:
		return

	# 根据移动方向播放动画
	if direction.length() > 0:
		# 移动中 - 判断主要方向
		if abs(direction.x) > abs(direction.y):
			# 左右移动
			if direction.x > 0:
				# 向右
				if animated_sprite.sprite_frames.has_animation("walk_right"):
					animated_sprite.play("walk_right")
					animated_sprite.flip_h = false
				elif animated_sprite.sprite_frames.has_animation("walk"):
					animated_sprite.play("walk")
					animated_sprite.flip_h = false
			else:
				# 向左
				if animated_sprite.sprite_frames.has_animation("walk_left"):
					animated_sprite.play("walk_left")
					animated_sprite.flip_h = false
				elif animated_sprite.sprite_frames.has_animation("walk"):
					animated_sprite.play("walk")
					animated_sprite.flip_h = true
		else:
			# 上下移动
			if direction.y > 0:
				# 向下
				if animated_sprite.sprite_frames.has_animation("walk_down"):
					animated_sprite.play("walk_down")
				elif animated_sprite.sprite_frames.has_animation("walk"):
					animated_sprite.play("walk")
			else:
				# 向上
				if animated_sprite.sprite_frames.has_animation("walk_up"):
					animated_sprite.play("walk_up")
				elif animated_sprite.sprite_frames.has_animation("walk"):
					animated_sprite.play("walk")
	else:
		# 静止
		if animated_sprite.sprite_frames.has_animation("idle"):
			animated_sprite.play("idle")

func _input(event: InputEvent):
	# 按E键与NPC交互
	# 检查E键 (KEY_E = 69)
	if event is InputEventKey:
		if event.pressed and not event.echo:
			# 调试: 打印所有按键
			print("[DEBUG] 按键: ", event.keycode, " (E=69, Enter=4194309)")

			if event.keycode == KEY_E or event.keycode == KEY_ENTER or event.is_action_pressed("ui_accept"):
				# 若对话框已打开,忽略交互键,避免回车穿透重复触发 start_dialogue
				var dlg = get_tree().get_first_node_in_group("dialogue_system")
				if dlg != null and dlg.visible:
					return
				print("[DEBUG] 检测到E键, nearby_npc=", nearby_npc, " nearby_interactable=", nearby_interactable)
				# NPC 优先,其次物体
				if nearby_npc != null:
					interact_with_npc()
					print("[INFO] E键触发NPC交互")
				elif nearby_interactable != null:
					interact_with_object()
					print("[INFO] E键触发物体交互")
				else:
					print("[WARN] 附近没有可交互对象")

func interact_with_npc():
	"""与附近的NPC交互"""
	if nearby_npc != null:
		# 播放交互音效 ⭐ 
		if interact_sound:
			interact_sound.play()

		Config.log_info("与NPC交互: " + nearby_npc.npc_name)
		# 发送信号给对话系统
		get_tree().call_group("dialogue_system", "start_dialogue", nearby_npc.npc_name)

func set_nearby_npc(npc: Node):
	"""设置附近的NPC"""
	nearby_npc = npc
	if npc != null:
		print("[INFO] ✅ 进入NPC范围: ", npc.npc_name)
		Config.log_info("进入NPC范围: " + npc.npc_name)
	else:
		print("[INFO] ❌ 离开NPC范围")
		Config.log_info("离开NPC范围")

func interact_with_object():
	"""与附近的物体交互"""
	if nearby_interactable != null:
		if interact_sound:
			interact_sound.play()
		Config.log_info("与物体交互: " + nearby_interactable.get_object_id())
		nearby_interactable.interact()

func set_nearby_interactable(obj: Node):
	"""设置附近的可交互物体"""
	nearby_interactable = obj
	if obj != null:
		print("[INFO] ✅ 进入物体范围: ", obj.get_object_id())
	else:
		print("[INFO] ❌ 离开物体范围")

func get_nearby_interactable() -> Node:
	"""获取附近的可交互物体"""
	return nearby_interactable

func get_nearby_npc() -> Node:
	"""获取附近的NPC"""
	return nearby_npc

func set_interacting(interacting: bool):
	"""设置交互状态"""
	is_interacting = interacting
	if interacting:
		print("[INFO] 🔒 玩家进入交互状态,移动已禁用")
		# 停止走路音效 ⭐ 
		stop_running_sound()
	else:
		print("[INFO] 🔓 玩家退出交互状态,移动已启用")

# ⭐ 更新走路音效
func update_running_sound(direction: Vector2):
	"""更新走路音效"""
	if running_sound == null:
		return

	# 如果正在移动
	if direction.length() > 0:
		# 如果音效还没播放,开始播放
		if not is_playing_running_sound:
			running_sound.play()
			is_playing_running_sound = true
			print("[INFO] 🎵 开始播放走路音效")
	else:
		# 如果停止移动,停止音效
		stop_running_sound()

# ⭐ 停止走路音效
func stop_running_sound():
	"""停止走路音效"""
	if running_sound and is_playing_running_sound:
		running_sound.stop()
		is_playing_running_sound = false
		print("[INFO] 🔇 停止走路音效")
