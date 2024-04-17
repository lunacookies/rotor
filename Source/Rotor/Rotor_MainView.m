@interface
MainView () <CALayerDelegate>
@end

function id<MTLTexture>
CreateGlyphAtlas(id<MTLDevice> device)
{
	F32 factor = 2;

	U64 width = 1024;
	U64 width_pixels = (U64)ceil(width * factor);
	U64 height = 512;
	U64 height_pixels = (U64)ceil(height * factor);

	U32 *pixels = calloc(width_pixels * height_pixels, sizeof(U32));

	char *text = "W“Just the facts, ma’am.” WAVE ”. greed";
	F32 size = 100;

	CTFontRef font =
	        (__bridge CTFontRef)[NSFont systemFontOfSize:size weight:NSFontWeightRegular];

	CFDictionaryRef attributes = (__bridge CFDictionaryRef)
	        @{ (__bridge NSString *)kCTFontAttributeName : (__bridge NSFont *)font };

	CFStringRef string =
	        CFStringCreateWithCString(kCFAllocatorDefault, text, kCFStringEncodingUTF8);
	CFAttributedStringRef attributed =
	        CFAttributedStringCreate(kCFAllocatorDefault, string, attributes);
	CTLineRef line = CTLineCreateWithAttributedString(attributed);
	CFArrayRef runs = CTLineGetGlyphRuns(line);
	U64 run_count = (U64)CFArrayGetCount(runs);

	U64 total_glyph_count = (U64)CTLineGetGlyphCount(line);
	CGGlyph *glyphs = calloc(total_glyph_count, sizeof(CGGlyph));
	CGPoint *all_positions = calloc(total_glyph_count, sizeof(CGSize));
	U64 glyph_count = 0;

	for (U64 i = 0; i < run_count; i++)
	{
		CTRunRef run = CFArrayGetValueAtIndex(runs, (CFIndex)i);
		U64 run_glyph_count = (U64)CTRunGetGlyphCount(run);

		U64 remaining_slots = total_glyph_count - glyph_count;
		assert(run_glyph_count <= remaining_slots);

		CFRange range = { 0 };
		range.length = (CFIndex)run_glyph_count;

		CTRunGetGlyphs(run, range, glyphs + glyph_count);
		CTRunGetPositions(run, range, all_positions + glyph_count);
		glyph_count += run_glyph_count;
	}

	CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
	CGContextRef context =
	        CGBitmapContextCreate(pixels, width_pixels, height_pixels, 8, 4 * width_pixels,
	                colorspace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
	CGContextScaleCTM(context, 2, 2);
	CGContextSetFillColorWithColor(context, CGColorCreateSRGB(0, 0, 0, 1));
	CGContextFillRect(context, (CGRect){ .size = { width, height } });
	CGContextSetFillColorWithColor(context, CGColorCreateSRGB(0.9, 0.9, 0.9, 1));

	{
		CGRect *bounding_rects = calloc(glyph_count, sizeof(CGRect));
		CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationDefault, glyphs,
		        bounding_rects, (CFIndex)glyph_count);

		CGPoint *positions = calloc(glyph_count, sizeof(CGPoint));
		CGFloat current_position = 0;
		for (U64 i = 0; i < glyph_count; i++)
		{
			positions[i].x = current_position;
			positions[i].y = height - size;
			current_position += ceil(bounding_rects[i].size.width);
		}

		CTFontDrawGlyphs(font, glyphs, positions, glyph_count, context);
	}

	{
		CGRect *optical_bounds = calloc(glyph_count, sizeof(CGRect));
		CTFontGetOpticalBoundsForGlyphs(
		        font, glyphs, optical_bounds, (CFIndex)glyph_count, 0);

		CGPoint *positions = calloc(glyph_count, sizeof(CGPoint));
		CGFloat current_position = 0;
		for (U64 i = 0; i < glyph_count; i++)
		{
			positions[i].x = current_position;
			positions[i].y = height - size * 2;
			current_position += optical_bounds[i].size.width;
		}

		CTFontDrawGlyphs(font, glyphs, positions, glyph_count, context);
	}

	{
		CGSize *advances = calloc(glyph_count, sizeof(CGSize));
		CTFontGetAdvancesForGlyphs(
		        font, kCTFontOrientationDefault, glyphs, advances, (CFIndex)glyph_count);

		CGPoint *positions = calloc(glyph_count, sizeof(CGPoint));
		CGFloat current_position = 0;
		for (U64 i = 0; i < glyph_count; i++)
		{
			positions[i].x = current_position;
			positions[i].y = height - size * 3;
			current_position += advances[i].width;
		}

		CTFontDrawGlyphs(font, glyphs, positions, glyph_count, context);
	}

	{
		CGPoint *positions = calloc(glyph_count, sizeof(CGPoint));
		for (U64 i = 0; i < glyph_count; i++)
		{
			positions[i].x = all_positions[i].x;
			positions[i].y = height - size * 4;
		}

		CTFontDrawGlyphs(font, glyphs, positions, glyph_count, context);
	}

	MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
	descriptor.width = width_pixels;
	descriptor.height = height_pixels;

	id<MTLTexture> texture = [device newTextureWithDescriptor:descriptor];

	[texture replaceRegion:MTLRegionMake2D(0, 0, width_pixels, height_pixels)
	           mipmapLevel:0
	             withBytes:pixels
	           bytesPerRow:width_pixels * sizeof(U32)];

	free(pixels);

	return texture;
}

@implementation MainView

CAMetalLayer *metal_layer;
id<MTLCommandQueue> command_queue;
id<MTLRenderPipelineState> pipeline_state;

CVDisplayLinkRef display_link;

id<MTLTexture> glyph_atlas;

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

	glyph_atlas = CreateGlyphAtlas(metal_layer.device);

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

	simd_float2 rect_origin = { 0 };
	rect_origin.x = 100;
	rect_origin.y = 200;
	[encoder setVertexBytes:&rect_origin length:sizeof(rect_origin) atIndex:1];

	simd_float2 rect_size = { 0 };
	rect_size.x = 1024;
	rect_size.y = 512;
	[encoder setVertexBytes:&rect_size length:sizeof(rect_size) atIndex:2];

	simd_float2 bounds = { 0 };
	bounds.x = (F32)self.bounds.size.width;
	bounds.y = (F32)self.bounds.size.height;
	[encoder setVertexBytes:&bounds length:sizeof(bounds) atIndex:3];

	[encoder setFragmentTexture:glyph_atlas atIndex:0];
	[encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
	[encoder endEncoding];

	[command_buffer presentDrawable:drawable];
	[command_buffer commit];
}

- (void)viewDidChangeBackingProperties
{
	[super viewDidChangeBackingProperties];
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
