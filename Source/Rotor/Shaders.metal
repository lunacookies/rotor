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

#define global static

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
	V4 rasterizer_position_ndc [[position]];
	V3 color;
	V2 texture_coordinates;
	B32 untextured;
};

F32
SRGBLinearFromGamma(F32 x)
{
	if (x <= 0.04045)
	{
		return x / 12.92;
	}
	else
	{
		return metal::pow((x + 0.055) / 1.055, 2.4);
	}
}

constant global V2 quad_positions_ndc[] = {
        {-1, 1},
        {-1, -1},
        {1, 1},
        {1, 1},
        {1, -1},
        {-1, -1},
};

vertex RasterizerData
VertexShader(U32 vertex_id [[vertex_id]], U32 instance_id [[instance_id]], constant Box *boxes,
        constant V2 *texture_bounds, constant V2 *bounds)
{
	RasterizerData result = {0};

	V2 offset = quad_positions_ndc[vertex_id];
	Box box = boxes[instance_id];
	V2 box_origin_rounded = metal::floor(box.origin);
	V2 box_size_rounded = metal::ceil(box.size);

	V2 position = box_origin_rounded + box_size_rounded * ((offset + 1) * 0.5);
	V2 position_ndc = (position / *bounds * 2 - 1) * V2(1, -1);

	result.rasterizer_position_ndc = V4(position_ndc, 0, 1);

	result.texture_coordinates = (offset + 1) / 2;
	result.texture_coordinates =
	        result.texture_coordinates * (box.texture_size / *texture_bounds) +
	        (box.texture_origin / *texture_bounds);

	result.color.r = SRGBLinearFromGamma(box.color.r);
	result.color.g = SRGBLinearFromGamma(box.color.g);
	result.color.b = SRGBLinearFromGamma(box.color.b);

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
