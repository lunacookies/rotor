@interface
MainView () <CALayerDelegate>
@end

typedef struct Box Box;
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
	B32 invert;
};

typedef struct BoxRenderChunk BoxRenderChunk;
struct BoxRenderChunk
{
	BoxRenderChunk *next;
	U64 start;
	U64 count;
	V2 clip_origin;
	V2 clip_size;
};

typedef struct BoxArray BoxArray;
struct BoxArray
{
	Box *boxes;
	U64 count;
	U64 capacity;

	BoxRenderChunk *first_chunk;
	BoxRenderChunk *last_chunk;
};

typedef struct RasterizedLine RasterizedLine;
struct RasterizedLine
{
	V2 bounds;
	U64 glyph_count;
	V2 *positions;
	GlyphAtlasSlot **slots;
};

typedef U32 ViewFlags;
enum : ViewFlags
{
	ViewFlags_FirstFrame = (1 << 0),
	ViewFlags_Clip = (1 << 1),
};

typedef U32 SignalFlags;
enum : SignalFlags
{
	SignalFlags_Clicked = (1 << 0),
	SignalFlags_Pressed = (1 << 1),
	SignalFlags_Dragged = (1 << 2),
	SignalFlags_Scrolled = (1 << 3),
};

typedef struct Signal Signal;
struct Signal
{
	V2 location;
	SignalFlags flags;
	V2 drag_distance;
	V2 scroll_distance;
};

function B32
Clicked(Signal signal)
{
	return signal.flags & SignalFlags_Clicked;
}

function B32
Pressed(Signal signal)
{
	return signal.flags & SignalFlags_Pressed;
}

function B32
Dragged(Signal signal)
{
	return signal.flags & SignalFlags_Dragged;
}

function B32
Scrolled(Signal signal)
{
	return signal.flags & SignalFlags_Scrolled;
}

function U64
KeyFromString(String8 string, U64 seed)
{
	U64 result = seed;
	for (U64 i = 0; i < string.count; i++)
	{
		result = ((result << 5) + result) + string.data[i];
	}
	return result;
}

typedef struct View View;
struct View
{
	View *next;
	View *first;
	View *last;
	View *parent;

	View *next_all;
	View *prev_all;

	U64 key;

	ViewFlags flags;
	V2 origin;
	V2 origin_target;
	V2 origin_velocity;
	V2 size;
	V2 size_target;
	V2 size_minimum;
	V2 size_velocity;
	V2 padding;
	F32 child_gap;
	Axis2 child_layout_axis;
	V2 child_offset;
	V4 color;
	V4 text_color;
	V4 border_color;
	F32 border_thickness;
	F32 corner_radius;
	V4 drop_shadow_color;
	F32 drop_shadow_blur;
	V2 drop_shadow_offset;
	V4 inner_shadow_color;
	F32 inner_shadow_blur;
	V2 inner_shadow_offset;
	String8 string;
	RasterizedLine rasterized_line;
	U64 last_touched_build_index;
	B32 pressed;
};

typedef enum EventKind
{
	EventKind_MouseUp = 1,
	EventKind_MouseDown,
	EventKind_MouseDragged,
	EventKind_Scroll,
} EventKind;

typedef struct Event Event;
struct Event
{
	Event *next;
	V2 location;
	V2 scroll_distance;
	EventKind kind;
};

typedef struct State State;
struct State
{
	View *root;
	View *current;

	View *first_view_all;
	View *last_view_all;
	View *first_free_view;

	Event *first_event;
	Event *last_event;
	V2 last_mouse_down_location;
	V2 last_mouse_drag_location;

	Arena *arena;
	Arena *frame_arena;
	GlyphAtlas *glyph_atlas;
	CTFontRef font;
	U64 build_index;

	B32 make_next_current;
};

