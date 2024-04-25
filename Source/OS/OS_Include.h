function void *OS_Reserve(U64 size);
function B32 OS_Commit(void *ptr, U64 size);
function void _OS_Decommit(void *ptr, U64 size) __attribute((unused));
function void _OS_Release(void *ptr, U64 size) __attribute((unused));
