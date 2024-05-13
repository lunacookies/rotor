function B32
String8Match(String8 a, String8 b)
{
	if (a.count != b.count)
	{
		return 0;
	}

	return MemoryMatch(a.data, b.data, a.count);
}

function String8
String8Format(Arena *arena, char *fmt, ...)
{
	va_list args;
	va_start(args, fmt);

	U64 count = (U64)vsnprintf(0, 0, fmt, args);
	String8 result = {0};
	result.data = PushArray(arena, U8, count);
	result.count = (U64)vsnprintf((char *)result.data, count, fmt, args);

	va_end(args);
	return result;
}
