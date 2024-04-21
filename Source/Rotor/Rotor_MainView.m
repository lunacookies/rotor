@interface
MainView () <CALayerDelegate>
@end

@implementation MainView

CAMetalLayer *metal_layer;
id<MTLCommandQueue> command_queue;
id<MTLRenderPipelineState> pipeline_state;

CVDisplayLinkRef display_link;

GlyphAtlas glyph_atlas;

- (instancetype)initWithFrame:(NSRect)frame
{
	self = [super initWithFrame:frame];
	self.wantsLayer = YES;
	self.layer = [CAMetalLayer layer];
	metal_layer = (CAMetalLayer *)self.layer;

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
	CVDisplayLinkStart(display_link);

	return self;
}

- (void)displayLayer:(CALayer *)layer
{
	id<CAMetalDrawable> drawable = [metal_layer nextDrawable];

	id<MTLCommandBuffer> command_buffer = [command_queue commandBuffer];

	MTLRenderPassDescriptor *descriptor = [MTLRenderPassDescriptor renderPassDescriptor];
	descriptor.colorAttachments[0].texture = drawable.texture;
	descriptor.colorAttachments[0].loadAction = MTLLoadActionClear;
	descriptor.colorAttachments[0].storeAction = MTLStoreActionStore;
	descriptor.colorAttachments[0].clearColor = MTLClearColorMake(0.25, 0.25, 0.25, 1);

	id<MTLRenderCommandEncoder> encoder =
	        [command_buffer renderCommandEncoderWithDescriptor:descriptor];

	[encoder setRenderPipelineState:pipeline_state];

	local_persist simd_float2 positions[] = {
		{ -1, 1 },
		{ -1, -1 },
		{ 1, 1 },
		{ 1, 1 },
		{ 1, -1 },
		{ -1, -1 },
	};

	[encoder setVertexBytes:positions length:sizeof(positions) atIndex:0];

	char *text = "hello world 👋 “no.” “no”. WAVE Te";
	F32 font_size = 12;
	CTFontRef font =
	        (__bridge CTFontRef)[NSFont systemFontOfSize:font_size weight:NSFontWeightRegular];

	CFDictionaryRef attributes = (__bridge CFDictionaryRef)
	        @{ (__bridge NSString *)kCTFontAttributeName : (__bridge NSFont *)font };

	CFStringRef string =
	        CFStringCreateWithCString(kCFAllocatorDefault, text, kCFStringEncodingUTF8);
	CFAttributedStringRef attributed =
	        CFAttributedStringCreate(kCFAllocatorDefault, string, attributes);
	CTLineRef line = CTLineCreateWithAttributedString(attributed);
	U64 glyph_count = (U64)CTLineGetGlyphCount(line);

	simd_float2 *rect_origins = calloc(glyph_count, sizeof(simd_float2));
	simd_float2 *rect_sizes = calloc(glyph_count, sizeof(simd_float2));
	simd_float2 *texture_origins = calloc(glyph_count, sizeof(simd_float2));
	simd_float2 *texture_sizes = calloc(glyph_count, sizeof(simd_float2));

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
		assert(run_font_raw != NULL);

		// Ensure we actually have a CTFont instance.
		CFTypeID ct_font_type_id = CTFontGetTypeID();
		CFTypeID run_font_attribute_type_id = CFGetTypeID(run_font_raw);
		assert(ct_font_type_id == run_font_attribute_type_id);

		CTFontRef run_font = run_font_raw;

		CFRange range = { 0 };
		range.length = (CFIndex)run_glyph_count;

		CGGlyph *glyphs = calloc(run_glyph_count, sizeof(CGGlyph));
		CGPoint *glyph_positions = calloc(run_glyph_count, sizeof(CGPoint));
		CTRunGetGlyphs(run, range, glyphs);
		CTRunGetPositions(run, range, glyph_positions);

		for (U64 j = 0; j < run_glyph_count; j++)
		{
			CGGlyph glyph = glyphs[j];
			GlyphAtlasSlot *slot = GlyphAtlasGet(&glyph_atlas, run_font, glyph);

			rect_origins[glyph_index].x = (F32)glyph_positions[j].x;
			rect_origins[glyph_index].y =
			        (F32)glyph_positions[j].y - slot->baseline + 100;

			rect_sizes[glyph_index].x = slot->width;
			rect_sizes[glyph_index].y = slot->height;

			texture_origins[glyph_index].x = slot->x;
			texture_origins[glyph_index].y = slot->y;

			texture_sizes[glyph_index].x = slot->width;
			texture_sizes[glyph_index].y = slot->height;

			glyph_index++;
		}
	}

	[encoder setVertexBytes:rect_origins length:glyph_count * sizeof(simd_float2) atIndex:1];
	[encoder setVertexBytes:rect_sizes length:glyph_count * sizeof(simd_float2) atIndex:2];
	[encoder setVertexBytes:texture_origins length:glyph_count * sizeof(simd_float2) atIndex:3];
	[encoder setVertexBytes:texture_sizes length:glyph_count * sizeof(simd_float2) atIndex:4];

	simd_float2 texture_bounds = { 0 };
	texture_bounds.x = 1024;
	texture_bounds.y = 1024;
	[encoder setVertexBytes:&texture_bounds length:sizeof(texture_bounds) atIndex:5];

	simd_float2 bounds = { 0 };
	bounds.x = (F32)self.bounds.size.width;
	bounds.y = (F32)self.bounds.size.height;
	[encoder setVertexBytes:&bounds length:sizeof(bounds) atIndex:6];

	[encoder setFragmentTexture:glyph_atlas.texture atIndex:0];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangle
	            vertexStart:0
	            vertexCount:6
	          instanceCount:glyph_count];
	[encoder endEncoding];

	[command_buffer presentDrawable:drawable];
	[command_buffer commit];
}

- (void)viewDidChangeBackingProperties
{
	[super viewDidChangeBackingProperties];

	F32 scale_factor = (F32)self.window.backingScaleFactor;

	GlyphAtlasInit(&glyph_atlas, metal_layer.device, scale_factor);

	metal_layer.contentsScale = self.window.backingScaleFactor;
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

@end
