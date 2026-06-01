@tool
class_name CodaEditorPreviewController
extends RefCounted

## Editor preview runtime lifecycle: gate registration, project push, gameplay handoff.

const CodaRuntimeScript := preload("res://addons/nexus_coda/runtime/coda_runtime.gd")
const CodaAudioBusSyncGateScript := preload(
	"res://addons/nexus_coda/runtime/coda_audio_bus_sync_gate.gd"
)

var _host: Node = null
var _runtime: CodaRuntime = null
var _pool_exhausted_slot: Callable = Callable()
var _timeline_panel: Node = null
var _player_panel: Node = null


func bind_host(host: Node) -> void:
	_host = host


func bind_panels(timeline_panel: Node, player_panel: Node) -> void:
	_timeline_panel = timeline_panel
	_player_panel = player_panel


func set_pool_exhausted_handler(handler: Callable) -> void:
	_pool_exhausted_slot = handler


func get_runtime() -> CodaRuntime:
	return _runtime


func ensure_runtime() -> CodaRuntime:
	if _runtime != null and is_instance_valid(_runtime):
		return _runtime
	if _host == null:
		return null
	_runtime = CodaRuntimeScript.new() as CodaRuntime
	_runtime.name = "CodaEditorRuntime"
	_runtime.is_editor_preview = true
	_host.add_child(_runtime)
	CodaAudioBusSyncGateScript.register_editor_preview(_runtime.get_instance_id())
	return _runtime


func dispose_runtime() -> void:
	if _runtime != null and is_instance_valid(_runtime):
		if _pool_exhausted_slot.is_valid() and _runtime.voice_pool_exhausted.is_connected(
			_pool_exhausted_slot
		):
			_runtime.voice_pool_exhausted.disconnect(_pool_exhausted_slot)
		_runtime.set_project(null)
		CodaAudioBusSyncGateScript.unregister_editor_preview(_runtime.get_instance_id())
		_runtime.stop_all()
		# During editor shutdown/unload, queued frees may not run.
		_runtime.free()
	_runtime = null
	_host = null
	_timeline_panel = null
	_player_panel = null


func push_project(state: Variant) -> void:
	ensure_runtime()
	if _runtime == null:
		return
	if state is CodaProject:
		_runtime.set_project((state as CodaProject).duplicate_for_playback())
	else:
		_runtime.set_project(state)


func on_event_output_bus_changed(live_event: CodaBrowserNode) -> void:
	if live_event == null:
		return
	var st: Variant = _authoring_state_from_host()
	if st != null:
		push_project(st)
	else:
		ensure_runtime()
	if _runtime == null:
		return
	_runtime.apply_event_output_bus_from_authoring(live_event)


func _authoring_state_from_host() -> Variant:
	if _host == null or not is_instance_valid(_host):
		return null
	if _host.has_method(&"get_authoring_state_for_preview"):
		return _host.call(&"get_authoring_state_for_preview")
	return null


func stop_panel_previews() -> void:
	if _timeline_panel != null and _timeline_panel.has_method(&"stop_all_previews"):
		_timeline_panel.call(&"stop_all_previews")
	if _player_panel != null and _player_panel.has_method(&"stop_current_voice"):
		_player_panel.stop_current_voice()


func stop_runtime_voices() -> void:
	if _runtime != null and is_instance_valid(_runtime):
		_runtime.stop_all()


func on_gameplay_play_started() -> void:
	stop_panel_previews()
	stop_runtime_voices()


func wire_pool_exhausted_signal() -> void:
	if _runtime == null or not is_instance_valid(_runtime):
		return
	if not _pool_exhausted_slot.is_valid():
		return
	if not _runtime.voice_pool_exhausted.is_connected(_pool_exhausted_slot):
		_runtime.voice_pool_exhausted.connect(_pool_exhausted_slot)
