extends RefCounted
class_name TestSnapshotBlender

const CodaSnapshotBlenderScript := preload("res://addons/nexus_coda/runtime/coda_snapshot_blender.gd")
const CodaTestRuntimeScript := preload("res://addons/nexus_coda/tests/helpers/coda_test_runtime.gd")


static func run() -> int:
	var failed: int = 0
	failed += _test_instant_apply()
	failed += _test_blend_lerp()
	failed += _test_blend_marks_project_dirty()
	failed += _test_blend_interrupt_commits_previous()
	return failed


static func _test_instant_apply() -> int:
	var state: CodaState = CodaTestRuntimeScript.build_snapshot_state()
	var snap: CodaSnapshot = state.snapshots[0]
	var bus: CodaBus = state.bus_root
	bus.volume_db = 0.0
	var sync_count: Array[int] = [0]
	var blender := CodaSnapshotBlenderScript.new()
	blender.setup(state, func() -> void: sync_count[0] += 1)
	if not blender.apply(snap.id, 0):
		push_error("instant snapshot apply failed")
		return 1
	if abs(bus.volume_db - (-12.0)) > 0.001:
		push_error("instant snapshot should set target volume")
		return 1
	return 0


static func _test_blend_marks_project_dirty() -> int:
	var state: CodaState = CodaTestRuntimeScript.build_snapshot_state()
	var snap: CodaSnapshot = state.snapshots[0]
	var dirty_count: Array[int] = [0]
	state.project_dirty.connect(func() -> void: dirty_count[0] = int(dirty_count[0]) + 1)
	var blender := CodaSnapshotBlenderScript.new()
	blender.setup(state, Callable())
	if not blender.apply(snap.id, 500):
		push_error("blend apply failed for dirty test")
		return 1
	if int(dirty_count[0]) != 1:
		push_error("blended snapshot recall should mark project dirty once at start")
		return 1
	return 0


static func _test_blend_lerp() -> int:
	var state: CodaState = CodaTestRuntimeScript.build_snapshot_state()
	var snap: CodaSnapshot = state.snapshots[0]
	var bus: CodaBus = state.bus_root
	bus.volume_db = 0.0
	var blender := CodaSnapshotBlenderScript.new()
	blender.setup(state, Callable())
	if not blender.apply(snap.id, 1000):
		push_error("blend snapshot apply failed")
		return 1
	blender.tick(0.5)
	var mid_db: float = bus.volume_db
	if mid_db >= -0.001 or mid_db <= -12.0:
		push_error("blend should lerp volume, got %s" % mid_db)
		return 1
	blender.tick(0.6)
	if abs(bus.volume_db - (-12.0)) > 0.001:
		push_error("blend should finish at target volume")
		return 1
	if blender.is_blending():
		push_error("blend should be complete")
		return 1
	return 0


static func _test_blend_interrupt_commits_previous() -> int:
	var state: CodaState = CodaTestRuntimeScript.build_snapshot_state()
	var snap: CodaSnapshot = state.snapshots[0]
	var bus: CodaBus = state.bus_root
	bus.volume_db = 0.0
	bus.mute = false
	var blender := CodaSnapshotBlenderScript.new()
	blender.setup(state, Callable())
	if not blender.apply(snap.id, 1000):
		push_error("first blend apply failed")
		return 1
	blender.tick(0.25)
	var snap2 := CodaSnapshot.new()
	snap2.id = "snap_interrupt"
	snap2.bus_overrides = {
		bus.id: {"volume_db": -24.0, "mute": true, "solo": false, "bypass": false, "send_target_id": ""},
	}
	state.snapshots.append(snap2)
	if not blender.apply(snap2.id, 1000):
		push_error("interrupting blend apply failed")
		return 1
	if abs(bus.volume_db - (-12.0)) > 0.001:
		push_error("interrupted blend should commit the previous snapshot volume")
		return 1
	if bus.mute:
		push_error("interrupted blend should commit the previous snapshot mute state")
		return 1
	return 0
