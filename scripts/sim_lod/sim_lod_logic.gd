class_name SimLODLogic
extends RefCounted

const TIER_NEAR := 0
const TIER_MID := 1
const TIER_FAR := 2


static func tier_for_distance(distance_meters: float, near_distance: float = 35.0, far_distance: float = 90.0) -> int:
	if distance_meters < near_distance:
		return TIER_NEAR
	if distance_meters < far_distance:
		return TIER_MID
	return TIER_FAR


static func tier_for_distance_squared(distance_squared: float, near_distance: float = 35.0, far_distance: float = 90.0) -> int:
	if distance_squared < near_distance * near_distance:
		return TIER_NEAR
	if distance_squared < far_distance * far_distance:
		return TIER_MID
	return TIER_FAR


static func promoted_tier(base_tier: int, promoted_until_active: bool, promoted_tier_value: int = TIER_MID) -> int:
	if not promoted_until_active:
		return base_tier
	return mini(base_tier, promoted_tier_value)


static func mid_tick_interval(distance_meters: float, near_distance: float = 35.0, far_distance: float = 90.0) -> int:
	var span := maxf(far_distance - near_distance, 0.001)
	var t := clampf((distance_meters - near_distance) / span, 0.0, 1.0)
	return 2 if t < 0.45 else 3


static func mid_tick_interval_squared(distance_squared: float, near_distance: float = 35.0, far_distance: float = 90.0) -> int:
	var split_distance := near_distance + maxf(far_distance - near_distance, 0.001) * 0.45
	return 2 if distance_squared < split_distance * split_distance else 3


static func motion_delta_scale(step_delta: float, physics_delta: float) -> float:
	if physics_delta <= 0.000001 or step_delta <= 0.0:
		return 1.0
	return step_delta / physics_delta


static func tier_name(tier: int) -> String:
	match tier:
		TIER_NEAR:
			return "NEAR"
		TIER_MID:
			return "MID"
		TIER_FAR:
			return "FAR"
		_:
			return "UNKNOWN"
