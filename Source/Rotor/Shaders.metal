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
	V4 color;
	V2 origin;
	V2 size;
	V2 texture_origin;
	V2 texture_size;
	F32 border_thickness;
	F32 corner_radius;
	F32 blur;
	V2 cutout_origin;
	V2 cutout_size;
};

struct RasterizerData
{
	V4 rasterizer_position_ndc [[position]];
	V2 position;
	V2 center;
	V2 half_size;
	V2 cutout_center;
	V2 cutout_half_size;
	V4 color;
	V2 texture_coordinates;
	B32 untextured;
	F32 border_thickness;
	F32 corner_radius;
	F32 blur;
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

constant global V2 corners[] = {
        {0, 1},
        {0, 0},
        {1, 1},
        {1, 1},
        {1, 0},
        {0, 0},
};

vertex RasterizerData
VertexShader(U32 vertex_id [[vertex_id]], U32 instance_id [[instance_id]], constant Box *boxes,
        constant V2 *texture_bounds, constant V2 *bounds)
{
	RasterizerData result = {0};

	V2 corner = corners[vertex_id];
	Box box = boxes[instance_id];

	V2 box_p0_rounded = metal::floor(box.origin);
	V2 box_p1_rounded = metal::ceil(box.origin + box.size);
	V2 box_origin_rounded = box_p0_rounded;
	V2 box_size_rounded = box_p1_rounded - box_p0_rounded;

	box_origin_rounded -= 100;
	box_size_rounded += 200;

	V2 origin_rounding = box_origin_rounded - box.origin;
	V2 size_rounding = box_size_rounded - box.size;

	V2 position = box_origin_rounded + box_size_rounded * corner;
	V2 position_ndc = (position / *bounds * 2 - 1) * V2(1, -1);

	result.rasterizer_position_ndc = V4(position_ndc, 0, 1);

	// The rasterizer interpolates in such a manner as to give us
	// values that correspond with the centers of fragments,
	// rather than the top-left corners of fragments.
	// We reposition ourselves to the top-left corners of fragments
	// by subtracting 0.5.
	result.position = position - 0.5;

	// Don’t blur more than the size of the box itself.
	F32 shortest_side = metal::min(box.size.x, box.size.y);
	box.blur = metal::min(box.blur, shortest_side);

	result.center = box.origin + box.size * 0.5;

	// By default the entirety of the blur sits outside of the box,
	// but we want half to sit within the box and the other half outside the box.
	// Thus, we need to move each edge of the box inwards by 0.5 * blur.
	// There are two edges in each dimension, so we subtract 1 * blur.
	result.half_size = 0.5 * (box.size - box.blur);
	result.half_size = metal::max(result.half_size, 0);

	result.cutout_center = box.cutout_origin + box.cutout_size * 0.5;
	result.cutout_half_size = 0.5 * box.cutout_size;

	// Multiply by 0.5 to account for glyph atlas using points rather than pixels.
	result.texture_coordinates =
	        corner * ((box.texture_size + size_rounding * 0.5) / *texture_bounds) +
	        ((box.texture_origin + origin_rounding * 0.5) / *texture_bounds);

	result.color.r = SRGBLinearFromGamma(box.color.r);
	result.color.g = SRGBLinearFromGamma(box.color.g);
	result.color.b = SRGBLinearFromGamma(box.color.b);
	result.color.a = 1;
	result.color *= box.color.a;

	result.untextured = box.texture_size.x == 0 && box.texture_size.y == 0;
	result.border_thickness = box.border_thickness;
	result.corner_radius = metal::min(box.corner_radius, 0.5 * shortest_side);
	result.blur = box.blur;

	return result;
}

F32
Rectangle(V2 sample_position, V2 center, V2 half_size, F32 corner_radius)
{
	sample_position -= center;

	// We sample fragments from the top-left corner. As a result,
	// all fragments that touch the bottom or right edges of the rectangle
	// have zero distance to the rectangle’s edge, causing them to be lit up.
	// This makes the rectangle one pixel too wide and one pixel too tall.
	// We adjust the size and position to counteract this effect.
	half_size -= 0.5;
	sample_position += 0.5;

	V2 distance_to_edges = metal::abs(sample_position) - half_size + corner_radius;
	return metal::min(metal::max(distance_to_edges.x, distance_to_edges.y), 0.f) +
	       metal::length(metal::max(distance_to_edges, 0)) - corner_radius;
}

fragment V4
FragmentShader(RasterizerData data [[stage_in]], metal::texture2d<F32> glyph_atlas)
{
	F32 distance = Rectangle(data.position, data.center, data.half_size, data.corner_radius);
	F32 factor = 1 - metal::saturate(distance / (data.blur + 1));
	V4 result = data.color * factor;

	if (data.cutout_half_size.x > 0 || data.cutout_half_size.y > 0)
	{
		distance = Rectangle(data.position, data.cutout_center, data.cutout_half_size,
		        data.corner_radius);
		factor = metal::saturate(distance);
		result *= factor;
	}

	if (data.border_thickness != 0)
	{
		distance = Rectangle(data.position, data.center,
		        data.half_size - data.border_thickness,
		        data.corner_radius - data.border_thickness);
		factor = metal::saturate(distance / (data.blur + 1));
		result *= factor;
	}

	if (!data.untextured)
	{
		metal::sampler glyph_atlas_sampler(
		        metal::mag_filter::linear, metal::min_filter::linear);
		F32 sample = glyph_atlas.sample(glyph_atlas_sampler, data.texture_coordinates).a;
		result *= sample;
	}

	return result;
}
