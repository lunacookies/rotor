enum
{
	GlyphAtlasPaddingX = 2,
	GlyphAtlasPaddingY = 2,
};

function void
GlyphAtlasInit(GlyphAtlas *atlas, id<MTLDevice> device, F32 scale_factor)
{
	atlas->width = 1024;
	atlas->height = 1024;

	atlas->width_pixels = (U64)CeilF32(atlas->width * scale_factor);
	atlas->height_pixels = (U64)CeilF32(atlas->height * scale_factor);

	atlas->pixels = calloc(atlas->width_pixels * atlas->height_pixels, sizeof(U32));
	CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceLinearGray);
	atlas->context = CGBitmapContextCreate(atlas->pixels, atlas->width_pixels,
	        atlas->height_pixels, 8, atlas->width_pixels, colorspace, kCGImageAlphaOnly);
	CGContextScaleCTM(atlas->context, scale_factor, scale_factor);

	MTLTextureDescriptor *descriptor = [[MTLTextureDescriptor alloc] init];
	descriptor.width = atlas->width_pixels;
	descriptor.height = atlas->height_pixels;
	descriptor.pixelFormat = MTLPixelFormatA8Unorm;
	atlas->texture = [device newTextureWithDescriptor:descriptor];

	atlas->slot_count = 1 << 16;
	atlas->slots = calloc(atlas->slot_count, sizeof(GlyphAtlasSlot));
}

function void
GlyphAtlasAdd(GlyphAtlas *atlas, CTFontRef font, CGGlyph glyph, GlyphAtlasSlot *slot)
{
	if (atlas->used_slot_count == atlas->slot_count)
	{
		return;
	}
	atlas->used_slot_count++;

	CGRect bounding_rect;
	CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationDefault, &glyph, &bounding_rect, 1);

	U64 glyph_width = (U64)CeilF64(bounding_rect.size.width);
	U64 glyph_height = (U64)CeilF64(bounding_rect.size.height);
	F64 glyph_baseline = bounding_rect.size.height + bounding_rect.origin.y;

	U64 x_step = glyph_width + GlyphAtlasPaddingX;
	U64 y_step = atlas->tallest_this_row + GlyphAtlasPaddingY;

	U64 remaining_x_in_row = atlas->width - atlas->current_row_x;
	if (remaining_x_in_row < x_step)
	{
		atlas->current_row_y += y_step;
		atlas->tallest_this_row = 0;
		atlas->current_row_x = 0;
	}

	slot->font = font;
	slot->glyph = glyph;
	slot->x = atlas->current_row_x;
	slot->y = atlas->current_row_y;
	slot->width = glyph_width;
	slot->height = glyph_height;
	slot->baseline = (U64)glyph_baseline;

	CGPoint position = { 0 };
	position.x = atlas->current_row_x - bounding_rect.origin.x + 0.5;
	position.y = atlas->height - (atlas->current_row_y + glyph_baseline + 0.5);

	CGRect rect = { 0 };
	rect.origin.x = atlas->current_row_x;
	rect.origin.y = atlas->height - (atlas->current_row_y + glyph_height);
	rect.size.width = glyph_width;
	rect.size.height = glyph_height;

	CTFontDrawGlyphs(font, &glyph, &position, 1, atlas->context);

	atlas->current_row_x += x_step;
	atlas->tallest_this_row = Max(atlas->tallest_this_row, glyph_height);

	[atlas->texture
	        replaceRegion:MTLRegionMake2D(0, 0, atlas->width_pixels, atlas->height_pixels)
	          mipmapLevel:0
	            withBytes:atlas->pixels
	          bytesPerRow:atlas->width_pixels];
}

function GlyphAtlasSlot *
GlyphAtlasGet(GlyphAtlas *atlas, CTFontRef font, CGGlyph glyph)
{
	U64 slot_count_mask = atlas->slot_count - 1;
	U64 slot_index = glyph & slot_count_mask;
	for (;;)
	{
		GlyphAtlasSlot *slot = atlas->slots + slot_index;

		if (slot->glyph == glyph && CFEqual(slot->font, font))
		{
			return slot;
		}

		if (slot->glyph == 0)
		{
			GlyphAtlasAdd(atlas, font, glyph, slot);
			return slot;
		}

		slot_index = (slot_index + 1) & slot_count_mask;
	}
}
