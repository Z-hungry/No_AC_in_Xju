extends Node

signal chat_response_received(npc_name: String, message: String)
signal chat_stream_chunk(npc_name: String, chunk: String)
signal chat_stream_done(npc_name: String, message: String, title: String)
signal chat_error(error_message: String)
signal npc_status_received(dialogues: Dictionary)
signal npc_list_received(npcs: Array)
signal quest_list_received(quests: Array)
signal quest_advanced(quest_id: String, quest_completed: bool)

var http_client: HTTPClient = HTTPClient.new()
var waiting_for_reply: bool = false

func _ready():
	print("[INFO] API客户端初始化完成")
	print("[INFO] API_BASE_URL: ", Config.API_BASE_URL)
	print("[INFO] API_CHAT: ", Config.API_CHAT)

func send_chat(npc_name: String, message: String) -> void:
	print("[DEBUG] send_chat 开始: ", npc_name, ", ", message)
	
	if waiting_for_reply:
		print("[WARN] 正在等待上一条回复,忽略本次发送")
		chat_error.emit("上一条还在回复中,请稍候…")
		return

	print("[DEBUG] 设置 waiting_for_reply = true")
	waiting_for_reply = true

	var data = {
		"npc_name": npc_name,
		"message": message
	}
	var json_string = JSON.stringify(data)
	
	print("[API] POST /chat -> ", data)
	
	print("[DEBUG] 获取 Config.API_CHAT...")
	var url = Config.API_CHAT
	print("[API] URL: ", url)
	
	print("[DEBUG] 开始解析URL...")
	var parsed_url = url.parse_url()
	print("[DEBUG] 解析结果: ", parsed_url)
	
	var host = parsed_url["host"]
	var port = parsed_url.get("port", 80)
	var path = parsed_url["path"] + (parsed_url.get("query", "") ? "?" + parsed_url["query"] : "")
	var use_ssl = parsed_url["scheme"] == "https"

	print("[DEBUG] 解析完成: host=", host, " port=", port, " path=", path, " ssl=", use_ssl)

	print("[DEBUG] 调用 _do_chat_request...")
	_do_chat_request(host, port, path, json_string, npc_name, use_ssl)
	print("[DEBUG] send_chat 结束")

func send_chat_stream(npc_name: String, message: String) -> void:
	print("[DEBUG] send_chat_stream 开始: ", npc_name, ", ", message)
	
	if waiting_for_reply:
		print("[WARN] 正在等待上一条回复,忽略本次发送")
		chat_error.emit("上一条还在回复中,请稍候…")
		return

	waiting_for_reply = true

	var data = {
		"npc_name": npc_name,
		"message": message
	}
	var json_string = JSON.stringify(data)
	
	print("[API] POST /chat/stream -> ", data)
	
	var url = Config.API_CHAT_STREAM
	print("[API] URL: ", url)
	
	var parsed_url = url.parse_url()
	var host = parsed_url["host"]
	var port = parsed_url.get("port", 80)
	var path = parsed_url["path"] + (parsed_url.get("query", "") ? "?" + parsed_url["query"] : "")
	var use_ssl = parsed_url["scheme"] == "https"

	print("[DEBUG] 解析完成: host=", host, " port=", port, " path=", path, " ssl=", use_ssl)

	_do_chat_stream_request(host, port, path, json_string, npc_name, use_ssl)
	print("[DEBUG] send_chat_stream 结束")

func _do_chat_request(host: String, port: int, path: String, body: String, npc_name: String, use_ssl: bool):
	http_client.clear()
	
	var err = http_client.connect_to_host(host, port, use_ssl)
	if err != OK:
		print("[ERROR] 连接失败(1): ", err)
		chat_error.emit("连接失败: " + str(err))
		waiting_for_reply = false
		return

	print("[DEBUG] 正在连接到 ", host, ":", port, " ssl=", use_ssl)

	var connect_timeout = 5.0
	var connect_elapsed = 0.0
	
	while connect_elapsed < connect_timeout:
		http_client.poll()
		var status = http_client.get_status()
		if status == HTTPClient.STATUS_CONNECTED:
			print("[DEBUG] 连接成功!")
			break
		elif status == HTTPClient.STATUS_ERROR:
			print("[ERROR] 连接错误: ", http_client.get_error())
			chat_error.emit("连接错误: " + str(http_client.get_error()))
			http_client.close()
			waiting_for_reply = false
			return
		
		await get_tree().create_timer(0.1).timeout
		connect_elapsed += 0.1
	
	if connect_elapsed >= connect_timeout:
		print("[ERROR] 连接超时")
		chat_error.emit("连接超时")
		http_client.close()
		waiting_for_reply = false
		return

	var headers = [
		"Content-Type: application/json",
		"Content-Length: " + str(body.length())
	]
	
	err = http_client.request(HTTPClient.METHOD_POST, path, headers, body.to_utf8())
	if err != OK:
		print("[ERROR] 发送请求失败: ", err)
		chat_error.emit("发送请求失败: " + str(err))
		http_client.close()
		waiting_for_reply = false
		return

	print("[DEBUG] 请求已发送,等待响应...")
	
	await get_tree().create_timer(0.1).timeout
	_poll_response(npc_name)

