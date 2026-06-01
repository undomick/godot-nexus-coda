@tool
class_name CodaEditorLifecycle
extends RefCounted

## Unified editor shutdown helpers. During Godot exit or plugin unload, `queue_free()`
## may never run; always detach and `free()` editor-only nodes explicitly.

const CodaTimelineWaveformCacheScript := preload(
	"res://addons/nexus_coda/editor/widgets/timeline/coda_timeline_waveform_cache.gd"
)
const CodaBrowserFolderIconsScript := preload(
	"res://addons/nexus_coda/editor/browser/coda_browser_folder_icons.gd"
)
const CodaAudioStreamCacheScript := preload(
	"res://addons/nexus_coda/runtime/coda_audio_stream_cache.gd"
)
const CodaAudioBusSyncGateScript := preload(
	"res://addons/nexus_coda/runtime/coda_audio_bus_sync_gate.gd"
)


static func clear_editor_static_caches() -> void:
	CodaTimelineWaveformCacheScript.clear_cache()
	CodaBrowserFolderIconsScript.clear_cache()
	CodaAudioStreamCacheScript.clear()
	CodaAudioBusSyncGateScript.reset_for_tests()


static func call_editor_teardown(node: Variant) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Node:
		(node as Node).set_process(false)
	if node.has_method(&"set_process_input"):
		node.call(&"set_process_input", false)
	if node.has_method(&"editor_teardown"):
		node.call(&"editor_teardown")


static func safe_remove_child(parent: Node, child: Node) -> void:
	if parent == null or child == null:
		return
	if not is_instance_valid(parent) or not is_instance_valid(child):
		return
	if child.get_parent() != parent:
		return
	parent.remove_child(child)


static func detach_and_free(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	call_editor_teardown(node)
	# Node.free() detaches from the scene tree; explicit remove_child() during editor
	# shutdown can fail with "parent is busy" / invalid rp_child on MenuBar popups.
	node.free()


static func disconnect_if_connected(sig: Signal, callable: Callable) -> void:
	if callable.is_valid() and sig.is_connected(callable):
		sig.disconnect(callable)
