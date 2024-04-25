function Arena *
ArenaAlloc(void)
{
	U8 *ptr = OS_Reserve(ARENA_RESERVE_SIZE);
	OS_Commit(ptr, ARENA_COMMIT_SIZE);
	Arena *arena = (Arena *)ptr;
	arena->used = sizeof(Arena);
	arena->committed = ARENA_COMMIT_SIZE;
	return arena;
}

function void
ArenaClear(Arena *arena)
{
	arena->used = sizeof(Arena);
}

function void *
ArenaPush(Arena *arena, U64 size, U64 align)
{
	void *ptr = ArenaPushNoZero(arena, size, align);
	MemoryZero(ptr, size);
	return ptr;
}

function void *
ArenaPushNoZero(Arena *arena, U64 size, U64 align)
{
	U8 *ptr = (U8 *)arena;
	U64 padding = AlignPadPow2((U64)(ptr + arena->used), align);
	U64 needed_space = size + padding;
	Assert(ARENA_RESERVE_SIZE - arena->used >= needed_space);

	if (arena->committed - arena->used < needed_space)
	{
		U64 overflow = (arena->used + needed_space) - arena->committed;
		U64 commit_bytes = AlignPow2(overflow, ARENA_COMMIT_SIZE);
		OS_Commit(ptr + arena->committed, commit_bytes);
		arena->committed += commit_bytes;
		Assert(AlignPadPow2(arena->committed, ARENA_COMMIT_SIZE) == 0);
		Assert(arena->committed - arena->used >= needed_space);
	}

	arena->used += padding;
	U8 *allocation = ptr + arena->used;
	arena->used += size;
	return allocation;
}
