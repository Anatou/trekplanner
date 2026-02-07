shader_type spatial;
// void vertex() {
// 	// Called for every vertex the material is visible on.
// }

uniform sampler2D TEXTURE;
uniform vec2 SCALE = vec2(1.0);
uniform vec2 ZOOM = vec2(1.0);
uniform vec2 OFFSET = vec2(0.0);

void fragment() {
	METALLIC = 0.0;
	ROUGHNESS = 1.0;

	const vec2 DISP = vec2(0.5,0.5); // Displacement to center in order to apply the scale
	vec2 new_uv = ((UV-DISP)*SCALE*ZOOM+DISP+OFFSET); 

	if (any(lessThan(new_uv, vec2(0.0))) || any(greaterThan(new_uv, vec2(1.0)))) {
		ALBEDO = vec3(0.0);
	}
	else {
		ALBEDO = pow(texture(TEXTURE, new_uv).rgb, vec3(2)); // boost the contrast
	}
}