function void
RasterizeLine(
        Arena *arena, RasterizedLine *result, String8 text, GlyphAtlas *glyph_atlas, CTFontRef font)
{
	CFStringRef string = CFStringCreateWithBytes(
	        kCFAllocatorDefault, text.data, (CFIndex)text.count, kCFStringEncodingUTF8, 0);

	CFDictionaryRef attributes = (__bridge CFDictionaryRef)
	        @{(__bridge NSString *)kCTFontAttributeName : (__bridge NSFont *)font};

	CFAttributedStringRef attributed =
	        CFAttributedStringCreate(kCFAllocatorDefault, string, attributes);
	CTLineRef line = CTLineCreateWithAttributedString(attributed);
	result->glyph_count = (U64)CTLineGetGlyphCount(line);

	CGRect cg_bounds = CTLineGetBoundsWithOptions(line, 0);
	result->bounds.x = (F32)cg_bounds.size.width;
	result->bounds.y = (F32)cg_bounds.size.height;

	result->positions = PushArray(arena, V2, result->glyph_count);
	result->slots = PushArray(arena, GlyphAtlasSlot *, result->glyph_count);

	CFArrayRef runs = CTLineGetGlyphRuns(line);
	U64 run_count = (U64)CFArrayGetCount(runs);
	U64 glyph_index = 0;

	for (U64 i = 0; i < run_count; i++)
	{
		CTRunRef run = CFArrayGetValueAtIndex(runs, (CFIndex)i);
		U64 run_glyph_count = (U64)CTRunGetGlyphCount(run);

		CFDictionaryRef run_attributes = CTRunGetAttributes(run);
		const void *run_font_raw =
		        CFDictionaryGetValue(run_attributes, kCTFontAttributeName);
		Assert(run_font_raw != NULL);

		// Ensure we actually have a CTFont instance.
		CFTypeID ct_font_type_id = CTFontGetTypeID();
		CFTypeID run_font_attribute_type_id = CFGetTypeID(run_font_raw);
		Assert(ct_font_type_id == run_font_attribute_type_id);

		CTFontRef run_font = run_font_raw;

		CFRange range = {0};
		range.length = (CFIndex)run_glyph_count;

		CGGlyph *glyphs = PushArray(arena, CGGlyph, run_glyph_count);
		CGPoint *glyph_positions = PushArray(arena, CGPoint, run_glyph_count);
		CTRunGetGlyphs(run, range, glyphs);
		CTRunGetPositions(run, range, glyph_positions);

		for (U64 j = 0; j < run_glyph_count; j++)
		{
			F32 x = (F32)glyph_positions[j].x * glyph_atlas->scale_factor;
			F32 y = (F32)glyph_positions[j].y * glyph_atlas->scale_factor;
			F32 subpixel_offset = x - FloorF32(x);
			F32 subpixel_resolution = 4;
			F32 rounded_subpixel_offset =
			        FloorF32(subpixel_offset * subpixel_resolution) /
			        subpixel_resolution;

			GlyphAtlasSlot *slot = GlyphAtlasGet(
			        glyph_atlas, run_font, glyphs[j], rounded_subpixel_offset);

			result->positions[glyph_index].x = FloorF32(x);
			result->positions[glyph_index].y = FloorF32(y - slot->baseline);
			result->slots[glyph_index] = slot;

			glyph_index++;
		}
	}

	CFRelease(line);
	CFRelease(attributed);
	CFRelease(string);
}

global State *state;

