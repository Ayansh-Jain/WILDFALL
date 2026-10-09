extends SceneTree
## Regenerates the placeholder sound effects in res://assets/audio/.
## Run from the Game folder:
##   godot --headless --path . -s res://tools/generate_audio.gd


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AudioLib.DIR))
	var synth := Synth.new()
	for sound_name in Synth.SOUNDS:
		var wav := synth.make(sound_name)
		var path := ProjectSettings.globalize_path(AudioLib.DIR + sound_name + ".wav")
		var err := wav.save_to_wav(path)
		print("%-18s %5.2f s  %s" % [sound_name, wav.get_length(), "ok" if err == OK else "error %d" % err])
	quit()
