shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded;

uniform vec4 grid_color : source_color = vec4(0.098, 0.890, 0.890, 1.0);
uniform float cell_size = 1.0;
uniform float line_width = 0.035;
uniform float base_alpha = 0.15;
uniform float line_alpha = 0.90;
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

void fragment() {
	float line = grid_line(world_position.xz);
	float pulse = 0.92 + 0.08 * sin(TIME * 2.094395);

	vec3 node_offset = world_position - NODE_POSITION_WORLD;
	float sweep = fract(TIME / scan_period);
	float scan_center = mix(-scan_distance * 0.5, scan_distance * 0.5, sweep);
	float scan = 1.0 - smoothstep(0.0, scan_half_width, abs(node_offset.z - scan_center));

	float glow = (0.25 + line * emission_strength + scan * 0.75) * pulse;
	ALBEDO = grid_color.rgb * (0.32 + line * 0.68 + scan * 0.22);
	EMISSION = grid_color.rgb * glow;
	ALPHA = clamp(mix(base_alpha + scan * 0.10, line_alpha, line), 0.0, 0.95);
}