function void
StateInit(Arena *frame_arena, GlyphAtlas *glyph_atlas)
{
	Arena *arena = ArenaAlloc();
	state = PushStruct(arena, State);
	state->arena = arena;
	state->frame_arena = frame_arena;
	state->glyph_atlas = glyph_atlas;
	state->font = (__bridge CTFontRef)[NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
}

function void
MakeNextCurrent(void)
{
	state->make_next_current = 1;
}

function void
MakeParentCurrent(void)
{
	state->current = state->current->parent;
}

function View *
ViewAlloc(void)
{
	View *result = state->first_free_view;
	if (result == 0)
	{
		result = PushStruct(state->arena, View);
	}
	else
	{
		state->first_free_view = state->first_free_view->next_all;
		MemoryZeroStruct(result);
	}

	if (state->first_view_all == 0)
	{
		state->first_view_all = result;
	}
	else
	{
		state->last_view_all->next_all = result;
	}

	result->child_layout_axis = Axis2_Y;
	result->prev_all = state->last_view_all;
	state->last_view_all = result;
	return result;
}

function void
ViewRelease(View *view)
{
	if (state->first_view_all == view)
	{
		state->first_view_all = view->next_all;
	}

	if (state->last_view_all == view)
	{
		state->last_view_all = view->prev_all;
	}

	if (view->prev_all != 0)
	{
		view->prev_all->next_all = view->next_all;
	}

	if (view->next_all != 0)
	{
		view->next_all->prev_all = view->prev_all;
	}

	view->next_all = state->first_free_view;
	state->first_free_view = view;
}

function void
ViewPush(View *view)
{
	view->next = 0;
	view->first = 0;
	view->last = 0;
	view->parent = 0;

	// Push view onto the list of children of the current view.
	view->parent = state->current;
	if (state->current->first == 0)
	{
		Assert(state->current->last == 0);
		state->current->first = view;
	}
	else
	{
		state->current->last->next = view;
	}
	state->current->last = view;

	if (state->make_next_current)
	{
		state->current = view;
		state->make_next_current = 0;
	}
}

function View *
ViewFromString(String8 string)
{
	View *result = 0;
	U64 key = KeyFromString(string, state->current->key);

	for (View *view = state->first_view_all; view != 0; view = view->next_all)
	{
		if (view->key == key)
		{
			result = view;
			result->flags &= ~ViewFlags_FirstFrame;
			break;
		}
	}

	if (result == 0)
	{
		result = ViewAlloc();
		result->key = key;
		result->flags |= ViewFlags_FirstFrame;
	}

	ViewPush(result);
	result->last_touched_build_index = state->build_index;

	return result;
}

function Signal
SignalForView(View *view)
{
	Signal result = {0};
	if (view->pressed)
	{
		result.flags |= SignalFlags_Pressed;
	}

	for (Event *event = state->first_event; event != 0; event = event->next)
	{
		result.location = event->location;

		B32 in_bounds = event->location.x >= view->origin.x &&
		                event->location.y >= view->origin.y &&
		                event->location.x <= view->origin.x + view->size.x &&
		                event->location.y <= view->origin.y + view->size.y;

		B32 last_mouse_down_in_bounds =
		        state->last_mouse_down_location.x >= view->origin.x &&
		        state->last_mouse_down_location.y >= view->origin.y &&
		        state->last_mouse_down_location.x <= view->origin.x + view->size.x &&
		        state->last_mouse_down_location.y <= view->origin.y + view->size.y;

		switch (event->kind)
		{
			case EventKind_MouseUp:
			{
				result.flags &= ~SignalFlags_Pressed;
				if (in_bounds && last_mouse_down_in_bounds)
				{
					result.flags |= SignalFlags_Clicked;
				}
			}
			break;

			case EventKind_MouseDown:
			{
				if (in_bounds)
				{
					result.flags |= SignalFlags_Pressed;
					state->last_mouse_drag_location = event->location;
				}
				state->last_mouse_down_location = event->location;
			}
			break;

			case EventKind_MouseDragged:
			{
				if (last_mouse_down_in_bounds)
				{
					result.flags |= SignalFlags_Dragged;
					result.drag_distance.x += event->location.x -
					                          state->last_mouse_drag_location.x;
					result.drag_distance.y += event->location.y -
					                          state->last_mouse_drag_location.y;
					if (in_bounds)
					{
						result.flags |= SignalFlags_Pressed;
					}
					state->last_mouse_drag_location = event->location;
				}

				if (!in_bounds)
				{
					result.flags &= ~SignalFlags_Pressed;
				}
			}
			break;

			case EventKind_Scroll:
			{
				if (in_bounds)
				{
					result.flags |= SignalFlags_Scrolled;
					result.scroll_distance = event->scroll_distance;
				}
			}
			break;
		}
	}

	view->pressed = result.flags & SignalFlags_Pressed;
	return result;
}

function Signal
Label(String8 string)
{
	View *view = ViewFromString(string);
	view->string = string;
	view->text_color = v4(1, 1, 1, 1);
	return SignalForView(view);
}

function Signal
Button(String8 string)
{
	View *view = ViewFromString(string);
	view->string = string;
	view->padding = v2(10, 3);
	view->color = v4(0.35f, 0.35f, 0.35f, 1);
	view->text_color = v4(1, 1, 1, 1);
	view->border_thickness = 1;
	view->border_color = v4(0, 0, 0, 1);
	view->corner_radius = 4;
	view->drop_shadow_color = v4(0, 0, 0, 0.25f);
	view->drop_shadow_blur = 4;
	view->drop_shadow_offset.y = 2;
	view->inner_shadow_color = v4(1, 1, 1, 0.2f);
	view->inner_shadow_blur = 0;
	view->inner_shadow_offset.y = 1;

	Signal signal = SignalForView(view);

	if (Pressed(signal))
	{
		view->color = v4(0.15f, 0.15f, 0.15f, 1);
		view->text_color = v4(0.9f, 0.9f, 0.9f, 1);
		view->drop_shadow_color = v4(1, 1, 1, 0.2f);
		view->drop_shadow_blur = 1;
		view->drop_shadow_offset.y = 1;
		view->inner_shadow_color = v4(0, 0, 0, 0.5f);
		view->inner_shadow_blur = 4;
		view->inner_shadow_offset.y = 2;
	}

	return signal;
}

function Signal
Checkbox(B32 *value, String8 string)
{
	MakeNextCurrent();
	View *view = ViewFromString(string);

	MakeNextCurrent();
	View *box = ViewFromString(Str8Lit("box"));
	View *mark = ViewFromString(Str8Lit("mark"));
	MakeParentCurrent();

	View *label = ViewFromString(Str8Lit("label"));
	MakeParentCurrent();

	view->child_layout_axis = Axis2_X;
	view->child_gap = 5;
	box->border_thickness = 1;
	box->corner_radius = 2;
	box->drop_shadow_color = v4(1, 1, 1, 0.1f);
	box->drop_shadow_blur = 1;
	box->drop_shadow_offset.y = 1;
	mark->corner_radius = 2;
	mark->color = v4(1, 1, 1, 1);
	mark->drop_shadow_color = v4(0, 0, 0, 0.5);
	mark->drop_shadow_blur = 4;
	mark->drop_shadow_offset.y = 2;
	label->string = string;
	label->text_color = v4(1, 1, 1, 1);

	Signal signal = SignalForView(view);
	if (Clicked(signal))
	{
		*value = !*value;
	}

	if (*value)
	{
		if (Pressed(signal))
		{
			box->color = v4(0.2f, 0.7f, 1, 1);
			box->padding = v2(6, 6);
			mark->padding = v2(4, 4);
		}
		else
		{
			box->color = v4(0, 0.5f, 1, 1);
			box->padding = v2(5, 5);
			mark->padding = v2(5, 5);
		}
		box->border_color = v4(0, 0, 0, 0.5f);
	}
	else
	{
		if (Pressed(signal))
		{
			box->color = v4(0.4f, 0.4f, 0.4f, 1);
			box->padding = v2(8, 8);
			mark->padding = v2(2, 2);
		}
		else
		{
			box->color = v4(0.1f, 0.1f, 0.1f, 1);
			box->padding = v2(10, 10);
			mark->padding = v2(0, 0);
		}
		box->border_color = v4(0, 0, 0, 1);
	}

	return signal;
}

function Signal
RadioButton(U32 *selection, U32 option, String8 string)
{
	MakeNextCurrent();
	View *view = ViewFromString(string);

	MakeNextCurrent();
	View *box = ViewFromString(Str8Lit("box"));
	View *mark = ViewFromString(Str8Lit("mark"));
	MakeParentCurrent();

	View *label = ViewFromString(Str8Lit("label"));
	MakeParentCurrent();

	view->child_layout_axis = Axis2_X;
	view->child_gap = 5;
	box->border_thickness = 1;
	box->corner_radius = 10;
	box->drop_shadow_color = v4(1, 1, 1, 0.1f);
	box->drop_shadow_blur = 1;
	box->drop_shadow_offset.y = 1;
	mark->color = v4(1, 1, 1, 1);
	mark->corner_radius = 10;
	mark->drop_shadow_color = v4(0, 0, 0, 0.5);
	mark->drop_shadow_blur = 4;
	mark->drop_shadow_offset.y = 2;
	label->string = string;
	label->text_color = v4(1, 1, 1, 1);

	Signal signal = SignalForView(view);
	if (Clicked(signal))
	{
		*selection = option;
	}

	if (*selection == option)
	{
		if (Pressed(signal))
		{
			box->color = v4(0.2f, 0.7f, 1, 1);
			box->padding = v2(6, 6);
			mark->padding = v2(4, 4);
		}
		else
		{
			box->color = v4(0, 0.5f, 1, 1);
			box->padding = v2(5, 5);
			mark->padding = v2(5, 5);
		}
		box->border_color = v4(0, 0, 0, 0.5f);
	}
	else
	{
		if (Pressed(signal))
		{
			box->color = v4(0.4f, 0.4f, 0.4f, 1);
			box->padding = v2(8, 8);
			mark->padding = v2(2, 2);
		}
		else
		{
			box->color = v4(0.1f, 0.1f, 0.1f, 1);
			box->padding = v2(10, 10);
			mark->padding = v2(0, 0);
		}
		box->border_color = v4(0, 0, 0, 1);
	}

	return signal;
}

function Signal
SliderF32(F32 *value, F32 minimum, F32 maximum, String8 string)
{
	MakeNextCurrent();
	View *view = ViewFromString(string);

	MakeNextCurrent();
	View *track = ViewFromString(Str8Lit("track"));
	View *thumb = ViewFromString(Str8Lit("thumb"));
	MakeParentCurrent();

	View *label = ViewFromString(Str8Lit("label"));

	MakeParentCurrent();

	V2 size = v2(200, 20);

	view->child_layout_axis = Axis2_X;
	view->child_gap = 10;
	track->size_minimum = size;
	track->color = v4(0, 0, 0, 1);
	track->corner_radius = size.y;
	track->drop_shadow_color = v4(1, 1, 1, 0.1f);
	track->drop_shadow_blur = 1;
	track->drop_shadow_offset.y = 1;
	thumb->size_minimum = size;
	thumb->size_minimum.x *= (*value - minimum) / (maximum - minimum);
	thumb->corner_radius = size.y;
	label->text_color = v4(1, 1, 1, 1);

	Signal signal = SignalForView(view);

	if (Pressed(signal))
	{
		thumb->color = v4(1, 1, 1, 1);
	}
	else
	{
		thumb->color = v4(0.7f, 0.7f, 0.7f, 1);
	}

	if (Dragged(signal))
	{
		*value += MixF32(0, maximum - minimum, signal.drag_distance.x / size.x);
		*value = Clamp(*value, minimum, maximum);
	}

	label->string = String8Format(state->frame_arena, "%.5f", *value);

	return signal;
}

function Signal
Scrollable(String8 string)
{
	View *view = ViewFromString(string);
	view->flags |= ViewFlags_Clip;
	view->color = v4(1, 0, 0, 1);
	view->size_minimum = v2(200, 200);

	Signal signal = SignalForView(view);
	if (Scrolled(signal))
	{
		view->child_offset.x += signal.scroll_distance.x;
		view->child_offset.y += signal.scroll_distance.y;
	}

	return signal;
}

function void
PruneUnusedViews(void)
{
	View *next = 0;

	for (View *view = state->first_view_all; view != 0; view = next)
	{
		next = view->next_all;

		if (view->last_touched_build_index < state->build_index)
		{
			ViewRelease(view);
		}
	}
}

global B32 use_springs = 1;
global B32 use_animations = 1;

function void
StepAnimation(F32 *x, F32 *dx, F32 x_target, B32 is_size)
{
	if (!use_animations)
	{
		*x = x_target;
		return;
	}

	if (!use_springs)
	{
		*x += (x_target - *x) * 0.1f;
		return;
	}

	F32 tension = 1;
	F32 friction = 5;
	F32 mass = 20;

	F32 displacement = *x - x_target;
	F32 tension_force = -tension * displacement;
	F32 friction_force = -friction * *dx;
	F32 ddx = (tension_force + friction_force) * (1.f / mass);
	*dx += ddx;
	*x += *dx;

	if (is_size && *x < 0)
	{
		*dx = 0;
		*x = 0;
		return;
	}
}

function void
LayoutView(View *view, V2 origin)
{
	MemoryZeroStruct(&view->rasterized_line);
	if (view->text_color.a > 0)
	{
		RasterizeLine(state->frame_arena, &view->rasterized_line, view->string,
		        state->glyph_atlas, state->font);
	}

	V2 start_position = origin;
	V2 current_position = origin;
	current_position.x += view->padding.x + view->child_offset.x;
	current_position.y += view->padding.y + view->child_offset.y;

	current_position.y += RoundF32(view->rasterized_line.bounds.y);

	V2 content_size_max = {0};
	content_size_max.x = RoundF32(view->rasterized_line.bounds.x);
	content_size_max.y = RoundF32(view->rasterized_line.bounds.y);

	for (View *child = view->first; child != 0; child = child->next)
	{
		LayoutView(child, current_position);
		content_size_max.x = Max(content_size_max.x, child->size_target.x);
		content_size_max.y = Max(content_size_max.y, child->size_target.y);

		switch (view->child_layout_axis)
		{
			case Axis2_X:
			{
				current_position.x += child->size_target.x + view->child_gap;
			}
			break;

			case Axis2_Y:
			{
				current_position.y += child->size_target.y + view->child_gap;
			}
			break;
		}
	}

	current_position.y += view->padding.y;

	// Update origin and size targets.
	view->origin_target = origin;
	switch (view->child_layout_axis)
	{
		case Axis2_X:
		{
			view->size_target.x = current_position.x - start_position.x;
			view->size_target.y = content_size_max.y + view->padding.y * 2;
		}
		break;

		case Axis2_Y:
		{
			view->size_target.x = content_size_max.x + view->padding.x * 2;
			view->size_target.y = current_position.y - start_position.y;
		}
		break;
	}
	view->size_target.x = Max(view->size_target.x, view->size_minimum.x);
	view->size_target.y = Max(view->size_target.y, view->size_minimum.y);

	// Step origin and size animations towards their targets.
	if (view->flags & ViewFlags_FirstFrame)
	{
		view->origin = view->origin_target;
		view->size = view->size_target;
	}
	else
	{
		StepAnimation(&view->origin.x, &view->origin_velocity.x, view->origin_target.x, 0);
		StepAnimation(&view->origin.y, &view->origin_velocity.y, view->origin_target.y, 0);
		StepAnimation(&view->size.x, &view->size_velocity.x, view->size_target.x, 1);
		StepAnimation(&view->size.y, &view->size_velocity.y, view->size_target.y, 1);
	}
}

function void
LayoutUI(V2 viewport_size)
{
	state->root->size_minimum = viewport_size;
	LayoutView(state->root, v2(0, 0));
}

function void
StartBuild(void)
{
	state->root = ViewAlloc();
	state->root->flags |= ViewFlags_FirstFrame;
	state->root->color = v4(0.2f, 0.2f, 0.2f, 1);
	state->root->padding = v2(20, 20);
	state->root->child_gap = 10;
	state->current = state->root;
	state->build_index++;
}

function void
EndBuild(V2 viewport_size)
{
	PruneUnusedViews();
	LayoutUI(viewport_size);
	state->first_event = 0;
	state->last_event = 0;
}

function void
BuildUI(void)
{
	if (Clicked(Button(Str8Lit("Button 1"))))
	{
		printf("button 1!\n");
	}

	Signal button_2_signal = Button(Str8Lit("Toggle Button 3"));
	local_persist B32 show_button_3 = 0;

	if (Clicked(button_2_signal))
	{
		printf("button 2!\n");
		show_button_3 = !show_button_3;
	}

	if (show_button_3)
	{
		if (Clicked(Button(Str8Lit("Button 3"))))
		{
			printf("button 3!\n");
		}
	}

	if (Pressed(button_2_signal))
	{
		Label(Str8Lit("Button 2 is currently pressed."));
	}

	Button(Str8Lit("Another Button"));

	Checkbox(&show_button_3, Str8Lit("Button 3?"));

	local_persist B32 checked = 0;
	Checkbox(&checked, Str8Lit("Another Checkbox"));
	Signal springs_signal = Checkbox(&use_springs, Str8Lit("Animate Using Springs"));
	Checkbox(&use_animations, Str8Lit("Animate"));
	if (Clicked(springs_signal) && use_springs)
	{
		use_animations = 1;
	}

	local_persist F32 value = 15;
	SliderF32(&value, 10, 20, Str8Lit("Slider"));

	local_persist U32 selection = 0;
	RadioButton(&selection, 0, Str8Lit("Foo"));
	RadioButton(&selection, 1, Str8Lit("Bar"));
	RadioButton(&selection, 2, Str8Lit("Baz"));

	MakeNextCurrent();
	Scrollable(Str8Lit("scrollable"));
	Button(Str8Lit("some button 1"));
	Button(Str8Lit("some button 2"));
	Button(Str8Lit("some button 3"));
	Button(Str8Lit("some button 4"));
	Button(Str8Lit("some button 5"));
	Button(Str8Lit("some button 6"));
	Button(Str8Lit("some button 7"));
	Button(Str8Lit("some button 8"));
	Button(Str8Lit("some button 9"));
	Button(Str8Lit("some button 10"));
	Button(Str8Lit("some button 11"));
	MakeParentCurrent();
}

function void
RenderView(View *view, V2 clip_origin, V2 clip_size, F32 scale_factor, BoxArray *box_array)
{
	if (view->flags & ViewFlags_Clip)
	{
		V2 parent_clip_origin = clip_origin;
		V2 parent_clip_size = clip_size;
		clip_origin.x = Max(parent_clip_origin.x, view->origin.x);
		clip_origin.y = Max(parent_clip_origin.y, view->origin.y);
		clip_size.x = Min(parent_clip_origin.x + parent_clip_size.x,
		                      view->origin.x + view->size.x) -
		              clip_origin.x;
		clip_size.y = Min(parent_clip_origin.y + parent_clip_size.y,
		                      view->origin.y + view->size.y) -
		              clip_origin.y;
	}

	BoxRenderChunk *chunk = 0;

	if (box_array->first_chunk == 0)
	{
		Assert(box_array->last_chunk == 0);
		chunk = PushStruct(state->frame_arena, BoxRenderChunk);
		box_array->first_chunk = chunk;
		box_array->last_chunk = box_array->first_chunk;
	}
	else
	{
		if (box_array->last_chunk->clip_origin.x == clip_origin.x &&
		        box_array->last_chunk->clip_origin.y == clip_origin.y &&
		        box_array->last_chunk->clip_size.x == clip_size.x &&
		        box_array->last_chunk->clip_size.y == clip_size.y)
		{
			chunk = box_array->last_chunk;
		}
		else
		{
			chunk = PushStruct(state->frame_arena, BoxRenderChunk);
			chunk->start = box_array->count;
			box_array->last_chunk->next = chunk;
			box_array->last_chunk = chunk;
		}
	}

	chunk->clip_origin = clip_origin;
	chunk->clip_size = clip_size;

	V2 inside_border_origin = view->origin;
	inside_border_origin.x += view->border_thickness;
	inside_border_origin.y += view->border_thickness;

	V2 inside_border_size = view->size;
	inside_border_size.x -= view->border_thickness * 2;
	inside_border_size.y -= view->border_thickness * 2;

	F32 inside_border_corner_radius = view->corner_radius - view->border_thickness;

	if (view->color.a > 0)
	{
		Box *box = box_array->boxes + box_array->count;
		box_array->count++;
		chunk->count++;
		Assert(box_array->count <= box_array->capacity);

		box->origin = inside_border_origin;
		box->origin.x *= scale_factor;
		box->origin.y *= scale_factor;
		box->size = inside_border_size;
		box->size.x *= scale_factor;
		box->size.y *= scale_factor;
		box->color = view->color;
		box->corner_radius = inside_border_corner_radius * scale_factor;
	}

	if (view->text_color.a > 0)
	{
		V2 text_origin = view->origin;
		text_origin.x += view->padding.x;
		text_origin.y += view->padding.y;
		text_origin.x *= scale_factor;
		text_origin.y *= scale_factor;
		text_origin.y += RoundF32(
		        (view->rasterized_line.bounds.y + (F32)CTFontGetCapHeight(state->font)) *
		        scale_factor * 0.5f);

		for (U64 glyph_index = 0; glyph_index < view->rasterized_line.glyph_count;
		        glyph_index++)
		{
			GlyphAtlasSlot *slot = view->rasterized_line.slots[glyph_index];

			Box *box = box_array->boxes + box_array->count;
			box_array->count++;
			chunk->count++;
			Assert(box_array->count <= box_array->capacity);

			box->origin = view->rasterized_line.positions[glyph_index];
			box->origin.x += text_origin.x;
			box->origin.y += text_origin.y;
			box->texture_origin.x = slot->origin.x;
			box->texture_origin.y = slot->origin.y;
			box->size.x = slot->size.x;
			box->size.y = slot->size.y;
			box->texture_size.x = slot->size.x;
			box->texture_size.y = slot->size.y;
			box->color = view->text_color;
		}
	}

	for (View *child = view->first; child != 0; child = child->next)
	{
		if (child->drop_shadow_color.a > 0)
		{
			Box *box = box_array->boxes + box_array->count;
			box_array->count++;
			chunk->count++;
			Assert(box_array->count <= box_array->capacity);

			box->origin = child->origin;
			box->origin.x += child->drop_shadow_offset.x;
			box->origin.y += child->drop_shadow_offset.y;
			box->origin.x *= scale_factor;
			box->origin.y *= scale_factor;
			box->size = child->size;
			box->size.x *= scale_factor;
			box->size.y *= scale_factor;
			box->color = child->drop_shadow_color;
			box->corner_radius = child->corner_radius * scale_factor;
			box->blur = child->drop_shadow_blur * scale_factor;
			box->cutout_origin = child->origin;
			box->cutout_origin.x *= scale_factor;
			box->cutout_origin.y *= scale_factor;
			box->cutout_size = child->size;
			box->cutout_size.x *= scale_factor;
			box->cutout_size.y *= scale_factor;
		}
	}

	for (View *child = view->first; child != 0; child = child->next)
	{
		RenderView(child, clip_origin, clip_size, scale_factor, box_array);
	}

	if (view->inner_shadow_color.a > 0)
	{
		Box *box = box_array->boxes + box_array->count;
		box_array->count++;
		chunk->count++;
		Assert(box_array->count <= box_array->capacity);

		box->origin = inside_border_origin;
		box->origin.x += view->inner_shadow_offset.x;
		box->origin.y += view->inner_shadow_offset.y;
		box->origin.x *= scale_factor;
		box->origin.y *= scale_factor;
		box->size = inside_border_size;
		box->size.x *= scale_factor;
		box->size.y *= scale_factor;
		box->color = view->inner_shadow_color;
		box->corner_radius = inside_border_corner_radius * scale_factor;
		box->blur = view->inner_shadow_blur * scale_factor;
		box->cutout_origin = inside_border_origin;
		box->cutout_origin.x *= scale_factor;
		box->cutout_origin.y *= scale_factor;
		box->cutout_size = inside_border_size;
		box->cutout_size.x *= scale_factor;
		box->cutout_size.y *= scale_factor;
		box->invert = 1;
	}

	if (view->border_thickness > 0)
	{
		Box *box = box_array->boxes + box_array->count;
		box_array->count++;
		chunk->count++;
		Assert(box_array->count <= box_array->capacity);

		box->origin = view->origin;
		box->origin.x *= scale_factor;
		box->origin.y *= scale_factor;
		box->size = view->size;
		box->size.x *= scale_factor;
		box->size.y *= scale_factor;
		box->color = view->border_color;
		box->border_thickness = view->border_thickness * scale_factor;
		box->corner_radius = view->corner_radius * scale_factor;
	}
}

function void
RenderUI(V2 viewport_size, F32 scale_factor, BoxArray *box_array)
{
	RenderView(state->root, v2(0, 0), viewport_size, scale_factor, box_array);
}

@implementation MainView

Arena *permanent_arena;
Arena *frame_arena;

CAMetalLayer *metal_layer;
id<MTLCommandQueue> command_queue;
id<MTLRenderPipelineState> pipeline_state;

CVDisplayLinkRef display_link;

GlyphAtlas glyph_atlas;

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];

	setenv("MTL_HUD_ENABLED", "1", 1);
	setenv("MTL_SHADER_VALIDATION", "1", 1);
	setenv("MTL_DEBUG_LAYER", "1", 1);
	setenv("MTL_DEBUG_LAYER_WARNING_MODE", "assert", 1);
	setenv("MTL_DEBUG_LAYER_VALIDATE_LOAD_ACTIONS", "1", 1);
	setenv("MTL_DEBUG_LAYER_VALIDATE_STORE_ACTIONS", "1", 1);

	self.wantsLayer = YES;
	self.layer = [CAMetalLayer layer];
	metal_layer = (CAMetalLayer *)self.layer;
	permanent_arena = ArenaAlloc();
	frame_arena = ArenaAlloc();

	metal_layer.delegate = self;
	metal_layer.device = MTLCreateSystemDefaultDevice();
	metal_layer.pixelFormat = MTLPixelFormatRGBA16Float;
	command_queue = [metal_layer.device newCommandQueue];

	metal_layer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	Assert(metal_layer.colorspace);

	NSError *error = nil;

	NSBundle *bundle = [NSBundle mainBundle];
	NSURL *library_url = [bundle URLForResource:@"Shaders" withExtension:@"metallib"];
	id<MTLLibrary> library = [metal_layer.device newLibraryWithURL:library_url error:&error];
	if (library == nil)
	{
		[[NSAlert alertWithError:error] runModal];
		abort();
	}

	MTLRenderPipelineDescriptor *descriptor = [[MTLRenderPipelineDescriptor alloc] init];
	descriptor.colorAttachments[0].pixelFormat = metal_layer.pixelFormat;
	descriptor.colorAttachments[0].blendingEnabled = YES;
	descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
	descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
	descriptor.colorAttachments[0].destinationRGBBlendFactor =
	        MTLBlendFactorOneMinusSourceAlpha;
	descriptor.colorAttachments[0].destinationAlphaBlendFactor =
	        MTLBlendFactorOneMinusSourceAlpha;

	descriptor.vertexFunction = [library newFunctionWithName:@"VertexShader"];
	descriptor.fragmentFunction = [library newFunctionWithName:@"FragmentShader"];

	pipeline_state = [metal_layer.device newRenderPipelineStateWithDescriptor:descriptor
	                                                                    error:&error];

	if (pipeline_state == nil)
	{
		[[NSAlert alertWithError:error] runModal];
		abort();
	}

	CVDisplayLinkCreateWithActiveCGDisplays(&display_link);
	CVDisplayLinkSetOutputCallback(display_link, DisplayLinkCallback, (__bridge void *)self);

	return self;
}

