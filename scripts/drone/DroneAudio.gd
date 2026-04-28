extends Node
class_name DroneAudio

var motor_audio: AudioStreamPlayer3D
var motor_playback: AudioStreamGeneratorPlayback
var crash_audio: AudioStreamPlayer3D
var crash_playback: AudioStreamGeneratorPlayback
var audio_hz = 44100.0
var motor_phase = 0.0

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
	motor_audio.play()
	motor_playback = motor_audio.get_stream_playback()

func setup_crash_audio():
	crash_audio = AudioStreamPlayer3D.new()
	var crash_gen = AudioStreamGenerator.new()
	crash_gen.buffer_length = 0.05
	crash_audio.stream = crash_gen
	get_parent().add_child(crash_audio)
	crash_audio.play()
	crash_playback = crash_audio.get_stream_playback()

func update_audio(throttle: float):
	if not motor_playback:
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
	if not crash_playback:
		return
	
	var vol = clamp(intensity / 10.0, 0.2, 0.5)
	var frames_to_push = 2205
	
	for i in range(frames_to_push):
		var sample = (randf() * 2.0 - 1.0) * vol
		sample *= (1.0 - float(i) / frames_to_push)
		crash_playback.push_frame(Vector2(sample, sample))
	
	if not crash_audio.playing:
		crash_audio.play()