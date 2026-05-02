extends Resource

## Snapshot held in `.godot/imported` for editor recognition. Authoring source remains the `.ncoda` JSON file.
## No class_name: imported `.res` must load via script path only (global class lookup fails for cached imports).
@export_multiline var json_source: String = ""
