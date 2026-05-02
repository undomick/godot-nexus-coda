@tool
extends EditorImportPlugin

const CodaNcodaFileResourceScript := preload("res://addons/nexus_coda/editor/import/coda_ncoda_file_resource.gd")

## Registers `.ncoda` with the editor so FileSystem / import pipeline treat it like other imported assets.

func _get_importer_name() -> String:
	# Bump when import output format changes so EditorFileSystem reimports instead of loading stale `.godot/imported/*.res`.
	return "nexus_coda.ncoda_v2"


func _get_visible_name() -> String:
	return "Nexus Coda Project"


func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(["ncoda"])


func _get_save_extension() -> String:
	return "res"


func _get_resource_type() -> String:
	return "Resource"


func _get_priority() -> float:
	return 1.0


func _get_preset_count() -> int:
	return 1


func _get_preset_name(preset_index: int) -> String:
	return "Default"


func _get_import_options(_path: String, _preset_index: int) -> Array:
	return []


func _import(
	source_file: String,
	save_path: String,
	_options: Dictionary,
	_platform_variants: Array[String],
	_gen_files: Array[String]
) -> Error:
	if not FileAccess.file_exists(source_file):
		return ERR_FILE_NOT_FOUND
	var text: String = FileAccess.get_file_as_string(source_file)
	var res: Resource = CodaNcodaFileResourceScript.new()
	res.set("json_source", text)
	var out_path: String = "%s.%s" % [save_path, _get_save_extension()]
	return ResourceSaver.save(res, out_path)
