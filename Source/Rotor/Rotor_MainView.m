@interface
MainView () <CALayerDelegate>
@end

typedef struct Box Box;
struct Box
{
	V3 color;
	V2 origin;
	V2 size;
	V2 texture_origin;
	V2 texture_size;
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
	ViewFlags_DrawBackground = (1 << 1),
	ViewFlags_DrawText = (1 << 2),
	ViewFlags_Clip = (1 << 3),
};

typedef struct Signal Signal;
struct Signal
{
	V2 location;
	B32 clicked;
	B32 pressed;
	B32 dragged;
	B32 scrolled;
	V2 drag_distance;
	V2 scroll_distance;
};

function B32
Clicked(Signal signal)
{
	return signal.clicked;
}

function B32
Pressed(Signal signal)
{
	return signal.pressed;
}

function B32
Dragged(Signal signal)
{
	return signal.dragged;
}

function B32
Scrolled(Signal signal)
{
	return signal.scrolled;
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
	V3 color;
	V3 text_color;
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
			CGGlyph glyph = glyphs[j];
			GlyphAtlasSlot *slot = GlyphAtlasGet(glyph_atlas, run_font, glyph);

			result->positions[glyph_index].x = (F32)glyph_positions[j].x;
			result->positions[glyph_index].y =
			        (F32)glyph_positions[j].y - slot->baseline;
			result->slots[glyph_index] = slot;

			glyph_index++;
		}
	}

	CFRelease(line);
	CFRelease(attributed);
	CFRelease(string);
}

function void
StateInit(State *state, Arena *frame_arena, GlyphAtlas *glyph_atlas)
{
	state->arena = ArenaAlloc();
	state->frame_arena = frame_arena;
	state->glyph_atlas = glyph_atlas;
	state->font = (__bridge CTFontRef)[NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
}

function void
MakeNextCurrent(State *state)
{
	state->make_next_current = 1;
}

function void
MakeParentCurrent(State *state)
{
	state->current = state->current->parent;
}

function View *
ViewAlloc(State *state)
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
ViewRelease(State *state, View *view)
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
ViewPush(State *state, View *view)
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
ViewFromString(State *state, String8 string)
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
		result = ViewAlloc(state);
		result->key = key;
		result->flags |= ViewFlags_FirstFrame;
	}

	ViewPush(state, result);
	result->last_touched_build_index = state->build_index;

	return result;
}

function Signal
SignalForView(State *state, View *view)
{
	Signal result = {0};
	result.pressed = view->pressed;

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
				result.pressed = 0;
				if (in_bounds && last_mouse_down_in_bounds)
				{
					result.clicked = 1;
				}
			}
			break;

			case EventKind_MouseDown:
			{
				if (in_bounds)
				{
					result.pressed = 1;
					state->last_mouse_drag_location = event->location;
				}
				state->last_mouse_down_location = event->location;
			}
			break;

			case EventKind_MouseDragged:
			{
				if (last_mouse_down_in_bounds)
				{
					result.dragged = 1;
					result.drag_distance.x += event->location.x -
					                          state->last_mouse_drag_location.x;
					result.drag_distance.y += event->location.y -
					                          state->last_mouse_drag_location.y;
					if (in_bounds)
					{
						result.pressed = 1;
					}
					state->last_mouse_drag_location = event->location;
				}

				if (!in_bounds)
				{
					result.pressed = 0;
				}
			}
			break;

			case EventKind_Scroll:
			{
				if (in_bounds)
				{
					result.scrolled = 1;
					result.scroll_distance = event->scroll_distance;
				}
			}
			break;
		}
	}

	view->pressed = result.pressed;
	return result;
}

function Signal
Label(State *state, String8 string)
{
	View *view = ViewFromString(state, string);
	view->flags |= ViewFlags_DrawText;
	view->string = string;
	view->text_color = v3(1, 1, 1);
	return SignalForView(state, view);
}

function Signal
Button(State *state, String8 string)
{
	View *view = ViewFromString(state, string);
	view->flags |= ViewFlags_DrawBackground | ViewFlags_DrawText;
	view->string = string;
	view->padding = v2(10, 2);

	Signal signal = SignalForView(state, view);

	if (Pressed(signal))
	{
		view->color = v3(0.7f, 0.7f, 0.7f);
		view->text_color = v3(0, 0, 0);
	}
	else
	{
		view->color = v3(0.1f, 0.1f, 0.1f);
		view->text_color = v3(1, 1, 1);
	}

	return signal;
}

