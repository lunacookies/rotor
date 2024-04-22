#include <metal_common>
#include <metal_stdlib>

struct Box
{
	float2 origin;
	float2 size;
	float2 texture_origin;
	float2 texture_size;
	uint32_t color_index;
};

struct RasterizerData
{
	float4 position [[position]];
	float2 texture_coordinates;
	float3 color;
};

vertex RasterizerData
VertexShader(uint vertex_id [[vertex_id]], uint instance_id [[instance_id]],
        constant float2 *positions, constant Box *boxes, constant float2 *texture_bounds,
        constant float3 *colors, constant float2 *bounds)
{
	float2 position = positions[vertex_id];
	Box box = boxes[instance_id];

	float2 origin_ndc = (box.origin + box.size / 2) / *bounds * 2 - 1;
	origin_ndc.y *= -1;
	float2 scale = box.size / *bounds;

	RasterizerData result = { 0 };
	result.position = float4(position * scale + origin_ndc, 0, 1);

	result.texture_coordinates = (position + 1) / 2;
	result.texture_coordinates.y = 1 - result.texture_coordinates.y;
	result.texture_coordinates =
	        result.texture_coordinates * (box.texture_size / *texture_bounds) +
	        (box.texture_origin / *texture_bounds);

	result.color = colors[box.color_index];

	return result;
}

fragment float4
FragmentShader(RasterizerData data [[stage_in]], metal::texture2d<float> glyph_atlas)
{
	metal::sampler glyph_atlas_sampler(metal::mag_filter::linear, metal::min_filter::linear);
	float sample = glyph_atlas.sample(glyph_atlas_sampler, data.texture_coordinates).a;
	return sample * float4(data.color, 1);
}
