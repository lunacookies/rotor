#define ARENA_RESERVE_SIZE Mebibytes(128)
#define ARENA_COMMIT_SIZE Kibibytes(64) // must be power of 2

typedef struct Arena Arena;
struct Arena
{
	U64 used;
	U64 committed;
};

function Arena *ArenaAlloc(void);
function void ArenaClear(Arena *arena);

function void *ArenaPush(Arena *arena, U64 size, U64 align);
function void *ArenaPushNoZero(Arena *arena, U64 size, U64 align);

#define PushArray(arena, T, count) ((T *)ArenaPush((arena), sizeof(T) * (count), _Alignof(T)))
#define PushArrayNoZero(arena, T, count)                                                           \
	((T *)ArenaPushNoZero((arena), sizeof(T) * (count), _Alignof(T)))
#define PushStruct(arena, T) (PushArray((arena), (T), 1))
#define PushStructNoZero(arena, T) (PushArrayNoZero((arena), (T), 1))
