struct RasterizerData
{
	float4 position [[position]];
	float3 color;
};

vertex RasterizerData
VertexShader(uint vertex_id [[vertex_id]], constant float2 *positions, constant float3 *colors)
{
	RasterizerData result = { 0 };
	result.position = float4(positions[vertex_id], 0, 1);
	result.color = colors[vertex_id];
	return result;
}

fragment float4
FragmentShader(RasterizerData data [[stage_in]])
{
	return float4(data.color, 0);
}
