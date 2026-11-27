extends SceneTree
## Writes only the day/night beds and hoof sounds added for this enhancement.

const NEW_SOUNDS := ["birds_loop", "horse_hoof_1", "horse_hoof_2", "horse_hoof_3", "horse_hoof_water"]


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AudioLib.DIR))
	var synth := Synth.new()
	for sound_name in NEW_SOUNDS:
		var path := ProjectSettings.globalize_path(AudioLib.DIR + sound_name + ".wav")
		if FileAccess.file_exists(path):
			print("skip existing ", sound_name)
			continue
		var wav := synth.make(sound_name)
		var err := wav.save_to_wav(path)
		print("%-18s %5.2f s  %s" % [sound_name, wav.get_length(), "ok" if err == OK else "error %d" % err])
	quit()
