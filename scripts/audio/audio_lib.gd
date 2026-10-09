class_name AudioLib
extends RefCounted
## Loads sounds from res://assets/audio/<name>.wav, falling back to Synth when a
## file is missing. Replace any .wav with a real recording of the same name.

const DIR := "res://assets/audio/"

static var _instance: AudioLib

var _cache := {}
var _synth: Synth


static func get_instance() -> AudioLib:
	if _instance == null:
		_instance = AudioLib.new()
	return _instance


func get_stream(sound_name: String) -> AudioStream:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var stream: AudioStream = null
	# Use the current procedural mixes for these sounds so a stale generated WAV
	# cannot hide improvements to their synthesis.
	if sound_name in ["water_loop", "waterfall_loop", "footstep_1", "footstep_2", "footstep_3", "footstep_water", "roar"]:
		if _synth == null:
			_synth = Synth.new()
		stream = _synth.make(sound_name)
	var path := DIR + sound_name + ".wav"
	if stream == null and ResourceLoader.exists(path):
		stream = load(path)
		var looping: bool = Synth.SOUNDS.get(sound_name, [null, false])[1]
		if looping and stream is AudioStreamWAV:
			var wav: AudioStreamWAV = stream
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = int(wav.get_length() * wav.mix_rate)
	if stream == null and Synth.SOUNDS.has(sound_name):
		if _synth == null:
			_synth = Synth.new()
		stream = _synth.make(sound_name)
	_cache[sound_name] = stream
	return stream


func footstep(wet: bool) -> AudioStream:
	if wet:
		return get_stream("footstep_water")
	return get_stream("footstep_%d" % randi_range(1, 3))