function Signal
Checkbox(State *state, B32 *value, String8 string)
{
	MakeNextCurrent(state);
	View *view = ViewFromString(state, string);

	MakeNextCurrent(state);
	View *box = ViewFromString(state, Str8Lit("box"));
	View *mark = ViewFromString(state, Str8Lit("mark"));
	MakeParentCurrent(state);

	View *label = ViewFromString(state, Str8Lit("label"));
	MakeParentCurrent(state);

	view->child_layout_axis = Axis2_X;
	view->child_gap = 5;
	box->flags |= ViewFlags_DrawBackground;
	mark->flags |= ViewFlags_DrawBackground;
	mark->color = v3(1, 1, 1);
	label->flags |= ViewFlags_DrawText;
	label->string = string;
	label->text_color = v3(1, 1, 1);

	Signal signal = SignalForView(state, view);
	if (Clicked(signal))
	{
		*value = !*value;
	}

	if (*value)
	{
		if (Pressed(signal))
		{
			box->color = v3(0.2f, 0.7f, 1);
			box->padding = v2(6, 6);
			mark->padding = v2(4, 4);
		}
		else
		{
			box->color = v3(0, 0.5f, 1);
			box->padding = v2(5, 5);
			mark->padding = v2(5, 5);
		}
	}
	else
	{
		if (Pressed(signal))
		{
			box->color = v3(0.4f, 0.4f, 0.4f);
			box->padding = v2(8, 8);
			mark->padding = v2(2, 2);
		}
		else
		{
			box->color = v3(0.1f, 0.1f, 0.1f);
			box->padding = v2(10, 10);
			mark->padding = v2(0, 0);
		}
	}

	return signal;
}

function Signal
RadioButton(State *state, U32 *selection, U32 option, String8 string)
{
	MakeNextCurrent(state);
	View *view = ViewFromString(state, string);

	MakeNextCurrent(state);
	View *box = ViewFromString(state, Str8Lit("box"));
	View *mark = ViewFromString(state, Str8Lit("mark"));
	MakeParentCurrent(state);

	View *label = ViewFromString(state, Str8Lit("label"));
	MakeParentCurrent(state);

	view->child_layout_axis = Axis2_X;
	view->child_gap = 5;
	box->flags |= ViewFlags_DrawBackground;
	mark->flags |= ViewFlags_DrawBackground;
	mark->color = v3(1, 1, 1);
	label->flags |= ViewFlags_DrawText;
	label->string = string;
	label->text_color = v3(1, 1, 1);

	Signal signal = SignalForView(state, view);
	if (Clicked(signal))
	{
		*selection = option;
	}

	if (*selection == option)
	{
		if (Pressed(signal))
		{
			box->color = v3(0.2f, 0.7f, 1);
			box->padding = v2(6, 6);
			mark->padding = v2(4, 4);
		}
		else
		{
			box->color = v3(0, 0.5f, 1);
			box->padding = v2(5, 5);
			mark->padding = v2(5, 5);
		}
	}
	else
	{
		if (Pressed(signal))
		{
			box->color = v3(0.4f, 0.4f, 0.4f);
			box->padding = v2(8, 8);
			mark->padding = v2(2, 2);
		}
		else
		{
			box->color = v3(0.1f, 0.1f, 0.1f);
			box->padding = v2(10, 10);
			mark->padding = v2(0, 0);
		}
	}

	return signal;
}

