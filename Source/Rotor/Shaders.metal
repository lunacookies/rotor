#include <metal_common>
#include <metal_stdlib>

typedef int8_t S8;
typedef int16_t S16;
typedef int32_t S32;
typedef int64_t S64;

typedef uint8_t U8;
typedef uint16_t U16;
typedef uint32_t U32;
typedef uint64_t U64;

typedef float F32;

typedef S8 B8;
typedef S16 B16;
typedef S32 B32;
typedef S64 B64;

typedef float2 V2;
typedef float3 V3;
typedef float4 V4;

struct Box
{
	V3 color;
	V2 origin;
	V2 size;
	V2 texture_origin;
	V2 texture_size;
};

struct RasterizerData
{
	V4 position [[position]];
	V3 color;
	V2 texture_coordinates;
	B32 untextured;
};

vertex RasterizerData
VertexShader(U32 vertex_id [[vertex_id]], U32 instance_id [[instance_id]], constant V2 *positions,
        constant Box *boxes, constant V2 *texture_bounds, constant V2 *bounds)
{
	V2 position = positions[vertex_id];
	Box box = boxes[instance_id];

	V2 origin_ndc = (box.origin + box.size / 2) / *bounds * 2 - 1;
	origin_ndc.y *= -1;
	V2 scale = box.size / *bounds;

	RasterizerData result = { 0 };
	result.position = V4(position * scale + origin_ndc, 0, 1);

	result.texture_coordinates = (position + 1) / 2;
	result.texture_coordinates.y = 1 - result.texture_coordinates.y;
	result.texture_coordinates =
	        result.texture_coordinates * (box.texture_size / *texture_bounds) +
	        (box.texture_origin / *texture_bounds);

	result.color = box.color;
	result.untextured = box.texture_size.x == 0 && box.texture_size.y == 0;

	return result;
}

fragment V4
FragmentShader(RasterizerData data [[stage_in]], metal::texture2d<F32> glyph_atlas)
{
	if (data.untextured)
	{
		return V4(data.color, 1);
	}

	metal::sampler glyph_atlas_sampler(metal::mag_filter::linear, metal::min_filter::linear);
	F32 sample = glyph_atlas.sample(glyph_atlas_sampler, data.texture_coordinates).a;
	return sample * V4(data.color, 1);
}
