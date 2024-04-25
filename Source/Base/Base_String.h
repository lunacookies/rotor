typedef struct String8 String8;
struct String8
{
	U8 *data;
	U64 count;
};

#define String8Lit(s) ((String8){ .data = (U8 *)(s), .count = sizeof(s) - 1 })
