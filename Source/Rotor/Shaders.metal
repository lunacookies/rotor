#include <metal_common>
#include <metal_stdlib>

struct RasterizerData
{
	float4 position [[position]];
	float2 texture_coordinates;
};

vertex RasterizerData
VertexShader(uint vertex_id [[vertex_id]], uint instance_id [[instance_id]],
        constant float2 *positions, constant float2 *origins, constant float2 *sizes,
        constant float2 *texture_origins, constant float2 *texture_sizes,
        constant float2 *texture_bounds, constant float2 *bounds)
{
	float2 origin_ndc = (origins[instance_id] + sizes[instance_id] / 2) / *bounds * 2 - 1;
	origin_ndc.y *= -1;
	float2 scale = sizes[instance_id] / *bounds;

	RasterizerData result = { 0 };
	result.position = float4(positions[vertex_id] * scale + origin_ndc, 0, 1);

	result.texture_coordinates = (positions[vertex_id] + 1) / 2;
	result.texture_coordinates.y = 1 - result.texture_coordinates.y;
	result.texture_coordinates =
	        result.texture_coordinates * (texture_sizes[instance_id] / *texture_bounds) +
	        (texture_origins[instance_id] / *texture_bounds);

	return result;
}

fragment float4
FragmentShader(RasterizerData data [[stage_in]], metal::texture2d<float> glyph_atlas)
{
	metal::sampler glyph_atlas_sampler(metal::mag_filter::nearest, metal::min_filter::nearest);
	return glyph_atlas.sample(glyph_atlas_sampler, data.texture_coordinates);
}
