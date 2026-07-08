extends Node
class_name MavlinkBridge

signal heartbeat_received(sys_id: int, comp_id: int)
signal connection_changed(connected: bool)
signal telemetry_sent(payload: Dictionary)
signal control_sent(payload: Dictionary)

@export var enabled: bool = false
@export var listen_port: int = 14550
@export var remote_host: String = "127.0.0.1"
@export var remote_port: int = 14551
@export var control_host: String = "127.0.0.1"
@export var control_port: int = 14551
@export var heartbeat_timeout_sec: float = 3.0
@export var telemetry_rate_hz: float = 20.0

var _socket: PacketPeerUDP
var _control_socket: PacketPeerUDP
var _last_heartbeat_time: float = -9999.0
var _telemetry_accum: float = 0.0
var _connected: bool = false
var _endpoint_set: bool = false

func _ready() -> void:
	if not enabled:
		set_process(false)
		return

	_socket = PacketPeerUDP.new()
	var err := _socket.bind(listen_port)
	if err != OK:
		push_error("MavlinkBridge: failed to bind UDP port %d (err %s)" % [listen_port, err])
		set_process(false)
		return

	_control_socket = PacketPeerUDP.new()
	err = _control_socket.bind(0)
	if err != OK:
		push_error("MavlinkBridge: failed to create outbound control socket (err %s)" % err)
		set_process(false)
		return

	set_process(true)

func set_endpoint(host: String, port: int) -> void:
	remote_host = host
	remote_port = port
	_endpoint_set = true


func is_mavlink_connected() -> bool:
	return _connected

func send_telemetry(payload: Dictionary) -> void:
	if not enabled or _socket == null or not _endpoint_set:
		return

	var packet := JSON.stringify(payload).to_utf8_buffer()
	_socket.set_dest_address(remote_host, remote_port)
	_socket.put_packet(packet)
	telemetry_sent.emit(payload)

func send_control_input(input_vec: Vector4) -> void:
	if not enabled or _control_socket == null:
		return

	var payload := {
		"type": "godot_input",
		"throttle": input_vec.x,
		"yaw": input_vec.y,
		"pitch": input_vec.z,
		"roll": input_vec.w,
		"timestamp_ms": Time.get_ticks_msec()
	}
	var packet := JSON.stringify(payload).to_utf8_buffer()
	_control_socket.set_dest_address(control_host, control_port)
	_control_socket.put_packet(packet)
	control_sent.emit(payload)

func _process(delta: float) -> void:
	if not enabled or _socket == null:
		return

	while _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		var text := packet.get_string_from_utf8()
		var parsed: Variant = JSON.parse_string(text)
		if typeof(parsed) == TYPE_DICTIONARY:
			if parsed.has("heartbeat"):
				_last_heartbeat_time = Time.get_ticks_msec() / 1000.0
				if not _connected:
					_connected = true
					connection_changed.emit(true)
				heartbeat_received.emit(int(parsed.get("sysid", 1)), int(parsed.get("compid", 1)))

	var now := Time.get_ticks_msec() / 1000.0
	var should_be_connected := (now - _last_heartbeat_time) <= heartbeat_timeout_sec
	if should_be_connected != _connected:
		_connected = should_be_connected
		connection_changed.emit(_connected)

	_telemetry_accum += delta
	if _connected and _telemetry_accum >= (1.0 / maxf(telemetry_rate_hz, 0.001)):
		_telemetry_accum = 0.0
		send_telemetry({
			"status": "alive",
			"connected": true,
			"heartbeat_age": now - _last_heartbeat_time
		})
