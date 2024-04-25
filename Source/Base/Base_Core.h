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

#define function static
#define local_persist static

#define Min(x, y) (((x) < (y)) ? (x) : (y))
#define Max(x, y) (((x) > (y)) ? (x) : (y))

#define CeilF32 ceilf
#define CeilF64 ceil

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

#define Assert(b)                                                                                  \
	if (!(b))                                                                                  \
	{                                                                                          \
		__builtin_debugtrap();                                                             \
	}