func _poll_response(npc_name: String):
	var timeout = 60.0
	var elapsed = 0.0

	while elapsed < timeout:
		var status = http_client.get_status()
		
		if status == HTTPClient.STATUS_CONNECTED:
			http_client.poll()
			status = http_client.get_status()
		
		if status == HTTPClient.STATUS_RESPONSE:
			var response_code = http_client.get_response_code()
			print("[DEBUG] 收到响应: HTTP ", response_code)
			
			var body_bytes = http_client.read_response_body()
			var body_str = body_bytes.get_string_from_utf8()
			print("[DEBUG] 响应内容: ", body_str)
			
			http_client.close()
			
			if response_code != 200:
				chat_error.emit("服务器错误: " + str(response_code))
				waiting_for_reply = false
				return
			
			var json = JSON.new()
			if json.parse(body_str) != OK:
				chat_error.emit("响应解析失败")
				waiting_for_reply = false
				return
			
			var response = json.data
			if response.has("success") and response["success"]:
				chat_response_received.emit(response["npc_name"], response["message"])
			else:
				chat_error.emit("对话失败")
			
			waiting_for_reply = false
			return
		
		elif status == HTTPClient.STATUS_ERROR:
			print("[ERROR] HTTP错误: ", http_client.get_error())
			chat_error.emit("HTTP错误: " + str(http_client.get_error()))
			http_client.close()
			waiting_for_reply = false
			return
		
		elif status == HTTPClient.STATUS_DISCONNECTED:
			print("[ERROR] 连接断开")
			chat_error.emit("连接断开")
			waiting_for_reply = false
			return
		
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	
	print("[ERROR] 请求超时")
	http_client.close()
	chat_error.emit("请求超时")
	waiting_for_reply = false

func _do_chat_stream_request(host: String, port: int, path: String, body: String, npc_name: String, use_ssl: bool):
	var stream_client = HTTPClient.new()
	
	var err = stream_client.connect_to_host(host, port, use_ssl)
	if err != OK:
		print("[ERROR] 流式连接失败: ", err)
		chat_error.emit("连接失败: " + str(err))
		waiting_for_reply = false
		return

	print("[DEBUG] 正在连接到 ", host, ":", port, " ssl=", use_ssl)

	var connect_timeout = 5.0
	var connect_elapsed = 0.0
	
	while connect_elapsed < connect_timeout:
		stream_client.poll()
		var status = stream_client.get_status()
		if status == HTTPClient.STATUS_CONNECTED:
			print("[DEBUG] 流式连接成功!")
			break
		elif status == HTTPClient.STATUS_ERROR:
			print("[ERROR] 流式连接错误: ", stream_client.get_error())
			chat_error.emit("连接错误: " + str(stream_client.get_error()))
			stream_client.close()
			waiting_for_reply = false
			return
		
		await get_tree().create_timer(0.05).timeout
		connect_elapsed += 0.05
	
	if connect_elapsed >= connect_timeout:
		print("[ERROR] 流式连接超时")
		chat_error.emit("连接超时")
		stream_client.close()
		waiting_for_reply = false
		return

	var headers = [
		"Content-Type: application/json",
		"Content-Length: " + str(body.length()),
		"Accept: text/event-stream"
	]
	
	err = stream_client.request(HTTPClient.METHOD_POST, path, headers, body.to_utf8())
	if err != OK:
		print("[ERROR] 发送流式请求失败: ", err)
		chat_error.emit("发送请求失败: " + str(err))
		stream_client.close()
		waiting_for_reply = false
		return

	print("[DEBUG] 流式请求已发送,等待响应...")
	
	await get_tree().create_timer(0.05).timeout
	_poll_stream_response(stream_client, npc_name)

