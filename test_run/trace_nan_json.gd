extends SceneTree

func _init() -> void:
    var cases: Array = [
        {"name": "raw_nan", "fn": func(): JSON.stringify({"v": NAN})},
        {"name": "sanitized", "fn": func(): JSON.stringify({"v": 0.0})},
        {"name": "vector2_nan", "fn": func(): JSON.stringify({"v": Vector2(NAN, 1.0)})},
        {"name": "array_nan", "fn": func(): JSON.stringify([NAN])},
    ]
    for c in cases:
        print("CASE: ", c.name)
        c.fn.call()
    quit()
