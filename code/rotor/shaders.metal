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
	F32 softness;
	V2 cutout_origin;
	V2 cutout_size;
	V2 clip_origin;
	V2 clip_size;
	F32 clip_corner_radius;
	B32 invert;
};

struct EffectsBox
{
	V2 origin;
	V2 size;
	V2 clip_origin;
	V2 clip_size;
	F32 clip_corner_radius;
	F32 corner_radius;
	F32 blur_radius;
};

constant global V2 corners[] = {
        {0, 1},
        {0, 0},
        {1, 1},
        {1, 1},
        {1, 0},
        {0, 0},
};

F32
Rectangle(V2 sample_position, V2 center, V2 half_size, F32 corner_radius)
{
	sample_position -= center;

	// The rasterizer interpolates in such a manner as to give us
	// values that correspond with the centers of fragments,
	// rather than the top-left corners of fragments.
	// We reposition ourselves to the top-left corners of fragments
	// by subtracting 0.5.
	sample_position -= 0.5;

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

struct RasterizerData
{
	V4 bounds_position_ndc [[position]];
	V2 position;
	V2 center;
	V2 half_size;
	V2 cutout_center;
	V2 cutout_half_size;
	V2 clip_center;
	V2 clip_half_size;
	F32 clip_corner_radius;
	V4 color;
	V2 texture_coordinates;
	B32 untextured;
	F32 border_thickness;
	F32 corner_radius;
	F32 softness;
	B32 invert;
};

vertex RasterizerData
VertexShader(U32 vertex_id [[vertex_id]], U32 instance_id [[instance_id]], constant Box *boxes,
        constant V2 *bounds, constant V2 *texture_bounds)
{
	RasterizerData result = {0};

	V2 corner = corners[vertex_id];
	Box box = boxes[instance_id];

	V2 bounds_p0_rounded = 0;
	V2 bounds_p1_rounded = 0;
	if (box.invert)
	{
		bounds_p0_rounded = box.cutout_origin;
		bounds_p1_rounded = box.cutout_origin + box.cutout_size;
	}
	else
	{
		bounds_p0_rounded = box.origin - 0.5 * box.softness;
		bounds_p1_rounded = box.origin + box.size + 0.5 * box.softness;

		// Half the softness sits outside the box,
		// so space out the primitive’s bounds to contain the softness within it.
		bounds_p0_rounded -= 0.5 * box.softness;
		bounds_p1_rounded += 0.5 * box.softness;
	}
	bounds_p0_rounded = metal::floor(bounds_p0_rounded);
	bounds_p1_rounded = metal::ceil(bounds_p1_rounded);

	V2 bounds_origin_rounded = bounds_p0_rounded;
	V2 bounds_size_rounded = bounds_p1_rounded - bounds_p0_rounded;

	V2 bounds_origin_rounding = bounds_origin_rounded - box.origin;
	V2 bounds_size_rounding = bounds_size_rounded - box.size;

	V2 bounds_position_ndc =
	        ((bounds_origin_rounded + bounds_size_rounded * corner) / *bounds * 2 - 1) *
	        V2(1, -1);
	result.bounds_position_ndc = V4(bounds_position_ndc, 0, 1);

	result.position = bounds_origin_rounded + bounds_size_rounded * corner;

	// Don’t apply more softness than the size of the box itself.
	F32 shortest_side = metal::min(box.size.x, box.size.y);
	box.softness = metal::min(box.softness, shortest_side);

	result.center = box.origin + box.size * 0.5;

	// By default the entirety of the softness sits outside of the box,
	// but we want half to sit within the box and the other half outside the box.
	// Thus, we need to move each edge of the box inwards by 0.5 * softness.
	// There are two edges in each dimension, so we subtract 1 * softness.
	result.half_size = 0.5 * (box.size - box.softness);
	result.half_size = metal::max(result.half_size, 0);

	result.cutout_center = box.cutout_origin + box.cutout_size * 0.5;
	result.cutout_half_size = 0.5 * box.cutout_size;

	result.clip_center = box.clip_origin + box.clip_size * 0.5;
	result.clip_half_size = 0.5 * box.clip_size;
	result.clip_corner_radius = box.clip_corner_radius;

	result.texture_coordinates =
	        ((box.texture_origin + bounds_origin_rounding) / *texture_bounds) +
	        ((box.texture_size + bounds_size_rounding) / *texture_bounds) * corner;

	result.color = box.color;
	result.color.rgb *= result.color.a;

	result.untextured = box.texture_size.x == 0 && box.texture_size.y == 0;
	result.border_thickness = box.border_thickness;
	result.corner_radius = metal::min(box.corner_radius, 0.5 * shortest_side);
	result.softness = box.softness;
	result.invert = box.invert;

	return result;
}

fragment V4
FragmentShader(RasterizerData data [[stage_in]], metal::texture2d<F32> glyph_atlas)
{
	F32 factor = 1;

	F32 distance = Rectangle(data.position, data.center, data.half_size, data.corner_radius);
	if (data.invert)
	{
		factor *= metal::saturate(distance / (data.softness + 1));
	}
	else
	{
		factor *= 1 - metal::saturate(distance / (data.softness + 1));
	}

	if (data.cutout_half_size.x > 0 || data.cutout_half_size.y > 0)
	{
		distance = Rectangle(data.position, data.cutout_center, data.cutout_half_size,
		        data.corner_radius);
		if (data.invert)
		{
			factor *= 1 - metal::saturate(distance);
		}
		else
		{
			factor *= metal::saturate(distance);
		}
	}

	distance = Rectangle(
	        data.position, data.clip_center, data.clip_half_size, data.clip_corner_radius);
	factor *= 1 - metal::saturate(distance);

	if (data.border_thickness != 0)
	{
		distance = Rectangle(data.position, data.center,
		        data.half_size - data.border_thickness,
		        data.corner_radius - data.border_thickness);
		factor *= metal::saturate(distance / (data.softness + 1));
	}

	if (!data.untextured)
	{
		metal::sampler glyph_atlas_sampler(
		        metal::mag_filter::linear, metal::min_filter::linear);
		factor *= glyph_atlas.sample(glyph_atlas_sampler, data.texture_coordinates).a;
	}

	return data.color * factor;
}

struct EffectsRasterizerData
{
	V4 bounds_position_ndc [[position]];
	V2 position;
	V2 center;
	V2 half_size;
	F32 corner_radius;
	V2 clip_center;
	V2 clip_half_size;
	F32 clip_corner_radius;
	V2 texture_coordinates;
	V2 step_size;
	F32 blur_radius;
	V2 bounds_p0_uv;
	V2 bounds_p1_uv;
};

constant global U32 sample_count = 64;

vertex EffectsRasterizerData
EffectsVertexShader(U32 vertex_id [[vertex_id]], U32 instance_id [[instance_id]],
        constant EffectsBox *boxes, constant V2 *bounds, constant B32 *is_vertical)
{
	EffectsRasterizerData result = {0};

	V2 corner = corners[vertex_id];
	EffectsBox box = boxes[instance_id];

	V2 bounds_p0_rounded = metal::floor(box.origin);
	V2 bounds_p1_rounded = metal::ceil(box.origin + box.size);
	V2 bounds_origin_rounded = bounds_p0_rounded;
	V2 bounds_size_rounded = bounds_p1_rounded - bounds_p0_rounded;
	V2 bounds_position_ndc =
	        ((bounds_origin_rounded + bounds_size_rounded * corner) / *bounds * 2 - 1) *
	        V2(1, -1);
	result.bounds_position_ndc = V4(bounds_position_ndc, 0, 1);
	result.position = bounds_origin_rounded + bounds_size_rounded * corner;

	F32 shortest_side = metal::min(box.size.x, box.size.y);

	result.center = box.origin + box.size * 0.5;
	result.half_size = 0.5 * box.size;
	result.corner_radius = metal::min(box.corner_radius, 0.5 * shortest_side);

	result.clip_center = box.clip_origin + box.clip_size * 0.5;
	result.clip_half_size = 0.5 * box.clip_size;
	result.clip_corner_radius = box.clip_corner_radius;

	result.texture_coordinates =
	        (bounds_origin_rounded + bounds_size_rounded * corner) / *bounds;

	if (*is_vertical)
	{
		result.step_size = V2(0, 1 / bounds->y);
	}
	else
	{
		result.step_size = V2(1 / bounds->x, 0);
	}
	result.step_size *= box.blur_radius / sample_count;

	result.blur_radius = box.blur_radius;

	result.bounds_p0_uv = bounds_p0_rounded / *bounds;
	result.bounds_p1_uv = bounds_p1_rounded / *bounds;

	return result;
}

void
GaussianWeights(thread F32 *weights, F32 sigma)
{
	for (U32 i = 0; i < sample_count; i++)
	{
		F32 x = (F32)i - (F32)(sample_count / 2);
		weights[i] = metal::exp(-(x * x) / (2 * sigma * sigma));
	}
}

fragment V4
EffectsFragmentShader(EffectsRasterizerData data [[stage_in]], metal::texture2d<F32> behind)
{
	F32 distance = Rectangle(data.position, data.center, data.half_size, data.corner_radius);
	F32 factor = 1 - metal::saturate(distance);

	distance = Rectangle(
	        data.position, data.clip_center, data.clip_half_size, data.clip_corner_radius);
	factor *= 1 - metal::saturate(distance);

	metal::sampler behind_sampler(metal::mag_filter::linear, metal::min_filter::linear,
	        metal::address::mirrored_repeat);

	F32 weights[sample_count] = {0};
	GaussianWeights(weights, data.blur_radius);

	V4 samples = 0;
	F32 weights_sum = 0;

	for (U32 i = 0; i < sample_count; i++)
	{
		V2 offset = ((F32)i - (F32)(sample_count / 2)) * data.step_size;
		V2 sample_position = data.texture_coordinates + offset;

		if (sample_position.x < data.bounds_p0_uv.x ||
		        sample_position.x > data.bounds_p1_uv.x ||
		        sample_position.y < data.bounds_p0_uv.y ||
		        sample_position.y > data.bounds_p1_uv.y)
		{
			continue;
		}

		F32 weight = weights[i];
		weights_sum += weight;
		samples += weight * behind.sample(behind_sampler, sample_position);
	}

	samples /= weights_sum;

	return samples * factor;
}

struct GameRasterizerData
{
	V4 position [[position]];
	V3 color;
};

vertex GameRasterizerData
GameVertexShader(U32 vertex_id [[vertex_id]], U32 instance_id [[instance_id]],
        constant V2 *positions, constant F32 *sizes, constant V3 *colors, constant V2 *bounds)
{
	V2 corner = corners[vertex_id];
	V2 position = positions[instance_id];
	F32 size = sizes[instance_id];

	GameRasterizerData result = {0};
	result.position.xy = (position / *bounds + size * corner / *bounds) * 2;
	result.position.w = 1;
	result.color = colors[instance_id];
	return result;
}

fragment V4
GameFragmentShader(GameRasterizerData data [[stage_in]])
{
	return V4(data.color, 1);
}
