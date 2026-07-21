extends Node
class_name DroneAudio

var motor_audio: AudioStreamPlayer3D
var motor_playback: AudioStreamGeneratorPlayback
var crash_audio: AudioStreamPlayer3D
var crash_playback: AudioStreamGeneratorPlayback
var audio_hz = 44100.0
var motor_phase = 0.0
var audio_enabled: bool = true

func initialize():
	setup_motor_audio()
	setup_crash_audio()

func setup_motor_audio():
	motor_audio = AudioStreamPlayer3D.new()
	var generator = AudioStreamGenerator.new()
	generator.buffer_length = 0.1
	motor_audio.stream = generator
	motor_audio.unit_size = 5.0
	motor_audio.max_distance = 100.0
	get_parent().add_child(motor_audio)
	if audio_enabled:
		motor_audio.play()
	motor_playback = motor_audio.get_stream_playback()

func setup_crash_audio():
	crash_audio = AudioStreamPlayer3D.new()
	var crash_gen = AudioStreamGenerator.new()
	crash_gen.buffer_length = 0.05
	crash_audio.stream = crash_gen
	get_parent().add_child(crash_audio)
	if audio_enabled:
		crash_audio.play()
	crash_playback = crash_audio.get_stream_playback()

func set_audio_enabled(enabled: bool) -> void:
	audio_enabled = enabled
	if motor_audio and is_instance_valid(motor_audio):
		motor_audio.stream_paused = not enabled
		motor_audio.volume_db = 0.0 if enabled else -80.0
		if not enabled:
			motor_audio.stop()
		elif not motor_audio.playing:
			motor_audio.play()
	if crash_audio and is_instance_valid(crash_audio):
		crash_audio.stream_paused = not enabled
		crash_audio.volume_db = 0.0 if enabled else -80.0
		if not enabled:
			crash_audio.stop()
		elif not crash_audio.playing:
			crash_audio.play()

func update_audio(throttle: float):
	if not audio_enabled or not motor_playback:
		return
	
	var n = motor_playback.get_frames_available()
	var freq = 60.0 + (throttle * 120.0)
	var volume = 0.005 + (throttle * 0.015)
	
	while n > 0:
		var sample = sin(motor_phase * TAU)
		sample += sin(motor_phase * 2.0 * TAU) * 0.3
		sample *= volume
		
		if not is_inf(sample) and not is_nan(sample):
			motor_playback.push_frame(Vector2(sample, sample))
		
		motor_phase = fmod(motor_phase + freq / audio_hz, 1.0)
		n -= 1

func play_crash(intensity: float):
	if not audio_enabled or not crash_playback:
		return
	
	var vol = clamp(intensity / 10.0, 0.2, 0.5)
	var frames_to_push = 2205
	
	for i in range(frames_to_push):
		var sample = (randf() * 2.0 - 1.0) * vol
		sample *= (1.0 - float(i) / frames_to_push)
		crash_playback.push_frame(Vector2(sample, sample))
	
	if not crash_audio.playing:
		crash_audio.play()