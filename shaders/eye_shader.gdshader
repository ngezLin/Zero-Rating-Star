shader_type spatial;

uniform vec4 sclera_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 pupil_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 skin_color : source_color = vec4(0.2, 0.5, 0.8, 1.0);

uniform float pupil_radius : hint_range(0.0, 0.5) = 0.22;
uniform float squint : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 col = sclera_color.rgb;
	
	// Draw circular pupil on the front center of the sphere UV
	vec2 center = vec2(0.5, 0.5);
	
	// Adjust UV mapping: multiply X distance by 2.0 to compensate for sphere horizontal UV stretching (2:1 aspect ratio)
	vec2 uv_dist = UV - center;
	uv_dist.x *= 2.0;
	float dist = length(uv_dist);
	
	if (dist < pupil_radius) {
		col = pupil_color.rgb;
	}
	
	// Eyelids (colored matching the body)
	float top_eyelid = mix(0.0, 0.44, squint);
	float bottom_eyelid = mix(1.0, 0.56, squint);
	
	if (UV.y < top_eyelid || UV.y > bottom_eyelid) {
		col = skin_color.rgb;
	}
	
	ALBEDO = col;
	ROUGHNESS = 0.15;
}
