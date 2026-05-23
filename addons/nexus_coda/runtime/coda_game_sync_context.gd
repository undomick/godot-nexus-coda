@tool
class_name CodaGameSyncContext
extends RefCounted

## Callback surface for [CodaGameSyncDispatcher] — real bridge or test mock.

var play_fn: Callable = Callable()
var set_music_fn: Callable = Callable()
var stop_music_fn: Callable = Callable()
var set_parameter_fn: Callable = Callable()
var apply_snapshot_fn: Callable = Callable()
var notify_music_state_fn: Callable = Callable()
var get_slot_handle_fn: Callable = Callable()
var is_alive_fn: Callable = Callable()


static func from_bridge(runtime: CodaRuntime, music: CodaMusicDirector) -> CodaGameSyncContext:
	var ctx := CodaGameSyncContext.new()
	if runtime != null:
		ctx.play_fn = runtime.play
		ctx.set_parameter_fn = runtime.set_parameter
		ctx.apply_snapshot_fn = runtime.apply_snapshot
		ctx.notify_music_state_fn = runtime.notify_music_state_changed
		ctx.is_alive_fn = runtime.is_alive
	if music != null:
		ctx.set_music_fn = music.set_music
		ctx.stop_music_fn = music.stop_music
		ctx.get_slot_handle_fn = music.get_slot_handle
	return ctx
