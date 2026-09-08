shader_type spatial;

// World-space triplanar grid. Scale-independent, so a 0.18m stair riser reads as
// a fraction of a grid square no matter how the box was scaled in the scene.

uniform float grid_size = 0.5;
uniform float line_width : hint_range(0.5, 4.0) = 1.2;
uniform vec3 base_color : source_color = vec3(0.46, 0.48, 0.52);
uniform vec3 line_color : source_color = vec3(0.10, 0.11, 0.13);
uniform vec3 tint : source_color = vec3(1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 uv = world_pos / grid_size;
	vec3 d = abs(fract(uv - 0.5) - 0.5) / max(fwidth(uv), vec3(0.0001));
	float line = min(min(d.x, d.y), d.z) / line_width;
	float a = 1.0 - clamp(line, 0.0, 1.0);
	ALBEDO = mix(base_color, line_color, a) * tint;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
}
