shader_type spatial;
// void vertex() {
// 	// Called for every vertex the material is visible on.
// }

uniform sampler2D TEXTURE;
uniform vec2 SCALE;
uniform vec2 OFFSET;

void fragment() {
	// ALBEDO = texture(TEXTURE, UV-OFFSET).xyz;
	const vec2 DISP = vec2(0.5,0.5); // Displacement to center in order to apply the scale
	ALBEDO = texture(TEXTURE, (UV-DISP)*SCALE+DISP+OFFSET).xyz;
}