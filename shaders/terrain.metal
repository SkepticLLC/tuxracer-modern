#include <metal_stdlib>
using namespace metal;

struct TerrainVertex {
    float3 position;
    float3 normal;
    float2 texcoord;
};

struct TerrainUniforms {
    float4x4 model_view_projection;
    float4x4 model_view;
};

struct TerrainVarying {
    float4 position [[position]];
    float3 normal;
    float2 texcoord;
};

vertex TerrainVarying terrain_vertex(
    uint vertex_id [[vertex_id]],
    const device TerrainVertex *vertices [[buffer(0)]],
    constant TerrainUniforms &uniforms [[buffer(1)]])
{
    TerrainVarying out;
    float4 p = float4(vertices[vertex_id].position, 1.0);
    out.position = uniforms.model_view_projection * p;
    out.normal = (uniforms.model_view * float4(vertices[vertex_id].normal, 0.0)).xyz;
    out.texcoord = vertices[vertex_id].texcoord;
    return out;
}

fragment float4 terrain_fragment(
    TerrainVarying in [[stage_in]],
    texture2d<float> base_texture [[texture(0)]],
    sampler base_sampler [[sampler(0)]])
{
    float3 n = normalize(in.normal);
    float light = 0.35 + 0.65 * saturate(dot(n, normalize(float3(0.25, 0.9, 0.35))));
    float4 albedo = base_texture.sample(base_sampler, in.texcoord);
    return float4(albedo.rgb * light, albedo.a);
}
