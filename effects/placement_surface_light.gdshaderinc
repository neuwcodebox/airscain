uniform vec3 placement_light_center = vec3(0.0);
uniform float placement_light_strength = 0.0;

vec3 placement_surface_light(vec3 world_position, vec3 surface_color) {
	float weight = 1.0 - smoothstep(12.0, 85.0, distance(world_position.xz, placement_light_center.xz));
	return surface_color * vec3(0.90, 0.94, 1.0) * weight * placement_light_strength * 0.65;
}