- (void)displayLayer:(CALayer *)layer
{
	BoxArray box_array = {0};
	box_array.capacity = 1024;

	id<MTLBuffer> box_array_buffer =
	        [metal_layer.device newBufferWithLength:box_array.capacity * sizeof(Box)
	                                        options:MTLResourceStorageModeShared];
	box_array.boxes = box_array_buffer.contents;

	V2 viewport_size = {0};
	viewport_size.x = (F32)self.bounds.size.width;
	viewport_size.y = (F32)self.bounds.size.height;

	F32 scale_factor = (F32)self.window.backingScaleFactor;

	StartBuild();
	BuildUI();
	EndBuild(viewport_size);
	RenderUI(viewport_size, scale_factor, &box_array);

	id<CAMetalDrawable> drawable = [metal_layer nextDrawable];

	id<MTLCommandBuffer> command_buffer = [command_queue commandBuffer];

	MTLRenderPassDescriptor *descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
	descriptor.colorAttachments[0].texture = drawable.texture;
	descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
	descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
	descriptor.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 0, 1);

	id<MTLRenderCommandEncoder> encoder =
	        [command_buffer renderCommandEncoderWithDescriptor:descriptor];

	[encoder setRenderPipelineState:pipeline_state];

	V2 glyph_atlas_size = {0};
	glyph_atlas_size.x = (F32)glyph_atlas.size.x;
	glyph_atlas_size.y = (F32)glyph_atlas.size.y;
	[encoder setVertexBytes:&glyph_atlas_size length:sizeof(glyph_atlas_size) atIndex:1];

	V2 viewport_size_pixels = viewport_size;
	viewport_size_pixels.x *= scale_factor;
	viewport_size_pixels.y *= scale_factor;
	[encoder setVertexBytes:&viewport_size_pixels
	                 length:sizeof(viewport_size_pixels)
	                atIndex:2];

	[encoder setFragmentTexture:glyph_atlas.texture atIndex:0];

	for (BoxRenderChunk *chunk = box_array.first_chunk; chunk != 0; chunk = chunk->next)
	{
		[encoder setVertexBuffer:box_array_buffer
		                  offset:chunk->start * sizeof(Box)
		                 atIndex:0];

		V2 scissor_rect_p0 = chunk->clip_origin;
		scissor_rect_p0.x = Clamp(scissor_rect_p0.x, 0, viewport_size.x);
		scissor_rect_p0.y = Clamp(scissor_rect_p0.y, 0, viewport_size.y);

		V2 scissor_rect_p1 = chunk->clip_origin;
		scissor_rect_p1.x += chunk->clip_size.x;
		scissor_rect_p1.y += chunk->clip_size.y;
		scissor_rect_p1.x = Clamp(scissor_rect_p1.x, 0, viewport_size.x);
		scissor_rect_p1.y = Clamp(scissor_rect_p1.y, 0, viewport_size.y);

		V2 scissor_rect_origin = scissor_rect_p0;
		V2 scissor_rect_size = {0};
		scissor_rect_size.x = scissor_rect_p1.x - scissor_rect_p0.x;
		scissor_rect_size.y = scissor_rect_p1.y - scissor_rect_p0.y;

		MTLScissorRect scissor_rect = {0};
		scissor_rect.x = (U64)(scissor_rect_origin.x * scale_factor);
		scissor_rect.y = (U64)(scissor_rect_origin.y * scale_factor);
		scissor_rect.width = (U64)(scissor_rect_size.x * scale_factor);
		scissor_rect.height = (U64)(scissor_rect_size.y * scale_factor);

		[encoder setScissorRect:scissor_rect];

		[encoder drawPrimitives:MTLPrimitiveTypeTriangle
		            vertexStart:0
		            vertexCount:6
		          instanceCount:chunk->count];
	}

	[encoder endEncoding];

	[command_buffer presentDrawable:drawable];
	[command_buffer commit];

	ArenaClear(frame_arena);
}

