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

typedef struct BoxArray BoxArray;
struct BoxArray
{
	Box *boxes;
	U64 count;
	U64 capacity;
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
enum
{
	ViewFlags_DrawBackground = (1 << 0),
};

typedef struct Signal Signal;
struct Signal
{
	V2 location;
	B32 clicked;
	B32 pressed;
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

typedef struct View View;
struct View
{
	View *next;
	View *next_all;
	View *prev_all;

	ViewFlags flags;
	V2 origin;
	V2 size;
	V2 padding;
	V3 color;
	V3 pressed_color;
	B32 pressed;
	String8 string;
	RasterizedLine rasterized_line;
	U64 last_touched_build_index;
};

typedef struct Event Event;
struct Event
{
	Event *next;
	V2 location;
	B32 up;
};

typedef struct State State;
struct State
{
	View *first_view;
	View *last_view;

	View *first_view_all;
	View *last_view_all;
	View *first_free_view;

	Event *events;
	Arena *arena;
	GlyphAtlas *glyph_atlas;
	CTFontRef font;
	U64 build_index;
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
StateInit(State *state, GlyphAtlas *glyph_atlas)
{
	state->arena = ArenaAlloc();
	state->glyph_atlas = glyph_atlas;
	state->font = (__bridge CTFontRef)[NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
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
	if (state->first_view == 0)
	{
		state->first_view = view;
	}
	else
	{
		state->last_view->next = view;
	}

	view->next = 0;
	state->last_view = view;
}

function View *
ViewFromKey(State *state, String8 key)
{
	View *result = 0;

	for (View *view = state->first_view_all; view != 0; view = view->next_all)
	{
		if (String8Match(view->string, key))
		{
			result = view;
			break;
		}
	}

	if (result == 0)
	{
		result = ViewAlloc(state);
		result->string = key;
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

	for (Event *event = state->events; event != 0; event = event->next)
	{
		if (event->up)
		{
			result.pressed = 0;
		}

		B32 in_bounds = event->location.x >= view->origin.x &&
		                event->location.y >= view->origin.y &&
		                event->location.x <= view->origin.x + view->size.x &&
		                event->location.y <= view->origin.y + view->size.y;
		if (!in_bounds)
		{
			continue;
		}

		result.location = event->location;
		if (event->up)
		{
			result.clicked = 1;
		}
		else
		{
			result.pressed = 1;
		}
	}

	view->pressed = result.pressed;
	return result;
}

function Signal
Label(State *state, String8 string)
{
	View *label = ViewFromKey(state, string);
	return SignalForView(state, label);
}

function Signal
Button(State *state, String8 string)
{
	View *button = ViewFromKey(state, string);
	button->flags |= ViewFlags_DrawBackground;
	button->padding.x = 10;
	button->padding.y = 2;
	button->color.r = 0.1f;
	button->color.g = 0.1f;
	button->color.b = 0.1f;
	button->pressed_color.r = 0.7f;
	button->pressed_color.g = 0.7f;
	button->pressed_color.b = 0.7f;

	return SignalForView(state, button);
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

function void
BuildUI(State *state)
{
	state->first_view = 0;
	state->last_view = 0;
	state->build_index++;

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

	PruneUnusedViews(state);
}

function void
LayoutUI(State *state)
{
	V2 current_position = {0};
	current_position.x = 20;
	current_position.y = 20;
	F32 margin = 10;

	for (View *view = state->first_view; view != 0; view = view->next)
	{
		MemoryZeroStruct(&view->rasterized_line);
		RasterizeLine(state->arena, &view->rasterized_line, view->string,
		        state->glyph_atlas, state->font);

		view->origin = current_position;

		view->size.x = RoundF32(view->rasterized_line.bounds.x) + view->padding.x * 2;
		view->size.y = RoundF32(view->rasterized_line.bounds.y) + view->padding.y * 2;

		current_position.y += view->size.y + margin;
	}
}

function void
RenderUI(State *state, BoxArray *box_array)
{
	for (View *view = state->first_view; view != 0; view = view->next)
	{
		if (view->flags & ViewFlags_DrawBackground)
		{
			Box *bg_box = box_array->boxes + box_array->count;
			box_array->count++;

			bg_box->origin = view->origin;
			bg_box->size = view->size;

			if (view->pressed)
			{
				bg_box->color = view->pressed_color;
			}
			else
			{
				bg_box->color = view->color;
			}
		}

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
			Assert(box_array->count <= box_array->capacity);

			box->origin = position;
			box->texture_origin.x = slot->origin.x;
			box->texture_origin.y = slot->origin.y;
			box->size.x = slot->size.x;
			box->size.y = slot->size.y;
			box->texture_size.x = slot->size.x;
			box->texture_size.y = slot->size.y;

			if (!view->pressed)
			{
				box->color.r = 1;
				box->color.g = 1;
				box->color.b = 1;
			}
		}
	}
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
	self.wantsLayer = YES;
	self.layer = [CAMetalLayer layer];
	metal_layer = (CAMetalLayer *)self.layer;
	permanent_arena = ArenaAlloc();
	frame_arena = ArenaAlloc();

	metal_layer.delegate = self;
	metal_layer.device = MTLCreateSystemDefaultDevice();
	command_queue = [metal_layer.device newCommandQueue];

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

	StateInit(&state, &glyph_atlas);

	CVDisplayLinkCreateWithActiveCGDisplays(&display_link);
	CVDisplayLinkSetOutputCallback(display_link, DisplayLinkCallback, (__bridge void *)self);
	CVDisplayLinkStart(display_link);

	return self;
}

- (void)displayLayer:(CALayer *)layer
{
	ArenaClear(frame_arena);

	BoxArray box_array = {0};
	box_array.capacity = 1024;
	box_array.boxes = PushArray(frame_arena, Box, box_array.capacity);

	BuildUI(&state);
	LayoutUI(&state);
	RenderUI(&state, &box_array);
	state.events = 0;

	id<CAMetalDrawable> drawable = [metal_layer nextDrawable];

	id<MTLCommandBuffer> command_buffer = [command_queue commandBuffer];

	MTLRenderPassDescriptor *descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
	descriptor.colorAttachments[0].texture = multisample_texture;
	descriptor.colorAttachments[0].resolveTexture = drawable.texture;
	descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
	descriptor.colorAttachments[0].storeAction = MTLStoreActionMultisampleResolve;
	descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.25, 0.25, 0.25, 1);

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

	[encoder setVertexBytes:box_array.boxes length:box_array.count * sizeof(Box) atIndex:1];

	V2 texture_bounds = {0};
	texture_bounds.x = 1024;
	texture_bounds.y = 1024;
	[encoder setVertexBytes:&texture_bounds length:sizeof(texture_bounds) atIndex:2];

	V2 bounds = {0};
	bounds.x = (F32)self.bounds.size.width;
	bounds.y = (F32)self.bounds.size.height;
	[encoder setVertexBytes:&bounds length:sizeof(bounds) atIndex:3];

	[encoder setFragmentTexture:glyph_atlas.texture atIndex:0];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangle
	            vertexStart:0
	            vertexCount:6
	          instanceCount:box_array.count];
	[encoder endEncoding];

	[command_buffer presentDrawable:drawable];
	[command_buffer commit];
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

- (void)mouseDown:(NSEvent *)ns_event
{
	NSPoint location = ns_event.locationInWindow;
	location.y = self.bounds.size.height - location.y;

	Event *event = PushStruct(state.arena, Event);
	event->location.x = (F32)location.x;
	event->location.y = (F32)location.y;

	event->next = state.events;
	state.events = event;
}

- (void)mouseUp:(NSEvent *)ns_event
{
	NSPoint location = ns_event.locationInWindow;
	location.y = self.bounds.size.height - location.y;

	Event *event = PushStruct(state.arena, Event);
	event->location.x = (F32)location.x;
	event->location.y = (F32)location.y;
	event->up = 1;

	event->next = state.events;
	state.events = event;
}

@end
