# Dialogue audio integration

No recorded voice acting is bundled. Dialogue currently uses subtitles and the existing character gestures. The commander whistle and giant rumble are synthesized placeholders; existing footsteps and combat sounds remain.

Add licensed voice files beneath `assets/audio/voices/` and map exact `Speaker|Full subtitle text` keys to `res://assets/audio/voices/file.wav` paths in `data/dialogue_voices.json`. The dialogue player plays one line at a time, retains its subtitle through the recording duration, stops the current recording on skip, and queues concurrent dialogue requests. Empty or missing mappings retain timed subtitles. Do not put credentials or external API keys in this mapping.
