shader_type canvas_item;
// Sand cells arrive as an R8 texture (one texel per grain, value = color id, 255 = empty).
// The palette maps ids to the image's exact colors. Sample with nearest filtering.

uniform vec4 palette[16];

void fragment() {
	int id = int(round(texture(TEXTURE, UV).r * 255.0));
	if (id >= 16) {
		COLOR = vec4(0.0);
	} else {
		COLOR = palette[id];
	}
}