func _poll_stream_response(stream_client: HTTPClient, npc_name: String):
	var timeout = 120.0
	var elapsed = 0.0
	var full_response = ""

	while elapsed < timeout:
		var status = stream_client.get_status()
		
		if status == HTTPClient.STATUS_CONNECTED:
			stream_client.poll()
			status = stream_client.get_status()
		
		if status == HTTPClient.STATUS_RESPONSE:
			var response_code = stream_client.get_response_code()
			print("[DEBUG] 收到流式响应: HTTP ", response_code)
			
			if response_code != 200:
				chat_error.emit("服务器错误: " + str(response_code))
				stream_client.close()
				waiting_for_reply = false
				return
			
			while stream_client.is_response_body_readable():
				var chunk_bytes = stream_client.read_response_body_chunk()
				if chunk_bytes.size() > 0:
					var chunk_str = chunk_bytes.get_string_from_utf8()
					var lines = chunk_str.split("\n")
					for line in lines:
						if line.begins_with("data: "):
							var json_str = line.substr(6)
							var json = JSON.new()
							if json.parse(json_str) == OK:
								var data = json.data
								if data.has("chunk") and data["chunk"]:
									print("[DEBUG] 收到流式数据: ", data["chunk"])
									chat_stream_chunk.emit(npc_name, data["chunk"])
								if data.has("done") and data["done"]:
									if data.has("error"):
										chat_error.emit(data["error"])
									else:
										if data.has("message"):
											full_response = data["message"]
											var title = data.get("title", "")
											chat_stream_done.emit(npc_name, full_response, title)
										print("[DEBUG] 流式传输完成")
									stream_client.close()
									waiting_for_reply = false
									return
		
		elif status == HTTPClient.STATUS_BODY:
			while stream_client.is_response_body_readable():
				var chunk_bytes = stream_client.read_response_body_chunk()
				if chunk_bytes.size() > 0:
					var chunk_str = chunk_bytes.get_string_from_utf8()
					var lines = chunk_str.split("\n")
					for line in lines:
						if line.begins_with("data: "):
							var json_str = line.substr(6)
							var json = JSON.new()
							if json.parse(json_str) == OK:
								var data = json.data
								if data.has("chunk") and data["chunk"]:
									print("[DEBUG] 收到流式数据: ", data["chunk"])
									chat_stream_chunk.emit(npc_name, data["chunk"])
								if data.has("done") and data["done"]:
									if data.has("error"):
										chat_error.emit(data["error"])
									else:
										if data.has("message"):
											full_response = data["message"]
											var title = data.get("title", "")
											chat_stream_done.emit(npc_name, full_response, title)
										print("[DEBUG] 流式传输完成")
									stream_client.close()
									waiting_for_reply = false
									return

		elif status == HTTPClient.STATUS_ERROR:
			print("[ERROR] 流式HTTP错误: ", stream_client.get_error())
			chat_error.emit("HTTP错误: " + str(stream_client.get_error()))
			stream_client.close()
			waiting_for_reply = false
			return
		
		elif status == HTTPClient.STATUS_DISCONNECTED:
			print("[ERROR] 流式连接断开")
			chat_error.emit("连接断开")
			stream_client.close()
			waiting_for_reply = false
			return
		
		await get_tree().create_timer(0.01).timeout
		elapsed += 0.01
	
	print("[ERROR] 流式请求超时")
	stream_client.close()
	chat_error.emit("请求超时")
	waiting_for_reply = false

func get_npc_status() -> void:
	var url = Config.API_NPC_STATUS
	var parsed_url = url.parse_url()
	var host = parsed_url["host"]
	var port = parsed_url.get("port", 80)
	var path = parsed_url["path"]
	var use_ssl = parsed_url["scheme"] == "https"

	var client = HTTPClient.new()
	var err = client.connect_to_host(host, port, use_ssl)
	if err != OK:
		print("[ERROR] 获取NPC状态连接失败: ", err)
		return

	err = client.request(HTTPClient.METHOD_GET, path, [])
	if err != OK:
		print("[ERROR] 获取NPC状态请求失败: ", err)
		client.close()
		return

	call_deferred("_poll_status_response", client)

func _poll_status_response(client: HTTPClient):
	var timeout = 10.0
	var elapsed = 0.0

	while elapsed < timeout:
		var status = client.get_status()
		if status == HTTPClient.STATUS_CONNECTED:
			client.poll()
			status = client.get_status()

		if status == HTTPClient.STATUS_RESPONSE:
			var response_code = client.get_response_code()
			if response_code == 200:
				var body_str = client.read_response_body().get_string_from_utf8()
				var json = JSON.new()
				if json.parse(body_str) == OK:
					var response = json.data
					if response.has("dialogues"):
						npc_status_received.emit(response["dialogues"])
			client.close()
			return

		elif status == HTTPClient.STATUS_ERROR:
			print("[ERROR] NPC状态请求错误")
			client.close()
			return

		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	client.close()

