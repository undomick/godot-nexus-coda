extends RefCounted
class_name TestBusSyncMatrix

const CodaAudioBusSyncGateScript := preload(
	"res://addons/nexus_coda/runtime/coda_audio_bus_sync_gate.gd"
)
const CodaAudioServerWriterScript := preload(
	"res://addons/nexus_coda/runtime/coda_audio_server_writer.gd"
)


static func run() -> int:
	var failed: int = 0
	failed += _test_preview_only()
	failed += _test_gameplay_only()
	failed += _test_editor_play_with_preview()
	failed += _test_mixer_recall_during_preview()
	failed += _test_writer_blocks_during_gameplay()
	return failed


static func _test_preview_only() -> int:
	CodaAudioBusSyncGateScript.reset_for_tests()
	CodaAudioBusSyncGateScript.register_editor_preview(1)
	if not CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.EditorPreview
	):
		push_error("preview-only: editor preview sync should be allowed")
		return 1
	if CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.GameplayAutoload
	):
		push_error("preview-only: gameplay autoload sync should be blocked")
		return 1
	if not CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.EditorMixer
	):
		push_error("preview-only: mixer recall should be allowed")
		return 1
	CodaAudioBusSyncGateScript.reset_for_tests()
	return 0


static func _test_gameplay_only() -> int:
	CodaAudioBusSyncGateScript.reset_for_tests()
	CodaAudioBusSyncGateScript.set_gameplay_active(true)
	if not CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.GameplayAutoload
	):
		push_error("gameplay-only: autoload sync should be allowed")
		return 1
	if CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.EditorPreview
	):
		push_error("gameplay-only: editor preview sync should be blocked")
		return 1
	CodaAudioBusSyncGateScript.reset_for_tests()
	return 0


static func _test_editor_play_with_preview() -> int:
	CodaAudioBusSyncGateScript.reset_for_tests()
	CodaAudioBusSyncGateScript.register_editor_preview(99)
	CodaAudioBusSyncGateScript.set_gameplay_active(true)
	if not CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.GameplayAutoload
	):
		push_error("editor play: gameplay sync should win over preview registration")
		return 1
	if CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.EditorPreview
	):
		push_error("editor play: preview sync should be blocked")
		return 1
	if CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.EditorMixer
	):
		push_error("editor play: mixer recall should be blocked")
		return 1
	CodaAudioBusSyncGateScript.reset_for_tests()
	return 0


static func _test_mixer_recall_during_preview() -> int:
	CodaAudioBusSyncGateScript.reset_for_tests()
	CodaAudioBusSyncGateScript.register_editor_preview(5)
	if not CodaAudioBusSyncGateScript.may_sync_to_audio_server(
		CodaAudioBusSyncGateScript.SyncCaller.EditorMixer
	):
		push_error("mixer recall during preview should be allowed when gameplay inactive")
		return 1
	CodaAudioBusSyncGateScript.unregister_editor_preview(5)
	CodaAudioBusSyncGateScript.reset_for_tests()
	return 0


static func _test_writer_blocks_during_gameplay() -> int:
	CodaAudioBusSyncGateScript.reset_for_tests()
	CodaAudioBusSyncGateScript.set_gameplay_active(true)
	if CodaAudioServerWriterScript.set_bus_volume_db(
		CodaAudioBusSyncGateScript.SyncCaller.EditorPreview, "Master", -12.0
	):
		push_error("writer should not apply editor preview volumes during gameplay")
		return 1
	CodaAudioBusSyncGateScript.reset_for_tests()
	return 0
