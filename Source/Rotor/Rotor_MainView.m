@interface
MainView () <CALayerDelegate>
@end

typedef struct View View;
struct View
{
	View *next;
	V2 origin;
	V2 size;
	B32 pressed;
	String8 string;
};

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

@implementation MainView

Arena *permanent_arena;
Arena *frame_arena;

CAMetalLayer *metal_layer;
id<MTLTexture> multisample_texture;
id<MTLCommandQueue> command_queue;
id<MTLRenderPipelineState> pipeline_state;

CVDisplayLinkRef display_link;

GlyphAtlas glyph_atlas;
CTFontRef font;
CTFontRef big_font;

View *views;
B32 button_pressed;
V2 button_origin;
V2 button_size;

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

	font = (__bridge CTFontRef)[NSFont systemFontOfSize:14 weight:NSFontWeightRegular];
	big_font = (__bridge CTFontRef)[NSFont systemFontOfSize:50 weight:NSFontWeightRegular];

	View *button1 = PushStruct(permanent_arena, View);
	button1->origin.x = 100;
	button1->origin.y = 100;
	button1->size.x = 50;
	button1->size.y = 20;
	button1->string = Str8Lit("hello tt fi world 👋");

	View *button2 = PushStruct(permanent_arena, View);
	button2->origin.x = 200;
	button2->origin.y = 300;
	button2->size.x = 100;
	button2->size.y = 40;
	button2->string = Str8Lit("“no.” “no”. WAVE Te");
	button2->next = button1;

	View *button3 = PushStruct(permanent_arena, View);
	button3->origin.x = 50;
	button3->origin.y = 10;
	button3->size.x = 50;
	button3->size.y = 50;
	button3->string = Str8Lit("𝕏ⓘ⁵");
	button3->next = button2;

	views = button3;

	CVDisplayLinkCreateWithActiveCGDisplays(&display_link);
	CVDisplayLinkSetOutputCallback(display_link, DisplayLinkCallback, (__bridge void *)self);
	CVDisplayLinkStart(display_link);

	return self;
}

- (void)displayLayer:(CALayer *)layer
{
	ArenaClear(frame_arena);

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

	BoxArray box_array = {0};
	box_array.capacity = 1024;
	box_array.boxes = PushArray(frame_arena, Box, box_array.capacity);

	for (View *view = views; view != 0; view = view->next)
	{
		Box *bg_box = box_array.boxes + box_array.count;
		box_array.count++;

		RasterizedLine rasterized_line = {0};
		RasterizeLine(frame_arena, &rasterized_line, view->string, &glyph_atlas, font);

		view->size = rasterized_line.bounds;

		bg_box->origin = view->origin;
		bg_box->size = view->size;
		bg_box->color.r = MixF32(1, 0, (F32)view->pressed);
		bg_box->color.g = MixF32(0, 1, (F32)view->pressed);
		bg_box->color.b = MixF32(1, 0, (F32)view->pressed);

		V2 text_origin = view->origin;
		text_origin.y += (rasterized_line.bounds.y + (F32)CTFontGetCapHeight(font)) * 0.5f;

		for (U64 glyph_index = 0; glyph_index < rasterized_line.glyph_count; glyph_index++)
		{
			V2 position = rasterized_line.positions[glyph_index];
			position.x += text_origin.x;
			position.y += text_origin.y;

			GlyphAtlasSlot *slot = rasterized_line.slots[glyph_index];

			Box *box = box_array.boxes + box_array.count;
			box_array.count++;
			Assert(box_array.count <= box_array.capacity);

			box->origin = position;
			box->texture_origin.x = slot->x;
			box->texture_origin.y = slot->y;
			box->size.x = slot->width;
			box->size.y = slot->height;
			box->texture_size.x = slot->width;
			box->texture_size.y = slot->height;

			if (!view->pressed)
			{
				box->color.r = 1;
				box->color.g = 1;
				box->color.b = 1;
			}
		}
	}

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

- (void)mouseDown:(NSEvent *)event
{
	NSPoint location = event.locationInWindow;
	location.y = self.bounds.size.height - location.y;

	for (View *view = views; view != 0; view = view->next)
	{
		view->pressed = location.x >= view->origin.x && location.y >= view->origin.y &&
		                location.x <= view->origin.x + view->size.x &&
		                location.y <= view->origin.y + view->size.y;
	}
}

- (void)mouseUp:(NSEvent *)event
{
	for (View *view = views; view != 0; view = view->next)
	{
		view->pressed = 0;
	}
}

@end
