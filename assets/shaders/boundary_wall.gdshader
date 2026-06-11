shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 wall_color : source_color = vec4(0.098, 0.890, 0.890, 1.0);
uniform float wall_height = 3.0;
uniform float base_alpha = 0.76;
uniform float fade_alpha = 1.0;
uniform float scanline_count = 18.0;
uniform float scanline_speed = 0.35;
uniform float emission_strength = 3.0;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float height = clamp((local_position.z / wall_height) + 0.5, 0.0, 1.0);
	float top_fade = pow(1.0 - height, 1.35);

	float moving_line = abs(fract(height * scanline_count - TIME * scanline_speed) - 0.5);
	float scanline = 1.0 - smoothstep(0.02, 0.12, moving_line);
	float flicker = 0.93 + 0.07 * sin(TIME * 4.7 + local_position.x * 1.9);
	float shimmer = 0.5 + 0.5 * sin(TIME * 1.6 + local_position.x * 3.4);

	float alpha = (base_alpha + scanline * 0.42 + shimmer * 0.08) * top_fade * flicker;
	ALBEDO = wall_color.rgb * (0.92 + scanline * 0.28);
	EMISSION = wall_color.rgb * (emission_strength + scanline * 2.1 + shimmer * 0.55) * top_fade * fade_alpha;
	ALPHA = clamp(alpha * fade_alpha, 0.0, 0.94);
}
