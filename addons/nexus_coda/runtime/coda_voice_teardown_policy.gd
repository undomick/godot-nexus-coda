@tool
class_name CodaVoiceTeardownPolicy
extends RefCounted

## Timeline voice teardown modes. Wet FX tails run only on dry-stop paths.
##
## | Path              | API                    | FX tail |
## |-------------------|------------------------|---------|
## | Clip/out end      | stop_voices_past_clip_end / stop_voices_dry | yes |
## | Pause preview     | stop_voices_dry        | yes     |
## | stop_all          | stop_voices_dry        | yes     |
## | Layout resync     | stop_voices_dry        | yes     |
## | Seek / loop wrap  | stop_voices (immediate)| no      |
## | Retire / replace  | _teardown_immediate    | no      |

enum Mode {
	DRY_WITH_TAIL,
	IMMEDIATE,
}


static func mode_for_preview_pause() -> int:
	return Mode.DRY_WITH_TAIL


static func mode_for_layout_resync() -> int:
	return Mode.DRY_WITH_TAIL


static func mode_for_stop_all() -> int:
	return Mode.DRY_WITH_TAIL


static func mode_for_seek() -> int:
	return Mode.IMMEDIATE


static func mode_for_loop_wrap() -> int:
	return Mode.IMMEDIATE
