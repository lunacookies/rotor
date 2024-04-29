function B32
String8Match(String8 a, String8 b)
{
	if (a.count != b.count)
	{
		return 0;
	}

	return MemoryMatch(a.data, b.data, a.count);
}
