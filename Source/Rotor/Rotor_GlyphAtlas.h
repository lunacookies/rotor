typedef struct GlyphAtlasSlot GlyphAtlasSlot;
struct GlyphAtlasSlot
{
	CTFontRef font;
	CGGlyph glyph;
	U64 x;
	U64 y;
};

typedef struct GlyphAtlas GlyphAtlas;
struct GlyphAtlas
{
	U64 width;
	U64 height;
	U64 width_pixels;
	U64 height_pixels;
	U32 *pixels;
	CGContextRef context;
	id<MTLTexture> texture;

	GlyphAtlasSlot *slots;
	U64 slot_count; // must always be power of two
	U64 used_slot_count;

	U64 current_row_x;
	U64 current_row_y;
	U64 tallest_this_row;
};

function void GlyphAtlasInit(GlyphAtlas *atlas, id<MTLDevice> device, F32 scale_factor);
function GlyphAtlasSlot *GlyphAtlasGet(GlyphAtlas *atlas, CTFontRef font, CGGlyph glyph);
