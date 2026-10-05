@tool
class_name MorphEasing
extends RefCounted
## Compact easing set for morph interpolation.


enum Type {
	LINEAR,
	EASE_IN,
	EASE_OUT,
	EASE_IN_OUT,
	SMOOTH,
	BOUNCE_OUT,
}

enum Mode {
	## Ease the blend between each pair of keyframes (current behavior).
	BETWEEN_KEYS,
	## Ease the whole timeline playhead, then sample keys linearly.
	GLOBAL_TIMELINE,
}


static func apply(type: Type, t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	match type:
		Type.LINEAR:
			return t
		Type.EASE_IN:
			return t * t * t
		Type.EASE_OUT:
			var u := 1.0 - t
			return 1.0 - u * u * u
		Type.EASE_IN_OUT:
			if t < 0.5:
				return 4.0 * t * t * t
			var u2 := -2.0 * t + 2.0
			return 1.0 - u2 * u2 * u2 * 0.5
		Type.SMOOTH:
			return t * t * (3.0 - 2.0 * t)
		Type.BOUNCE_OUT:
			return _bounce_out(t)
		_:
			return t


static func _bounce_out(t: float) -> float:
	const N1 := 7.5625
	const D1 := 2.75
	if t < 1.0 / D1:
		return N1 * t * t
	if t < 2.0 / D1:
		t -= 1.5 / D1
		return N1 * t * t + 0.75
	if t < 2.5 / D1:
		t -= 2.25 / D1
		return N1 * t * t + 0.9375
	t -= 2.625 / D1
	return N1 * t * t + 0.984375
