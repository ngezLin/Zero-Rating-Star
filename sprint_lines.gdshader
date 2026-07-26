shader_type canvas_item;

uniform float lines_count : hint_range(1.0, 500.0) = 180.0;
uniform float threshold : hint_range(0.0, 1.0) = 0.85;
uniform float speed = 25.0;
uniform float sprint_intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 line_color : source_color = vec4(0.0, 0.0, 0.0, 0.4);
uniform float inner_radius : hint_range(0.0, 1.0) = 0.3;
uniform float outer_radius : hint_range(0.0, 1.0) = 0.55;

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void fragment() {
	vec2 center = vec2(0.5, 0.5);
	vec2 uv = UV - center;
	
	float radius = length(uv);
	float angle = atan(uv.y, uv.x);
	
	float angle_id = floor(angle * lines_count);
	float noise = hash(angle_id + floor(TIME * speed));
	
	float line_mask = step(threshold, noise);
	float radial_fade = smoothstep(inner_radius, outer_radius, radius);
	
	float alpha = line_mask * radial_fade * sprint_intensity;
	
	COLOR = vec4(line_color.rgb, line_color.a * alpha);
}
