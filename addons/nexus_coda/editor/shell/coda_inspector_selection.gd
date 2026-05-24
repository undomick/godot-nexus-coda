@tool
class_name CodaInspectorSelection
extends RefCounted

## Single source of truth for what the Inspector should display.

enum Subject {
	EMPTY,
	BROWSER_EVENT,
	BROWSER_ASSET,
	BROWSER_BANK,
	BROWSER_GAME_SYNC,
	TIMELINE_TRACK,
	TIMELINE_CLIP,
	MIXER_BUS,
}

const FxSectionScript := preload(
	"res://addons/nexus_coda/editor/panels/inspector/coda_inspector_effects_section.gd"
)

var subject: Subject = Subject.EMPTY
var browser_node: CodaBrowserNode = null
var event_id: String = ""
var track_id: String = ""
var clip_id: String = ""
var bus_id: String = ""
var bank_id: String = ""
var game_sync_payload: Dictionary = {}
var project: CodaState = null


func apply(sub: Subject, payload: Dictionary = {}) -> Dictionary:
	subject = sub
	match sub:
		Subject.EMPTY:
			browser_node = null
			event_id = ""
			track_id = ""
			clip_id = ""
			bus_id = ""
			bank_id = ""
			game_sync_payload = {}
		Subject.BROWSER_EVENT:
			browser_node = payload.get("node") as CodaBrowserNode
			event_id = _node_id(browser_node)
			track_id = ""
			clip_id = ""
			bus_id = ""
			bank_id = ""
			game_sync_payload = {}
		Subject.BROWSER_ASSET:
			browser_node = payload.get("node") as CodaBrowserNode
			event_id = ""
			track_id = ""
			clip_id = ""
			bus_id = ""
			bank_id = ""
			game_sync_payload = {}
		Subject.BROWSER_BANK:
			browser_node = null
			bank_id = str(payload.get("bank_id", ""))
			event_id = ""
			track_id = ""
			clip_id = ""
			bus_id = ""
			game_sync_payload = {}
		Subject.BROWSER_GAME_SYNC:
			browser_node = null
			game_sync_payload = (payload.get("payload", {}) as Dictionary).duplicate(true)
			event_id = str(game_sync_payload.get("event_id", ""))
			track_id = ""
			clip_id = ""
			bus_id = ""
			bank_id = ""
		Subject.TIMELINE_TRACK:
			event_id = str(payload.get("event_id", event_id))
			track_id = str(payload.get("track_id", ""))
			clip_id = ""
			bus_id = ""
			bank_id = ""
			game_sync_payload = {}
			_sync_browser_event_node()
		Subject.TIMELINE_CLIP:
			event_id = str(payload.get("event_id", event_id))
			clip_id = str(payload.get("clip_id", ""))
			track_id = str(payload.get("track_id", track_id))
			bus_id = ""
			bank_id = ""
			game_sync_payload = {}
			_sync_browser_event_node()
		Subject.MIXER_BUS:
			browser_node = null
			bus_id = str(payload.get("bus_id", ""))
			event_id = ""
			track_id = ""
			clip_id = ""
			bank_id = ""
			game_sync_payload = {}
	return build_view_state()


func build_view_state() -> Dictionary:
	var state: Dictionary = {
		"subject": subject,
		"title": "",
		"subtitle": "",
		"browser_node": browser_node,
		"show_event_stack": false,
		"show_asset": false,
		"show_bank": false,
		"show_game_sync": false,
		"show_context_banner": false,
		"bank_id": bank_id,
		"game_sync_payload": game_sync_payload,
		"fx_scope": FxSectionScript.FxScope.NONE,
		"event_id": event_id,
		"track_id": track_id,
		"clip_id": clip_id,
		"bus_id": bus_id,
	}

	match subject:
		Subject.EMPTY:
			pass
		Subject.BROWSER_EVENT:
			state["title"] = _node_label(browser_node)
			state["show_event_stack"] = browser_node != null
		Subject.BROWSER_ASSET:
			state["title"] = _node_label(browser_node)
			state["show_asset"] = browser_node != null
		Subject.BROWSER_BANK:
			state["title"] = _bank_title(bank_id)
			state["subtitle"] = "Bank"
			state["show_bank"] = not bank_id.is_empty()
		Subject.BROWSER_GAME_SYNC:
			state["title"] = str(game_sync_payload.get("rule_name", "Game Sync"))
			state["subtitle"] = "Game Sync rule"
			state["show_game_sync"] = not game_sync_payload.is_empty()
		Subject.TIMELINE_TRACK:
			var tr: CodaTimelineTrack = _resolve_track()
			var ev: CodaBrowserNode = browser_node
			state["show_context_banner"] = tr != null
			state["title"] = "Track: %s" % (tr.track_name if tr != null else "Track")
			state["subtitle"] = "in Event: %s" % (ev.name if ev != null else event_id)
			if tr != null:
				state["fx_scope"] = FxSectionScript.FxScope.TIMELINE_TRACK
		Subject.TIMELINE_CLIP:
			var clip: CodaTimelineClip = _resolve_clip()
			var tr2: CodaTimelineTrack = _resolve_track()
			var ev2: CodaBrowserNode = browser_node
			state["show_context_banner"] = clip != null
			var clip_label: String = (
				clip.audio_path.get_file() if clip != null and not clip.audio_path.is_empty() else "Clip"
			)
			state["title"] = "Clip: %s" % clip_label
			var crumbs: PackedStringArray = PackedStringArray()
			if tr2 != null:
				crumbs.append(tr2.track_name)
			if ev2 != null:
				crumbs.append(ev2.name)
			state["subtitle"] = " · ".join(crumbs) if not crumbs.is_empty() else ""
			if clip != null:
				state["fx_scope"] = FxSectionScript.FxScope.TIMELINE_CLIP
		Subject.MIXER_BUS:
			var bus: CodaBus = _resolve_bus()
			state["show_context_banner"] = bus != null
			state["title"] = "Bus: %s" % (bus.bus_name if bus != null else "Bus")
			state["subtitle"] = "Mixer output bus"
			if bus != null:
				state["fx_scope"] = FxSectionScript.FxScope.BUS

	return state


func _sync_browser_event_node() -> void:
	if project == null or event_id.is_empty():
		return
	browser_node = project.events_root.find_by_id(event_id)


func _resolve_track() -> CodaTimelineTrack:
	if project == null or event_id.is_empty() or track_id.is_empty():
		return null
	var node: CodaBrowserNode = project.events_root.find_by_id(event_id)
	if node == null or node.event_timeline == null:
		return null
	return node.event_timeline.find_track(track_id)


func _resolve_clip() -> CodaTimelineClip:
	if project == null or event_id.is_empty() or clip_id.is_empty():
		return null
	var node: CodaBrowserNode = project.events_root.find_by_id(event_id)
	if node == null or node.event_timeline == null:
		return null
	var info: Dictionary = node.event_timeline.find_clip(clip_id)
	if info.is_empty():
		return null
	return info.get("clip") as CodaTimelineClip


func _resolve_bus() -> CodaBus:
	if project == null or project.bus_root == null or bus_id.is_empty():
		return null
	return project.bus_root.find_by_id(bus_id)


func _bank_title(bid: String) -> String:
	if project == null or bid.is_empty():
		return "Bank"
	var bank: CodaBank = project.find_bank_by_id(bid)
	if bank == null:
		return "Bank"
	return bank.bank_name


static func _node_id(node: CodaBrowserNode) -> String:
	return node.id if node != null else ""


static func _node_label(node: CodaBrowserNode) -> String:
	return node.name if node != null else ""