func get_npc_list() -> void:
	var url = Config.API_NPCS
	var parsed_url = url.parse_url()
	var host = parsed_url["host"]
	var port = parsed_url.get("port", 80)
	var path = parsed_url["path"]
	var use_ssl = parsed_url["scheme"] == "https"

	var client = HTTPClient.new()
	var err = client.connect_to_host(host, port, use_ssl)
	if err != OK:
		print("[ERROR] 获取NPC列表连接失败: ", err)
		return

	err = client.request(HTTPClient.METHOD_GET, path, [])
	if err != OK:
		print("[ERROR] 获取NPC列表请求失败: ", err)
		client.close()
		return

	call_deferred("_poll_npcs_response", client)

func _poll_npcs_response(client: HTTPClient):
	var timeout = 10.0
	var elapsed = 0.0

	while elapsed < timeout:
		var status = client.get_status()
		if status == HTTPClient.STATUS_CONNECTED:
			client.poll()
			status = client.get_status()

		if status == HTTPClient.STATUS_RESPONSE:
			var response_code = client.get_response_code()
			if response_code == 200:
				var body_str = client.read_response_body().get_string_from_utf8()
				var json = JSON.new()
				if json.parse(body_str) == OK:
					var response = json.data
					if response.has("npcs"):
						npc_list_received.emit(response["npcs"])
			client.close()
			return

		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	client.close()

func send_quest_action(action_type: String, target: String, player_id: String = "player") -> void:
	var data = {
		"action_type": action_type,
		"target": target,
		"player_id": player_id
	}
	var url = Config.API_QUEST_ACTION
	var parsed_url = url.parse_url()
	var host = parsed_url["host"]
	var port = parsed_url.get("port", 80)
	var path = parsed_url["path"]
	var use_ssl = parsed_url["scheme"] == "https"

	var client = HTTPClient.new()
	var err = client.connect_to_host(host, port, use_ssl)
	if err != OK:
		print("[ERROR] 任务上报连接失败: ", err)
		return

	var body = JSON.stringify(data)
	var headers = [
		"Content-Type: application/json",
		"Content-Length: " + str(body.length())
	]
	
	err = client.request(HTTPClient.METHOD_POST, path, headers, body.to_utf8())
	if err != OK:
		print("[ERROR] 任务上报请求失败: ", err)
		client.close()
		return

	call_deferred("_poll_quest_action_response", client)

func _poll_quest_action_response(client: HTTPClient):
	var timeout = 10.0
	var elapsed = 0.0

	while elapsed < timeout:
		var status = client.get_status()
		if status == HTTPClient.STATUS_CONNECTED:
			client.poll()
			status = client.get_status()

		if status == HTTPClient.STATUS_RESPONSE:
			var response_code = client.get_response_code()
			if response_code == 200:
				var body_str = client.read_response_body().get_string_from_utf8()
				var json = JSON.new()
				if json.parse(body_str) == OK:
					var response = json.data
					if response.has("advanced") and response["advanced"]:
						var quest_id = response.get("quest_id", "")
						var completed = response.get("quest_completed", false)
						quest_advanced.emit(str(quest_id), completed)
			client.close()
			return

		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	client.close()

func get_quest_list(player_id: String = "player") -> void:
	var url = Config.API_QUESTS + "?player_id=" + player_id
	var parsed_url = url.parse_url()
	var host = parsed_url["host"]
	var port = parsed_url.get("port", 80)
	var path = parsed_url["path"] + "?" + parsed_url.get("query", "")
	var use_ssl = parsed_url["scheme"] == "https"

	var client = HTTPClient.new()
	var err = client.connect_to_host(host, port, use_ssl)
	if err != OK:
		print("[ERROR] 获取任务列表连接失败: ", err)
		return

	err = client.request(HTTPClient.METHOD_GET, path, [])
	if err != OK:
		print("[ERROR] 获取任务列表请求失败: ", err)
		client.close()
		return

	call_deferred("_poll_quest_list_response", client)

func _poll_quest_list_response(client: HTTPClient):
	var timeout = 10.0
	var elapsed = 0.0

	while elapsed < timeout:
		var status = client.get_status()
		if status == HTTPClient.STATUS_CONNECTED:
			client.poll()
			status = client.get_status()

		if status == HTTPClient.STATUS_RESPONSE:
			var response_code = client.get_response_code()
			if response_code == 200:
				var body_str = client.read_response_body().get_string_from_utf8()
				var json = JSON.new()
				if json.parse(body_str) == OK:
					var response = json.data
					if response.has("quests"):
						quest_list_received.emit(response["quests"])
			client.close()
			return

		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1

	client.close()
