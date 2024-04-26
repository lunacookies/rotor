typedef struct GlyphAtlasSlot GlyphAtlasSlot;
struct GlyphAtlasSlot
{
	CTFontRef font;
	CGGlyph glyph;
	V2U64 origin;
	V2U64 size;
	U64 baseline;
};

typedef struct GlyphAtlas GlyphAtlas;
struct GlyphAtlas
{
	V2U64 size;
	V2U64 size_pixels;
	U32 *pixels;
	CGContextRef context;
	id<MTLTexture> texture;

	GlyphAtlasSlot *slots;
	U64 slot_count; // must always be power of two
	U64 used_slot_count;

	V2U64 current_row;
	U64 tallest_this_row;
};

function void GlyphAtlasInit(
        GlyphAtlas *atlas, Arena *arena, id<MTLDevice> device, F32 scale_factor);
function GlyphAtlasSlot *GlyphAtlasGet(GlyphAtlas *atlas, CTFontRef font, CGGlyph glyph);
