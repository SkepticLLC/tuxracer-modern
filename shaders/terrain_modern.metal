#include <metal_stdlib>
using namespace metal;

struct TerrainVertex {
    float3 position;
    float3 normal;
    float2 texcoord;
    float4 terrainWeights;
};

struct TerrainUniforms {
    float4x4 viewProjection;
    float3 cameraPosition;
    float fogStart;
    float fogEnd;
    float3 sunDirection;
    float3 sunColor;
    float3 skyAmbient;
    float3 fogColor;
};

struct TerrainVarying {
    float4 position [[position]];
    float3 worldPosition;
    float3 normal;
    float2 texcoord;
    float3 terrainWeights;
};

vertex TerrainVarying terrain_modern_vertex(
    uint vid [[vertex_id]],
    const device TerrainVertex *vertices [[buffer(0)]],
    constant TerrainUniforms &u [[buffer(1)]])
{
    TerrainVarying o;
    TerrainVertex v = vertices[vid];
    o.position = u.viewProjection * float4(v.position, 1.0);
    o.worldPosition = v.position;
    o.normal = v.normal;
    o.texcoord = v.texcoord;
    o.terrainWeights = max(v.terrainWeights.xyz, float3(0.0));
    return o;
}

fragment float4 terrain_modern_fragment(
    TerrainVarying in [[stage_in]],
    constant TerrainUniforms &u [[buffer(1)]],
    texture2d<float> snow [[texture(0)]],
    texture2d<float> rock [[texture(1)]],
    texture2d<float> ice [[texture(2)]],
    sampler terrainSampler [[sampler(0)]])
{
    float3 w = in.terrainWeights;
    w /= max(w.x + w.y + w.z, 0.0001);

    float4 snowSample = snow.sample(terrainSampler, in.texcoord);
    float4 rockSample = rock.sample(terrainSampler, in.texcoord);
    float4 iceSample  = ice.sample(terrainSampler, in.texcoord);
    float3 albedo = snowSample.rgb * w.x + rockSample.rgb * w.y + iceSample.rgb * w.z;

    float3 n = normalize(in.normal);
    float ndotl = saturate(dot(n, normalize(-u.sunDirection)));
    float hemi = 0.5 + 0.5 * saturate(n.y);
    float3 lighting = u.skyAmbient * (0.55 + 0.45 * hemi) + u.sunColor * ndotl;
    float3 lit = albedo * lighting;

    float distanceFromCamera = distance(in.worldPosition, u.cameraPosition);
    float fog = smoothstep(u.fogStart, u.fogEnd, distanceFromCamera);
    float3 finalColor = mix(lit, u.fogColor, fog);

    return float4(finalColor, 1.0);
}
