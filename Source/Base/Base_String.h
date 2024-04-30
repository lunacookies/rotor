typedef struct String8 String8;
struct String8
{
	U8 *data;
	U64 count;
};

#define Str8Lit(s) ((String8){.data = (U8 *)(s), .count = sizeof(s) - 1})
#define Str8VArg(s) (S32)(s).count, (s).data

function B32 String8Match(String8 a, String8 b);