- (void)viewDidChangeBackingProperties
{
	[super viewDidChangeBackingProperties];

	F32 scale_factor = (F32)self.window.backingScaleFactor;

	GlyphAtlasInit(&glyph_atlas, permanent_arena, metal_layer.device, scale_factor);
	StateInit(frame_arena, &glyph_atlas);
	metal_layer.contentsScale = self.window.backingScaleFactor;
	CVDisplayLinkStart(display_link);
}

- (void)setFrameSize:(NSSize)size
{
	[super setFrameSize:size];
	F32 scale_factor = (F32)self.window.backingScaleFactor;
	size.width *= scale_factor;
	size.height *= scale_factor;

	if (size.width == 0 && size.height == 0)
	{
		return;
	}

	metal_layer.drawableSize = size;
}

function CVReturn
DisplayLinkCallback(CVDisplayLinkRef _display_link, const CVTimeStamp *in_now,
        const CVTimeStamp *in_output_time, CVOptionFlags flags_in, CVOptionFlags *flags_out,
        void *display_link_context)
{
	MainView *view = (__bridge MainView *)display_link_context;
	dispatch_sync(dispatch_get_main_queue(), ^{
	  [view.layer setNeedsDisplay];
	});
	return kCVReturnSuccess;
}

- (void)mouseUp:(NSEvent *)event
{
	[self handleEvent:event];
}
- (void)mouseDown:(NSEvent *)event
{
	[self handleEvent:event];
}
- (void)mouseDragged:(NSEvent *)event
{
	[self handleEvent:event];
}
- (void)scrollWheel:(NSEvent *)event
{
	[self handleEvent:event];
}

