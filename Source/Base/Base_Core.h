#include <stdint.h>

typedef int8_t S8;
typedef int16_t S16;
typedef int32_t S32;
typedef int64_t S64;

typedef uint8_t U8;
typedef uint16_t U16;
typedef uint32_t U32;
typedef uint64_t U64;

typedef float F32;
typedef double F64;

typedef S8 B8;
typedef S16 B16;
typedef S32 B32;
typedef S64 B64;

typedef union V2 V2;
union __attribute((aligned(8))) V2
{
	struct
	{
		F32 x;
		F32 y;
	};
};

typedef union V2U64 V2U64;
union V2U64
{
	struct
	{
		U64 x;
		U64 y;
	};
};

typedef union V3 V3;
union __attribute((aligned(16))) V3
{
	struct
	{
		F32 x;
		F32 y;
		F32 z;
	};
	struct
	{
		F32 r;
		F32 g;
		F32 b;
	};
};

#define function static
#define local_persist static

#define Min(x, y) (((x) < (y)) ? (x) : (y))
#define Max(x, y) (((x) > (y)) ? (x) : (y))

#define CeilF32 ceilf
#define CeilF64 ceil
#define RoundF32 roundf
#define RoundF64 round

function F32 MixF32(F32 x, F32 y, F32 a);

#define Kibibytes(n) ((U64)1024 * (n))
#define Mebibytes(n) ((U64)1024 * Kibibytes(n))
#define Gibibytes(n) ((U64)1024 * Mebibytes(n))

#define AlignPow2(n, align) (((n) + (align) - 1) & ~((align) - 1))
#define AlignPadPow2(n, align) ((0 - (n)) & ((align) - 1))

#define MemoryCopy(dst, src, size) (memmove((dst), (src), (size)))
#define MemoryCopyArray(dst, src, count) (MemoryCopy((dst), (src), sizeof(*(dst)) * (count)))
#define MemoryCopyStruct(dst, src) (MemoryCopyArray((dst), (src), 1))

#define MemorySet(dst, byte, size) (memset((dst), (byte), (size)))
#define MemoryZero(dst, size) (MemorySet((dst), 0, (size)))
#define MemoryZeroArray(dst, count) (MemoryZero((dst), sizeof(*(dst)) * (count)))
#define MemoryZeroStruct(dst) (MemoryZeroArray((dst), 1))

#define MemoryCompare(dst, src, size) (memcmp((dst), (src), (size)))
#define MemoryMatch(dst, src, size) (MemoryCompare((dst), (src), (size)) == 0)

#define Assert(b)                                                                                  \
	if (!(b))                                                                                  \
	{                                                                                          \
		__builtin_debugtrap();                                                             \
	}
