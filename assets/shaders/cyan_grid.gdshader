shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

uniform vec4 grid_color : source_color = vec4(0.098, 0.890, 0.890, 1.0);
uniform float cell_size = 1.0;
uniform float line_width = 0.035;
uniform float base_alpha = 0.15;
uniform float line_alpha = 0.90;
uniform float fade_alpha = 1.0;
uniform float distress = 0.0;
uniform float emission_strength = 2.4;
uniform float scan_period = 6.0;
uniform float scan_half_width = 1.65;
uniform float scan_distance = 30.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 world_xz) {
	vec2 grid_uv = world_xz / cell_size;
	vec2 cell = abs(fract(grid_uv) - 0.5);
	float distance_to_line = 0.5 - max(cell.x, cell.y);
	float aa = max(fwidth(grid_uv.x), fwidth(grid_uv.y)) * 1.5;
	return 1.0 - smoothstep(line_width, line_width + aa, distance_to_line);
}

float hash21(vec2 point) {
	return fract(sin(dot(point, vec2(127.1, 311.7))) * 43758.5453123);
}

void fragment() {
	float clamped_distress = clamp(distress, 0.0, 1.0);
	float glitch_clock = floor(TIME * mix(3.0, 22.0, clamped_distress));
	float glitch_noise = hash21(floor(world_position.xz * mix(0.35, 1.65, clamped_distress)) + vec2(glitch_clock));
	float glitch_gate = smoothstep(0.50, 0.96, glitch_noise) * clamped_distress;

	vec2 glitched_xz = world_position.xz + vec2(glitch_gate * 0.18 * sin(TIME * 31.0), 0.0);
	float line = grid_line(glitched_xz);
	float pulse_speed = mix(2.094395, 9.8, clamped_distress);
	float pulse = 0.92 + mix(0.08, 0.29, clamped_distress) * sin(TIME * pulse_speed);
	float flicker = mix(1.0, 0.38 + glitch_noise * 0.92, glitch_gate);

	vec3 node_offset = world_position - NODE_POSITION_WORLD;
	float effective_scan_period = max(0.45, mix(scan_period, scan_period * 0.35, clamped_distress));
	float sweep = fract(TIME / effective_scan_period);
	float scan_center = mix(-scan_distance * 0.5, scan_distance * 0.5, sweep);
	float scan = 1.0 - smoothstep(0.0, scan_half_width, abs(node_offset.z - scan_center));

	float glow = (0.25 + line * emission_strength + scan * 0.75) * pulse * flicker * (1.0 + clamped_distress * 0.55);
	ALBEDO = grid_color.rgb * (0.32 + line * 0.68 + scan * 0.22);
	EMISSION = grid_color.rgb * glow;
	ALPHA = clamp(mix(base_alpha + scan * 0.10, line_alpha, line) * flicker * fade_alpha, 0.0, 0.95);
}