- (void)handleEvent:(NSEvent *)ns_event
{
	EventKind kind = 0;

	switch (ns_event.type)
	{
		default: return;

		case NSEventTypeLeftMouseUp:
		{
			kind = EventKind_MouseUp;
		}
		break;

		case NSEventTypeLeftMouseDown:
		{
			kind = EventKind_MouseDown;
		}
		break;

		case NSEventTypeLeftMouseDragged:
		{
			kind = EventKind_MouseDragged;
		}
		break;

		case NSEventTypeScrollWheel:
		{
			kind = EventKind_Scroll;
		}
		break;
	}

	NSPoint location_ns_point = ns_event.locationInWindow;
	location_ns_point.y = self.bounds.size.height - location_ns_point.y;
	V2 location = {0};
	location.x = (F32)location_ns_point.x;
	location.y = (F32)location_ns_point.y;

	Event *event = PushStruct(frame_arena, Event);
	event->kind = kind;
	event->location = location;

	if (kind == EventKind_Scroll)
	{
		event->scroll_distance.x = (F32)ns_event.scrollingDeltaX;
		event->scroll_distance.y = (F32)ns_event.scrollingDeltaY;
	}

	if (state->first_event == 0)
	{
		Assert(state->last_event == 0);
		state->first_event = event;
	}
	else
	{
		state->last_event->next = event;
	}
	state->last_event = event;
}

@end