function Signal
SliderF32(State *state, F32 *value, F32 minimum, F32 maximum, String8 string)
{
	MakeNextCurrent(state);
	View *view = ViewFromString(state, string);

	MakeNextCurrent(state);
	View *track = ViewFromString(state, Str8Lit("track"));
	View *thumb = ViewFromString(state, Str8Lit("thumb"));
	MakeParentCurrent(state);

	View *label = ViewFromString(state, Str8Lit("label"));

	MakeParentCurrent(state);

	V2 size = v2(200, 20);

	view->child_layout_axis = Axis2_X;
	view->child_gap = 10;
	track->flags |= ViewFlags_DrawBackground;
	track->size_minimum = size;
	track->color = v3(0, 0, 0);
	thumb->flags |= ViewFlags_DrawBackground;
	thumb->size_minimum = size;
	thumb->size_minimum.x *= (*value - minimum) / (maximum - minimum);
	label->flags |= ViewFlags_DrawText;
	label->text_color = v3(1, 1, 1);

	Signal signal = SignalForView(state, view);

	if (Pressed(signal))
	{
		thumb->color = v3(1, 1, 1);
	}
	else
	{
		thumb->color = v3(0.7f, 0.7f, 0.7f);
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
Scrollable(State *state, String8 string)
{
	View *view = ViewFromString(state, string);
	view->flags |= ViewFlags_Clip | ViewFlags_DrawBackground;
	view->color = v3(1, 0, 0);
	view->size_minimum = v2(200, 200);

	Signal signal = SignalForView(state, view);
	if (Scrolled(signal))
	{
		view->child_offset.x += signal.scroll_distance.x;
		view->child_offset.y += signal.scroll_distance.y;
	}

	return signal;
}

function void
PruneUnusedViews(State *state)
{
	View *next = 0;

	for (View *view = state->first_view_all; view != 0; view = next)
	{
		next = view->next_all;

		if (view->last_touched_build_index < state->build_index)
		{
			ViewRelease(state, view);
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

	if (is_size && x_target <= 0 && *x <= 0)
	{
		*x = 0;
		*dx = 0;
		return;
	}

	F32 displacement = *x - x_target;
	F32 tension_force = -tension * displacement;
	F32 friction_force = -friction * *dx;
	F32 ddx = (tension_force + friction_force) * (1.f / mass);
	*dx += ddx;
	*x += *dx;
}

function void
LayoutView(State *state, View *view, V2 origin)
{
	MemoryZeroStruct(&view->rasterized_line);
	if (view->flags & ViewFlags_DrawText)
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
		LayoutView(state, child, current_position);
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
LayoutUI(State *state, V2 viewport_size)
{
	state->root->size_minimum = viewport_size;
	LayoutView(state, state->root, v2(0, 0));
}

function void
StartBuild(State *state)
{
	state->root = ViewAlloc(state);
	state->root->flags |= ViewFlags_FirstFrame | ViewFlags_DrawBackground;
	state->root->color = v3(0.25, 0.25, 0.25);
	state->root->padding = v2(20, 20);
	state->root->child_gap = 10;
	state->current = state->root;
	state->build_index++;
}

function void
EndBuild(State *state, V2 viewport_size)
{
	PruneUnusedViews(state);
	LayoutUI(state, viewport_size);
	state->first_event = 0;
	state->last_event = 0;
}

function void
BuildUI(State *state)
{
	if (Clicked(Button(state, Str8Lit("Button 1"))))
	{
		printf("button 1!\n");
	}

	Signal button_2_signal = Button(state, Str8Lit("Toggle Button 3"));
	local_persist B32 show_button_3 = 0;

	if (Clicked(button_2_signal))
	{
		printf("button 2!\n");
		show_button_3 = !show_button_3;
	}

	if (show_button_3)
	{
		if (Clicked(Button(state, Str8Lit("Button 3"))))
		{
			printf("button 3!\n");
		}
	}

	if (Pressed(button_2_signal))
	{
		Label(state, Str8Lit("Button 2 is currently pressed."));
	}

	Button(state, Str8Lit("Another Button"));

	Checkbox(state, &show_button_3, Str8Lit("Button 3?"));

	local_persist B32 checked = 0;
	Checkbox(state, &checked, Str8Lit("Another Checkbox"));
	Signal springs_signal = Checkbox(state, &use_springs, Str8Lit("Animate Using Springs"));
	Checkbox(state, &use_animations, Str8Lit("Animate"));
	if (Clicked(springs_signal) && use_springs)
	{
		use_animations = 1;
	}

	local_persist F32 value = 15;
	SliderF32(state, &value, 10, 20, Str8Lit("Slider"));

	local_persist U32 selection = 0;
	RadioButton(state, &selection, 0, Str8Lit("Foo"));
	RadioButton(state, &selection, 1, Str8Lit("Bar"));
	RadioButton(state, &selection, 2, Str8Lit("Baz"));

	MakeNextCurrent(state);
	Scrollable(state, Str8Lit("scrollable"));
	Button(state, Str8Lit("some button 1"));
	Button(state, Str8Lit("some button 2"));
	Button(state, Str8Lit("some button 3"));
	Button(state, Str8Lit("some button 4"));
	Button(state, Str8Lit("some button 5"));
	Button(state, Str8Lit("some button 6"));
	Button(state, Str8Lit("some button 7"));
	Button(state, Str8Lit("some button 8"));
	Button(state, Str8Lit("some button 9"));
	Button(state, Str8Lit("some button 10"));
	Button(state, Str8Lit("some button 11"));
	MakeParentCurrent(state);
}

function void
RenderView(State *state, View *view, V2 clip_origin, V2 clip_size, BoxArray *box_array)
{
	if (view->flags & ViewFlags_Clip)
	{
		clip_origin = view->origin;
		clip_size = view->size;
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

	if (view->flags & ViewFlags_DrawBackground)
	{
		Box *bg_box = box_array->boxes + box_array->count;
		box_array->count++;
		chunk->count++;

		bg_box->origin = view->origin;
		bg_box->size = view->size;
		bg_box->color = view->color;
	}

	if (view->flags & ViewFlags_DrawText)
	{
		V2 text_origin = view->origin;
		text_origin.x += view->padding.x;
		text_origin.y += view->padding.y;
		text_origin.y +=
		        (view->rasterized_line.bounds.y + (F32)CTFontGetCapHeight(state->font)) *
		        0.5f;

		for (U64 glyph_index = 0; glyph_index < view->rasterized_line.glyph_count;
		        glyph_index++)
		{
			V2 position = view->rasterized_line.positions[glyph_index];
			position.x += text_origin.x;
			position.y += text_origin.y;

			GlyphAtlasSlot *slot = view->rasterized_line.slots[glyph_index];

			Box *box = box_array->boxes + box_array->count;
			box_array->count++;
			chunk->count++;
			Assert(box_array->count <= box_array->capacity);

			box->origin = position;
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
		RenderView(state, child, clip_origin, clip_size, box_array);
	}
}

function void
RenderUI(State *state, V2 viewport_size, BoxArray *box_array)
{
	RenderView(state, state->root, v2(0, 0), viewport_size, box_array);
}

@implementation MainView

Arena *permanent_arena;
Arena *frame_arena;

CAMetalLayer *metal_layer;
id<MTLTexture> multisample_texture;
id<MTLCommandQueue> command_queue;
id<MTLRenderPipelineState> pipeline_state;

CVDisplayLinkRef display_link;

GlyphAtlas glyph_atlas;
State state;

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

	metal_layer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceLinearSRGB);
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
	descriptor.rasterSampleCount = 4;
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

	StateInit(&state, frame_arena, &glyph_atlas);

	CVDisplayLinkCreateWithActiveCGDisplays(&display_link);
	CVDisplayLinkSetOutputCallback(display_link, DisplayLinkCallback, (__bridge void *)self);
	CVDisplayLinkStart(display_link);

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

	StartBuild(&state);
	BuildUI(&state);
	EndBuild(&state, viewport_size);
	RenderUI(&state, viewport_size, &box_array);

	id<CAMetalDrawable> drawable = [metal_layer nextDrawable];

	id<MTLCommandBuffer> command_buffer = [command_queue commandBuffer];

	MTLRenderPassDescriptor *descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
	descriptor.colorAttachments[0].texture = multisample_texture;
	descriptor.colorAttachments[0].resolveTexture = drawable.texture;
	descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
	descriptor.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
	descriptor.colorAttachments[0].clearColor = MTLClearColorMake(1, 1, 0, 1);

	id<MTLRenderCommandEncoder> encoder =
	        [command_buffer renderCommandEncoderWithDescriptor:descriptor];

	[encoder setRenderPipelineState:pipeline_state];

	local_persist V2 positions[] = {
	        {-1, 1},
	        {-1, -1},
	        {1, 1},
	        {1, 1},
	        {1, -1},
	        {-1, -1},
	};

	[encoder setVertexBytes:positions length:sizeof(positions) atIndex:0];

	V2 texture_bounds = v2(1024, 1024);
	[encoder setVertexBytes:&texture_bounds length:sizeof(texture_bounds) atIndex:2];

	[encoder setVertexBytes:&viewport_size length:sizeof(viewport_size) atIndex:3];

	[encoder setFragmentTexture:glyph_atlas.texture atIndex:0];

	for (BoxRenderChunk *chunk = box_array.first_chunk; chunk != 0; chunk = chunk->next)
	{
		[encoder setVertexBuffer:box_array_buffer
		                  offset:chunk->start * sizeof(Box)
		                 atIndex:1];

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

		F32 scale_factor = (F32)self.window.backingScaleFactor;

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

	metal_layer.contentsScale = self.window.backingScaleFactor;
	[self updateMultisampleTexture];
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
	[self updateMultisampleTexture];
}

- (void)updateMultisampleTexture
{
	F32 scale_factor = (F32)self.window.backingScaleFactor;
	MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
	descriptor.textureType = MTLTextureType2DMultisample;
	descriptor.usage = MTLTextureUsageRenderTarget;
	descriptor.storageMode = MTLStorageModeMemoryless;
	descriptor.width = (U64)(self.bounds.size.width * scale_factor);
	descriptor.height = (U64)(self.bounds.size.height * scale_factor);
	descriptor.pixelFormat = metal_layer.pixelFormat;
	descriptor.sampleCount = 4;
	multisample_texture = [metal_layer.device newTextureWithDescriptor:descriptor];
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

	if (state.first_event == 0)
	{
		Assert(state.last_event == 0);
		state.first_event = event;
	}
	else
	{
		state.last_event->next = event;
	}
	state.last_event = event;
}

@end
