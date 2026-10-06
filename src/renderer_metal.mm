/*
 * Tux Racer Modern Metal backend foundation.
 *
 * OpenGL still presents pixels in this milestone. Metal owns real GPU
 * resources in parallel so terrain data can be validated before presentation
 * switches backends.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <stdio.h>
#include <string.h>
#include <mach/mach_time.h>
#include "renderer_metal.h"
#include "course_load.h"
#include "metal_present.h"
#include "fonts.h"
#include "tex_font_metrics.h"
#include "image.h"

static id<MTLDevice> g_device = nil;
static id<MTLCommandQueue> g_command_queue = nil;
static id<MTLBuffer> g_course_vertex_buffer = nil;
static id<MTLBuffer> g_last_index_buffer = nil;
static id<MTLLibrary> g_terrain_library = nil;
static id<MTLRenderPipelineState> g_terrain_pipeline = nil;
static id<MTLRenderPipelineState> g_sky_pipeline = nil;
static id<MTLRenderPipelineState> g_billboard_pipeline = nil;
static id<MTLRenderPipelineState> g_sphere_pipeline = nil;
static id<MTLRenderPipelineState> g_overlay_pipeline = nil;
static id<MTLRenderPipelineState> g_ui_image_pipeline = nil;
static NSMutableDictionary<NSString *, id<MTLTexture>> *g_ui_textures = nil;
static id<MTLRenderPipelineState> g_text_pipeline = nil;
static id<MTLRenderPipelineState> g_shadow_pipeline = nil;
static id<MTLRenderPipelineState> g_skybox_pipeline = nil;
static id<MTLRenderPipelineState> g_mountain_pipeline = nil;
static id<MTLRenderPipelineState> g_mountain_card_pipeline = nil;
static id<MTLDepthStencilState> g_depth_readonly_state = nil;
static id<MTLDepthStencilState> g_depth_state = nil;
static id<MTLDepthStencilState> g_no_depth_state = nil;
static id<MTLBuffer> g_camera_uniform_buffer = nil;
static char g_device_name[256] = {0};
static size_t g_vertex_bytes = 0;
static size_t g_last_index_bytes = 0;
static unsigned long long g_batch_count = 0;
static id<MTLTexture> g_offscreen_color = nil;
static id<MTLTexture> g_offscreen_depth = nil;
static id<MTLCommandBuffer> g_frame_command_buffer = nil;
static id<MTLRenderCommandEncoder> g_frame_encoder = nil;
static MTLRenderPassDescriptor *g_frame_pass = nil;
static int g_offscreen_width = 0;
static int g_offscreen_height = 0;
static unsigned long long g_draw_count = 0;
static id<CAMetalDrawable> g_native_drawable = nil;
static int g_native_frame_active = 0;
static int g_native_width = 0;
static int g_native_height = 0;
static int g_pacing_log_enabled = 1;
static uint64_t g_pacing_last_present_ns = 0;
static uint64_t g_pacing_drawable_start_ns = 0;
static uint64_t g_pacing_frame_start_ns = 0;
static double g_pacing_sum_ms = 0.0;
static double g_pacing_min_ms = 1000000.0;
static double g_pacing_max_ms = 0.0;
static unsigned int g_pacing_samples = 0;
static float g_mountain_parallax_x = 0.0f;
static tux_texture_handle_t g_mountain_far_handle = TUX_INVALID_TEXTURE_HANDLE;
static tux_texture_handle_t g_mountain_mid_handle = TUX_INVALID_TEXTURE_HANDLE;
static tux_texture_handle_t g_mountain_foothill_handle = TUX_INVALID_TEXTURE_HANDLE;
static tux_texture_handle_t g_menu_mountain_far_handle = TUX_INVALID_TEXTURE_HANDLE;
static tux_texture_handle_t g_menu_mountain_mid_handle = TUX_INVALID_TEXTURE_HANDLE;
static tux_texture_handle_t g_menu_mountain_foothill_handle = TUX_INVALID_TEXTURE_HANDLE;

static uint64_t renderer_metal_now_ns( void )
{
    static mach_timebase_info_data_t tb = {0,0};
    uint64_t t = mach_absolute_time();
    if ( tb.denom == 0 ) mach_timebase_info( &tb );
    return t * tb.numer / tb.denom;
}

void renderer_metal_set_frame_pacing_log( int enabled )
{
    g_pacing_log_enabled = enabled ? 1 : 0;
}

static int g_capture_written = 1; /* diagnostic PPM capture disabled by default */
static NSMutableDictionary<NSNumber *, id<MTLTexture>> *g_textures = nil;
static id<MTLSamplerState> g_repeat_sampler = nil;
static id<MTLSamplerState> g_clamp_sampler = nil;
static tux_texture_handle_t g_snow_handle = TUX_INVALID_TEXTURE_HANDLE;
static tux_texture_handle_t g_rock_handle = TUX_INVALID_TEXTURE_HANDLE;
static tux_texture_handle_t g_ice_handle = TUX_INVALID_TEXTURE_HANDLE;

int renderer_metal_probe( void )
{
    @autoreleasepool {
        if ( g_device == nil ) {
            g_device = MTLCreateSystemDefaultDevice();
            if ( g_device == nil ) {
                return 0;
            }

            const char *name = [[g_device name] UTF8String];
            if ( name != NULL ) {
                snprintf( g_device_name, sizeof(g_device_name), "%s", name );
            }
        }
        return 1;
    }
}

const char *renderer_metal_device_name( void )
{
    return g_device_name[0] != '\0' ? g_device_name : "Unavailable";
}

int renderer_metal_initialize_resources( void )
{
    @autoreleasepool {
        if ( !renderer_metal_probe() ) {
            return 0;
        }
        if ( g_command_queue == nil ) {
            g_command_queue = [g_device newCommandQueue];
        }
        if ( g_textures == nil ) {
            g_textures = [[NSMutableDictionary alloc] init];
        }
        if ( g_repeat_sampler == nil ) {
            MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
            sd.minFilter = MTLSamplerMinMagFilterLinear;
            sd.magFilter = MTLSamplerMinMagFilterLinear;
            sd.mipFilter = MTLSamplerMipFilterNotMipmapped;
            sd.sAddressMode = MTLSamplerAddressModeRepeat;
            sd.tAddressMode = MTLSamplerAddressModeRepeat;
            g_repeat_sampler = [g_device newSamplerStateWithDescriptor:sd];
        }
        if ( g_clamp_sampler == nil ) {
            MTLSamplerDescriptor *sd = [[MTLSamplerDescriptor alloc] init];
            sd.minFilter = MTLSamplerMinMagFilterLinear;
            sd.magFilter = MTLSamplerMinMagFilterLinear;
            sd.mipFilter = MTLSamplerMipFilterNotMipmapped;
            sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
            sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
            g_clamp_sampler = [g_device newSamplerStateWithDescriptor:sd];
        }

        if ( g_terrain_library == nil ) {
            NSString *source = @
                "#include <metal_stdlib>\n"
                "using namespace metal;\n"
                "struct TerrainVertex { packed_float3 position; packed_float3 normal; float2 texcoord; float4 terrainWeights; };\n"
                "struct TerrainUniforms { float4x4 viewProjection; float4 cameraAndFogStart; float4 fogEndAndPad; };\n"
                "struct TerrainVarying { float4 position [[position]]; float3 worldPosition; float3 normal; float2 texcoord; float3 weights; };\n"                "struct SkyOut { float4 position [[position]]; float2 uv; };\n"
                "vertex SkyOut sky_vertex(uint vid [[vertex_id]]) { "
                "float2 p[3]={float2(-1.0,-1.0),float2(3.0,-1.0),float2(-1.0,3.0)}; "
                "SkyOut o; o.position=float4(p[vid],0.9999,1.0); o.uv=p[vid]*0.5+0.5; return o; }\n"
                "float skyhash(float2 p){ return fract(sin(dot(p,float2(127.1,311.7)))*43758.5453); }\n"
                "float skynoise(float2 p){ float2 i=floor(p),f=fract(p); f=f*f*(3.0-2.0*f); "
                "return mix(mix(skyhash(i),skyhash(i+float2(1,0)),f.x),mix(skyhash(i+float2(0,1)),skyhash(i+float2(1,1)),f.x),f.y); }\n"
                "float skyfbm(float2 p){ float v=0.0,a=0.5; for(int i=0;i<4;i++){v+=a*skynoise(p);p=p*2.03+17.1;a*=0.5;}return v;}\n"
                "fragment float4 sky_fragment(SkyOut in [[stage_in]]) { "
                "float2 uv=in.uv; float y=saturate(uv.y); "
                "float3 horizon=float3(0.72,0.82,0.93); float3 mid=float3(0.34,0.56,0.80); float3 zenith=float3(0.10,0.30,0.58); "
                "float3 c=mix(horizon,mid,smoothstep(0.02,0.48,y)); c=mix(c,zenith,smoothstep(0.45,1.0,y)); "
                "float haze=exp(-y*8.0); c=mix(c,float3(0.82,0.87,0.93),haze*0.22); "
                "float2 sunPos=float2(0.82,0.70); float sd=distance(uv,sunPos); "
                "float sunCore=exp(-sd*145.0); float sunGlow=exp(-sd*19.0); "
                "c+=float3(1.0,0.90,0.70)*(sunCore*0.62+sunGlow*0.075); "
                "float cloudBand=smoothstep(0.18,0.34,y)*(1.0-smoothstep(0.72,0.88,y)); "
                "float n=skyfbm(float2(uv.x*7.0,uv.y*18.0)+float2(3.7,9.2)); "
                "float wisps=smoothstep(0.69,0.84,n)*cloudBand; "
                "float highN=skyfbm(float2(uv.x*13.0,uv.y*30.0)+float2(21.0,4.0)); "
                "wisps+=smoothstep(0.76,0.89,highN)*smoothstep(0.50,0.67,y)*(1.0-smoothstep(0.86,0.96,y))*0.38; "
                "c=mix(c,float3(0.96,0.97,0.99),saturate(wisps)*0.38); "
                "return float4(c,1.0); }\n"
                "struct ObjectVertex { packed_float3 position; float uv0; float uv1; float pad; };\n"
                "struct ObjectOut { float4 position [[position]]; float2 uv; float alpha; float mode; };\n"
                "vertex ObjectOut object_vertex(uint vid [[vertex_id]], const device ObjectVertex *v [[buffer(0)]], constant TerrainUniforms &u [[buffer(1)]]) { "
                "ObjectOut o; o.position=u.viewProjection*float4(float3(v[vid].position),1.0); o.uv=float2(v[vid].uv0,v[vid].uv1); "
                "o.mode=(v[vid].pad<0.0?1.0:0.0); o.alpha=(v[vid].pad>0.0?v[vid].pad:1.0); return o; }\n"
                "fragment float4 object_fragment(ObjectOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler samp [[sampler(0)]]) { "
                "float4 c=tex.sample(samp,in.uv); "
                "if(in.mode>0.5){ float mx=max(c.r,max(c.g,c.b)); float mn=min(c.r,min(c.g,c.b)); float sat=mx-mn; "
                "float green=smoothstep(0.02,0.16,c.g-max(c.r,c.b))*smoothstep(0.08,0.28,sat); "
                "float lum=dot(c.rgb,float3(0.299,0.587,0.114)); "
                "float3 charcoal=mix(float3(0.055,0.065,0.075),float3(0.16,0.18,0.20),lum); "
                "float3 red=mix(float3(0.38,0.035,0.03),float3(0.72,0.07,0.055),lum); "
                "c.rgb=mix(c.rgb,mix(charcoal,red,smoothstep(0.30,0.72,lum)),green); } "
                "c.a*=in.alpha; if(c.a<0.05) discard_fragment(); return c; }\n"
                "struct SphereVertex { packed_float3 position; packed_float3 normal; };\n"
                "struct SphereUniforms { float4x4 mvp; float4x4 model; float4 color; };\n"
                "struct SphereOut { float4 position [[position]]; float3 normal; float4 color; };\n"
                "vertex SphereOut sphere_vertex(uint vid [[vertex_id]], const device SphereVertex *v [[buffer(0)]], constant SphereUniforms &u [[buffer(1)]]) { "
                "SphereOut o; o.position=u.mvp*float4(float3(v[vid].position),1.0); "
                "o.normal=normalize((u.model*float4(float3(v[vid].normal),0.0)).xyz); o.color=u.color; return o; }\n"
                "fragment float4 sphere_fragment(SphereOut in [[stage_in]]) { "
                "float3 L=normalize(float3(-0.35,0.82,0.44)); float d=max(dot(normalize(in.normal),L),0.0); "
                "float light=0.34+0.66*d; return float4(in.color.rgb*light,in.color.a); }\n"
                "struct OverlayVertex { packed_float2 position; };\n"
                "struct OverlayUniforms { float4 color; };\n"
                "struct TextVertex { packed_float2 position; packed_float2 uv; };\n"
                "struct TextOut { float4 position [[position]]; float2 uv; };\n"
                "vertex TextOut text_vertex(uint vid [[vertex_id]], const device TextVertex *v [[buffer(0)]]) { TextOut o; o.position=float4(float2(v[vid].position),0,1); o.uv=float2(v[vid].uv); return o; }\n"
                "fragment float4 text_fragment(TextOut in [[stage_in]], constant OverlayUniforms &u [[buffer(0)]], texture2d<float> tex [[texture(0)]], sampler samp [[sampler(0)]]) { float4 s=tex.sample(samp,in.uv); float lum=max(s.r,max(s.g,s.b)); float a=s.a<0.999? s.a : lum; return float4(u.color.rgb,u.color.a*a); }\n"
                "struct OverlayOut { float4 position [[position]]; };\n"
                "vertex OverlayOut overlay_vertex(uint vid [[vertex_id]], const device OverlayVertex *v [[buffer(0)]]) { "
                "OverlayOut o; o.position=float4(float2(v[vid].position),0.0,1.0); return o; }\n"
                "fragment float4 overlay_fragment(OverlayOut in [[stage_in]], constant OverlayUniforms &u [[buffer(0)]]) { return u.color; }\n"
                "struct ShadowVertex { packed_float3 position; float alpha; };\n"
                "struct ShadowOut { float4 position [[position]]; float alpha; float radial; };\n"
                "vertex ShadowOut shadow_vertex(uint vid [[vertex_id]], const device ShadowVertex *v [[buffer(0)]], constant TerrainUniforms &u [[buffer(1)]]) { "
                "ShadowOut o; float3 p=float3(v[vid].position); o.position=u.viewProjection*float4(p,1.0); "
                "o.alpha=v[vid].alpha; o.radial=(vid==0)?0.0:1.0; return o; }\n"
                "fragment float4 shadow_fragment(ShadowOut in [[stage_in]]) { "
                "float a=in.alpha*(1.0-smoothstep(0.15,1.0,in.radial)); return float4(0.02,0.03,0.04,a); }\n"
                "struct SkyboxVertex { packed_float3 position; float uv0; float uv1; float pad; };\n"
                "struct SkyboxUniforms { float4x4 viewProjection; };\n"
                "struct SkyboxOut { float4 position [[position]]; float2 uv; };\n"
                "vertex SkyboxOut skybox_vertex(uint vid [[vertex_id]], const device SkyboxVertex *v [[buffer(0)]], constant SkyboxUniforms &u [[buffer(1)]]) { "
                "SkyboxOut o; float4 p=u.viewProjection*float4(float3(v[vid].position),1.0); "
                "o.position=float4(p.xy,p.w*0.9999,p.w); o.uv=float2(v[vid].uv0,v[vid].uv1); return o; }\n"
                "fragment float4 skybox_fragment(SkyboxOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler samp [[sampler(0)]]) { "
                "float4 c=tex.sample(samp,in.uv); return float4(c.rgb,1.0); }\n"
                "struct MountainUniforms { float parallaxX; float pad0; float pad1; float pad2; };\n"
                "struct MountainOut { float4 position [[position]]; float2 uv; };\n"
                "vertex MountainOut mountain_vertex(uint vid [[vertex_id]]) { "
                "float2 p[3]={float2(-1.0,-1.0),float2(3.0,-1.0),float2(-1.0,3.0)}; "
                "MountainOut o; o.position=float4(p[vid],0.9998,1.0); o.uv=p[vid]*0.5+0.5; return o; }\n"
                "float triPeak(float x,float c,float w,float h){ return h*max(0.0,1.0-abs(x-c)/w); }\n"
                "float rockyRidge(float x,float shift,float layer){ "
                "x=fract(x+shift); float h=0.22; "
                "h+=triPeak(x,0.08,0.12,0.22+layer*0.03); h+=triPeak(x,0.24,0.17,0.34); "
                "h+=triPeak(x,0.43,0.10,0.28); h+=triPeak(x,0.59,0.19,0.40-layer*0.03); "
                "h+=triPeak(x,0.78,0.13,0.31); h+=triPeak(x,0.93,0.18,0.25); "
                "h+=0.018*sin(x*83.0+layer*7.0); return h; }\n"
                "fragment float4 mountain_fragment(MountainOut in [[stage_in]], constant MountainUniforms &mu [[buffer(0)]]) { "
                "float x=in.uv.x+mu.parallaxX; float y=in.uv.y; "
                "float farH=rockyRidge(x*0.72,0.07,1.0); float midH=rockyRidge(x*0.90,0.31,0.0)-0.055; "
                "float aFar=1.0-smoothstep(farH-0.004,farH+0.004,y); "
                "float aMid=1.0-smoothstep(midH-0.004,midH+0.004,y); "
                "float snowFar=smoothstep(farH-0.075,farH-0.012,y)*aFar; "
                "float snowMid=smoothstep(midH-0.095,midH-0.014,y)*aMid; "
                "float3 farC=float3(0.42,0.50,0.59); float3 midC=float3(0.24,0.29,0.34); "
                "float3 c=mix(farC,float3(0.88,0.91,0.94),snowFar*0.82); "
                "c=mix(c,mix(midC,float3(0.94,0.95,0.96),snowMid*0.88),aMid); "
                "float a=max(aFar*0.62,aMid*0.90); return float4(c,a); }\n"
                "struct MountainCardVertex { packed_float3 position; float uv0; float uv1; float pad; };\n"
                "struct MountainCardOut { float4 position [[position]]; float2 uv; float alpha; };\n"
                "vertex MountainCardOut mountain_card_vertex(uint vid [[vertex_id]], const device MountainCardVertex *v [[buffer(0)]], constant TerrainUniforms &u [[buffer(1)]]) { "
                "MountainCardOut o; o.position=float4(float3(v[vid].position),1.0); "
                "o.uv=float2(v[vid].uv0,v[vid].uv1); o.alpha=v[vid].pad; return o; }\n"
                "fragment float4 mountain_card_fragment(MountainCardOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler samp [[sampler(0)]]) { "
                "float4 c=tex.sample(samp,in.uv); "
                "float blueDom=c.b-max(c.r,c.g); float cyanDom=min(c.g,c.b)-c.r; "
                "float bright=max(c.r,max(c.g,c.b)); "
                "float skyBlue=smoothstep(0.015,0.10,blueDom+cyanDom*0.55)*smoothstep(0.34,0.62,bright); "
                "float topBias=smoothstep(0.46,0.98,in.uv.y); "
                "float skyKey=saturate(skyBlue*(0.72+0.28*topBias)); "
                "float cloudNeutral=1.0-smoothstep(0.035,0.14,max(abs(c.r-c.g),abs(c.g-c.b))); "
                "float cloudBright=smoothstep(0.62,0.92,bright)*cloudNeutral*topBias; "
                "float a=c.a*in.alpha*(1.0-saturate(max(skyKey,cloudBright*0.88))); "
                "if(a<0.025) discard_fragment(); return float4(c.rgb,a); }\n"
                "vertex TerrainVarying terrain_vertex(uint vid [[vertex_id]], const device TerrainVertex *v [[buffer(0)]], constant TerrainUniforms &u [[buffer(1)]]) { "
                "TerrainVarying o; o.position=u.viewProjection*float4(v[vid].position,1.0); o.worldPosition=v[vid].position; o.normal=v[vid].normal; o.texcoord=v[vid].texcoord; o.weights=max(v[vid].terrainWeights.xyz,float3(0.0)); return o; }\n"
                "fragment float4 terrain_fragment(TerrainVarying in [[stage_in]], constant TerrainUniforms &u [[buffer(1)]], texture2d<float> snow [[texture(0)]], texture2d<float> rock [[texture(1)]], texture2d<float> ice [[texture(2)]], sampler samp [[sampler(0)]]) { "
                "float3 w=in.weights/max(in.weights.x+in.weights.y+in.weights.z,0.0001); "
                "float2 macroUV=in.texcoord; float2 detailUV=in.texcoord*7.5; float2 microUV=in.texcoord*23.0; "
                "float3 snowMacro=snow.sample(samp,macroUV).rgb; float3 snowDetail=snow.sample(samp,detailUV).rgb; "
                "float3 snowMicro=snow.sample(samp,microUV+float2(in.worldPosition.z*0.003,in.worldPosition.x*0.002)).rgb; "
                "float3 rockBase=rock.sample(samp,macroUV*0.85).rgb; float3 iceBase=ice.sample(samp,macroUV*1.15).rgb; "
                "float detailLum=dot(snowDetail,float3(0.3333)); float microLum=dot(snowMicro,float3(0.3333)); "
                "float ripple=0.5+0.5*sin(in.worldPosition.x*0.32+in.worldPosition.z*0.11); "
                "float snowVar=0.82+0.13*detailLum+0.07*microLum+0.025*ripple; "
                "float3 snowMat=snowMacro*snowVar*float3(0.985,0.995,1.02); "
                "float3 rockMat=rockBase*float3(0.78,0.75,0.72); "
                "float3 iceMat=iceBase*float3(0.80,0.93,1.10); "
                "float3 albedo=snowMat*w.x+rockMat*w.y+iceMat*w.z; "
                "float3 n=normalize(in.normal); float3 sunDir=normalize(float3(-0.28,-0.90,-0.32)); "
                "float ndl=saturate(dot(n,-sunDir)); float up=saturate(n.y); float hemi=0.54+0.46*up; "
                "float slopeShadow=(1.0-up)*(1.0-ndl); "
                "float3 ambient=mix(float3(0.40,0.50,0.66),float3(0.56,0.62,0.72),up)*hemi; "
                "float3 sun=float3(0.92,0.88,0.80)*ndl; "
                "float snowSpark=pow(saturate(ndl*(0.88+0.12*microLum)),42.0)*w.x*(0.035+0.055*microLum); "
                "float iceGlint=pow(saturate(ndl),56.0)*w.z*0.28; "
                "float3 lit=albedo*(ambient+sun); "
                "lit=mix(lit,lit*float3(0.82,0.91,1.05),slopeShadow*w.x*0.32); "
                "lit+=float3(0.96,0.98,1.0)*snowSpark+float3(0.70,0.86,1.0)*iceGlint; "
                "float d=distance(in.worldPosition,u.cameraAndFogStart.xyz); "
                "float fog=smoothstep(u.cameraAndFogStart.w,u.fogEndAndPad.x,d)*0.55; "
                "float3 fogColor=float3(0.68,0.77,0.88); return float4(mix(lit,fogColor,fog),1.0); "
                "}\n";

            NSError *error = nil;
            g_terrain_library = [g_device newLibraryWithSource:source
                                                       options:nil
                                                         error:&error];
            if ( g_terrain_library == nil ) {
                fprintf( stderr, "Tux Racer Modern: Metal shader compile failed: %s\n",
                         error ? [[error localizedDescription] UTF8String] : "unknown error" );
                return 0;
            }

            id<MTLFunction> vertex =
                [g_terrain_library newFunctionWithName:@"terrain_vertex"];
            id<MTLFunction> fragment =
                [g_terrain_library newFunctionWithName:@"terrain_fragment"];

            MTLRenderPipelineDescriptor *desc =
                [[MTLRenderPipelineDescriptor alloc] init];
            desc.vertexFunction = vertex;
            desc.fragmentFunction = fragment;
            desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
            desc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;

            g_terrain_pipeline =
                [g_device newRenderPipelineStateWithDescriptor:desc error:&error];
            if ( g_terrain_pipeline == nil ) {
                fprintf( stderr, "Tux Racer Modern: Metal pipeline creation failed: %s\n",
                         error ? [[error localizedDescription] UTF8String] : "unknown error" );
                return 0;
            }

            {
                id<MTLFunction> skyVertex =
                    [g_terrain_library newFunctionWithName:@"sky_vertex"];
                id<MTLFunction> skyFragment =
                    [g_terrain_library newFunctionWithName:@"sky_fragment"];
                MTLRenderPipelineDescriptor *skyDesc =
                    [[MTLRenderPipelineDescriptor alloc] init];
                skyDesc.vertexFunction = skyVertex;
                skyDesc.fragmentFunction = skyFragment;
                skyDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
                skyDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
                g_sky_pipeline =
                    [g_device newRenderPipelineStateWithDescriptor:skyDesc error:&error];
                if ( g_sky_pipeline == nil ) {
                    fprintf( stderr, "Tux Racer Modern: Metal sky pipeline creation failed: %s\n",
                             error ? [[error localizedDescription] UTF8String] : "unknown error" );
                    return 0;
                }
            }

            {
                id<MTLFunction> objectVertex =
                    [g_terrain_library newFunctionWithName:@"object_vertex"];
                id<MTLFunction> objectFragment =
                    [g_terrain_library newFunctionWithName:@"object_fragment"];
                MTLRenderPipelineDescriptor *objectDesc =
                    [[MTLRenderPipelineDescriptor alloc] init];
                objectDesc.vertexFunction = objectVertex;
                objectDesc.fragmentFunction = objectFragment;
                objectDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
                objectDesc.colorAttachments[0].blendingEnabled = YES;
                objectDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
                objectDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
                objectDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
                g_billboard_pipeline =
                    [g_device newRenderPipelineStateWithDescriptor:objectDesc error:&error];
                if ( g_billboard_pipeline == nil ) {
                    fprintf( stderr, "Tux Racer Modern: Metal object pipeline creation failed: %s\n",
                             error ? [[error localizedDescription] UTF8String] : "unknown error" );
                    return 0;
                }
            }

            {
                id<MTLFunction> sphereVertex =
                    [g_terrain_library newFunctionWithName:@"sphere_vertex"];
                id<MTLFunction> sphereFragment =
                    [g_terrain_library newFunctionWithName:@"sphere_fragment"];
                MTLRenderPipelineDescriptor *sphereDesc =
                    [[MTLRenderPipelineDescriptor alloc] init];
                sphereDesc.vertexFunction = sphereVertex;
                sphereDesc.fragmentFunction = sphereFragment;
                sphereDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
                sphereDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
                g_sphere_pipeline =
                    [g_device newRenderPipelineStateWithDescriptor:sphereDesc error:&error];
                if ( g_sphere_pipeline == nil ) {
                    fprintf( stderr, "Tux Racer Modern: Metal sphere pipeline creation failed: %s\n",
                             error ? [[error localizedDescription] UTF8String] : "unknown error" );
                    return 0;
                }
            }

            {
                id<MTLFunction> overlayVertex =
                    [g_terrain_library newFunctionWithName:@"overlay_vertex"];
                id<MTLFunction> overlayFragment =
                    [g_terrain_library newFunctionWithName:@"overlay_fragment"];
                MTLRenderPipelineDescriptor *overlayDesc =
                    [[MTLRenderPipelineDescriptor alloc] init];
                overlayDesc.vertexFunction = overlayVertex;
                overlayDesc.fragmentFunction = overlayFragment;
                overlayDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
                overlayDesc.colorAttachments[0].blendingEnabled = YES;
                overlayDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
                overlayDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
                overlayDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
                g_overlay_pipeline =
                    [g_device newRenderPipelineStateWithDescriptor:overlayDesc error:&error];
                if ( g_overlay_pipeline == nil ) {
                    fprintf( stderr, "Tux Racer Modern: Metal overlay pipeline creation failed: %s\n",
                             error ? [[error localizedDescription] UTF8String] : "unknown error" );
                    return 0;
                }
            }

            { id<MTLFunction> v=[g_terrain_library newFunctionWithName:@"text_vertex"]; id<MTLFunction> f=[g_terrain_library newFunctionWithName:@"text_fragment"]; MTLRenderPipelineDescriptor *d=[[MTLRenderPipelineDescriptor alloc]init]; d.vertexFunction=v;d.fragmentFunction=f;d.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;d.colorAttachments[0].blendingEnabled=YES;d.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;d.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;d.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;g_text_pipeline=[g_device newRenderPipelineStateWithDescriptor:d error:&error];if(!g_text_pipeline){fprintf(stderr,"Tux Racer Modern: text pipeline failed: %s\n",error?[[error localizedDescription]UTF8String]:"unknown");return 0;} }

            {
                id<MTLFunction> shadowVertex =
                    [g_terrain_library newFunctionWithName:@"shadow_vertex"];
                id<MTLFunction> shadowFragment =
                    [g_terrain_library newFunctionWithName:@"shadow_fragment"];
                MTLRenderPipelineDescriptor *shadowDesc =
                    [[MTLRenderPipelineDescriptor alloc] init];
                shadowDesc.vertexFunction = shadowVertex;
                shadowDesc.fragmentFunction = shadowFragment;
                shadowDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
                shadowDesc.colorAttachments[0].blendingEnabled = YES;
                shadowDesc.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
                shadowDesc.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
                shadowDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
                g_shadow_pipeline =
                    [g_device newRenderPipelineStateWithDescriptor:shadowDesc error:&error];
                if ( g_shadow_pipeline == nil ) {
                    fprintf( stderr, "Tux Racer Modern: Metal shadow pipeline creation failed: %s\n",
                             error ? [[error localizedDescription] UTF8String] : "unknown error" );
                    return 0;
                }
            }

            {
                id<MTLFunction> skyboxVertex =
                    [g_terrain_library newFunctionWithName:@"skybox_vertex"];
                id<MTLFunction> skyboxFragment =
                    [g_terrain_library newFunctionWithName:@"skybox_fragment"];
                MTLRenderPipelineDescriptor *skyboxDesc =
                    [[MTLRenderPipelineDescriptor alloc] init];
                skyboxDesc.vertexFunction = skyboxVertex;
                skyboxDesc.fragmentFunction = skyboxFragment;
                skyboxDesc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
                skyboxDesc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
                g_skybox_pipeline =
                    [g_device newRenderPipelineStateWithDescriptor:skyboxDesc error:&error];
                if ( g_skybox_pipeline == nil ) {
                    fprintf( stderr, "Tux Racer Modern: Metal skybox pipeline creation failed: %s\n",
                             error ? [[error localizedDescription] UTF8String] : "unknown error" );
                    return 0;
                }
            }

            {
                id<MTLFunction> mv=[g_terrain_library newFunctionWithName:@"mountain_vertex"];
                id<MTLFunction> mf=[g_terrain_library newFunctionWithName:@"mountain_fragment"];
                MTLRenderPipelineDescriptor *md=[[MTLRenderPipelineDescriptor alloc] init];
                md.vertexFunction=mv; md.fragmentFunction=mf;
                md.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
                md.colorAttachments[0].blendingEnabled=YES;
                md.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;
                md.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
                md.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
                g_mountain_pipeline=[g_device newRenderPipelineStateWithDescriptor:md error:&error];
                if(g_mountain_pipeline==nil){
                    fprintf(stderr,"Tux Racer Modern: Metal mountain pipeline creation failed: %s\n",
                            error?[[error localizedDescription] UTF8String]:"unknown error");
                    return 0;
                }
            }

            {
                id<MTLFunction> mv=[g_terrain_library newFunctionWithName:@"mountain_card_vertex"];
                id<MTLFunction> mf=[g_terrain_library newFunctionWithName:@"mountain_card_fragment"];
                MTLRenderPipelineDescriptor *md=[[MTLRenderPipelineDescriptor alloc] init];
                md.vertexFunction=mv; md.fragmentFunction=mf;
                md.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
                md.colorAttachments[0].blendingEnabled=YES;
                md.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;
                md.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
                md.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
                g_mountain_card_pipeline=[g_device newRenderPipelineStateWithDescriptor:md error:&error];
                if(g_mountain_card_pipeline==nil){
                    fprintf(stderr,"Tux Racer Modern: Metal mountain-card pipeline creation failed: %s\n",
                            error?[[error localizedDescription] UTF8String]:"unknown error");
                    return 0;
                }
            }

            MTLDepthStencilDescriptor *depthDesc = [[MTLDepthStencilDescriptor alloc] init];
            depthDesc.depthCompareFunction = MTLCompareFunctionLessEqual;
            depthDesc.depthWriteEnabled = YES;
            g_depth_state = [g_device newDepthStencilStateWithDescriptor:depthDesc];
            {
                MTLDepthStencilDescriptor *readOnlyDesc =
                    [[MTLDepthStencilDescriptor alloc] init];
                readOnlyDesc.depthCompareFunction = MTLCompareFunctionLessEqual;
                readOnlyDesc.depthWriteEnabled = NO;
                g_depth_readonly_state =
                    [g_device newDepthStencilStateWithDescriptor:readOnlyDesc];
            }
            {
                MTLDepthStencilDescriptor *noDepthDesc =
                    [[MTLDepthStencilDescriptor alloc] init];
                noDepthDesc.depthCompareFunction = MTLCompareFunctionAlways;
                noDepthDesc.depthWriteEnabled = NO;
                g_no_depth_state =
                    [g_device newDepthStencilStateWithDescriptor:noDepthDesc];
            }
            if ( g_depth_state == nil ) {
                fprintf( stderr, "Tux Racer Modern: Metal depth state creation failed\n" );
                return 0;
            }

            if ( g_ui_image_pipeline == nil ) {
                NSString *uiSource =
                    @"#include <metal_stdlib>\n"
                     "using namespace metal;\n"
                     "struct UIVertex { packed_float2 position; packed_float2 uv; };\n"
                     "struct UIOut { float4 position [[position]]; float2 uv; };\n"
                     "vertex UIOut ui_image_vertex(uint vid [[vertex_id]], const device UIVertex *v [[buffer(0)]]) { "
                     "UIOut o; o.position=float4(float2(v[vid].position),0.0,1.0); o.uv=float2(v[vid].uv); return o; }\n"
                     "fragment float4 ui_image_fragment(UIOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler samp [[sampler(0)]]) { "
                     "return tex.sample(samp,in.uv); }\n";
                NSError *uiError=nil;
                id<MTLLibrary> uiLibrary=[g_device newLibraryWithSource:uiSource options:nil error:&uiError];
                if(uiLibrary==nil){
                    fprintf(stderr,"Tux Racer Modern: UI shader compile failed: %s\n",
                            uiError?[[uiError localizedDescription] UTF8String]:"unknown");
                    return 0;
                }
                id<MTLFunction> uiVS=[uiLibrary newFunctionWithName:@"ui_image_vertex"];
                id<MTLFunction> uiFS=[uiLibrary newFunctionWithName:@"ui_image_fragment"];
                if(uiVS==nil||uiFS==nil){
                    fprintf(stderr,"Tux Racer Modern: UI shader functions missing after successful compile\n");
                    return 0;
                }
                MTLRenderPipelineDescriptor *uiPD=[[MTLRenderPipelineDescriptor alloc] init];
                uiPD.vertexFunction=uiVS;uiPD.fragmentFunction=uiFS;
                uiPD.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
                g_ui_image_pipeline=[g_device newRenderPipelineStateWithDescriptor:uiPD error:&uiError];
                if(g_ui_image_pipeline==nil){
                    fprintf(stderr,"Tux Racer Modern: UI image pipeline failed: %s\n",
                            uiError?[[uiError localizedDescription] UTF8String]:"unknown");
                    return 0;
                }
            }
            if(g_ui_textures==nil)g_ui_textures=[[NSMutableDictionary alloc] init];

            fprintf( stderr, "Tux Racer Modern: Metal terrain pipeline ready\n" );
            fprintf( stderr, "Tux Racer Modern: Modern UI image pipeline ready\n" );
        }

        return g_command_queue != nil && g_terrain_pipeline != nil;
    }
}

void renderer_metal_shutdown_resources( void )
{
    @autoreleasepool {
        g_frame_encoder = nil;
        g_frame_command_buffer = nil;
        g_frame_pass = nil;
        g_offscreen_depth = nil;
        g_offscreen_color = nil;
        g_last_index_buffer = nil;
        g_course_vertex_buffer = nil;
        g_camera_uniform_buffer = nil;
        g_depth_state = nil;
        g_no_depth_state = nil;
        g_terrain_pipeline = nil;
        g_sky_pipeline = nil;
        g_billboard_pipeline = nil;
        g_sphere_pipeline = nil;
        g_shadow_pipeline = nil;
        g_skybox_pipeline = nil;
        g_mountain_pipeline = nil;
        g_mountain_card_pipeline = nil;
        g_depth_readonly_state = nil;
        g_terrain_library = nil;
        [g_textures removeAllObjects];
        g_textures = nil;
        g_repeat_sampler = nil;
        g_command_queue = nil;
        g_vertex_bytes = 0;
        g_last_index_bytes = 0;
        g_batch_count = 0;
    }
}

int renderer_metal_upload_course_vertices( const tux_vertex_t *vertices,
                                           size_t vertex_count )
{
    @autoreleasepool {
        if ( vertices == NULL || vertex_count == 0 ||
             !renderer_metal_initialize_resources() ) {
            return 0;
        }

        g_vertex_bytes = sizeof(tux_vertex_t) * vertex_count;
        g_course_vertex_buffer =
            [g_device newBufferWithBytes:vertices
                                  length:g_vertex_bytes
                                 options:MTLResourceStorageModeShared];

        if ( g_course_vertex_buffer == nil ) {
            g_vertex_bytes = 0;
            return 0;
        }

        fprintf( stderr,
                 "Tux Racer Modern: Metal uploaded %zu terrain vertices (%zu bytes)\n",
                 vertex_count, g_vertex_bytes );
        return 1;
    }
}

void renderer_metal_consume_terrain_batch( const tux_terrain_batch_t *batch,
                                           void *context )
{
    (void)context;
    @autoreleasepool {
        if ( batch == NULL || batch->indices == NULL ||
             batch->index_count == 0 || g_device == nil ) {
            return;
        }

        /* Legacy snow/rock/ice passes remain OpenGL-only. */
        if ( batch->terrain_index != -2 && batch->terrain_index != -3 ) {
            return;
        }

        g_last_index_bytes = batch->index_count * sizeof(uint32_t);
        g_last_index_buffer =
            [g_device newBufferWithBytes:batch->indices
                                  length:g_last_index_bytes
                                 options:MTLResourceStorageModeShared];
        if ( g_last_index_buffer != nil ) {
            ++g_batch_count;

            if ( g_frame_encoder != nil && g_course_vertex_buffer != nil &&
                 g_terrain_pipeline != nil ) {
                [g_frame_encoder setRenderPipelineState:g_terrain_pipeline];
                [g_frame_encoder setDepthStencilState:g_depth_state];
                [g_frame_encoder setVertexBuffer:g_course_vertex_buffer offset:0 atIndex:0];
                [g_frame_encoder setVertexBuffer:g_camera_uniform_buffer offset:0 atIndex:1];
                /*
                 * Terrain textures are stable renderer handles assigned in load
                 * order, but batch->texture gives us only the active legacy
                 * pass. Bind known terrain resources by their handles below;
                 * missing slots safely retain no texture until all are loaded.
                 */
                id<MTLTexture> snow = [g_textures objectForKey:@(g_snow_handle)];
                id<MTLTexture> rock = [g_textures objectForKey:@(g_rock_handle)];
                id<MTLTexture> ice  = [g_textures objectForKey:@(g_ice_handle)];
                if ( snow != nil ) [g_frame_encoder setFragmentTexture:snow atIndex:0];
                if ( rock != nil ) [g_frame_encoder setFragmentTexture:rock atIndex:1];
                if ( ice  != nil ) [g_frame_encoder setFragmentTexture:ice  atIndex:2];
                [g_frame_encoder setFragmentSamplerState:g_repeat_sampler atIndex:0];
                [g_frame_encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
                                            indexCount:batch->index_count
                                             indexType:MTLIndexTypeUInt32
                                           indexBuffer:g_last_index_buffer
                                     indexBufferOffset:0];
                ++g_draw_count;
            }

            if ( g_batch_count <= 3 ) {
                fprintf( stderr,
                         "Tux Racer Modern: Metal terrain batch %llu: terrain=%d, indices=%zu, bytes=%zu\n",
                         g_batch_count, batch->terrain_index,
                         batch->index_count, g_last_index_bytes );
            }
        }
    }
}

void renderer_metal_reset_course_resources( void )
{
    @autoreleasepool {
        g_course_vertex_buffer = nil;
        g_last_index_buffer = nil;
        g_vertex_bytes = 0;
        g_last_index_bytes = 0;
        g_batch_count = 0;
        g_draw_count = 0;
        fprintf( stderr, "Tux Racer Modern: reset Metal course resources\n" );
    }
}

size_t renderer_metal_vertex_bytes( void ) { return g_vertex_bytes; }
size_t renderer_metal_last_index_bytes( void ) { return g_last_index_bytes; }


void renderer_metal_begin_offscreen_frame( const tux_renderer_camera_state_t *camera,
                                           int width, int height )
{
    @autoreleasepool {
        if ( camera == NULL || !camera->valid || width <= 0 || height <= 0 ||
             g_command_queue == nil || g_terrain_pipeline == nil ) {
            return;
        }

        if ( g_offscreen_color == nil ||
             width != g_offscreen_width || height != g_offscreen_height ) {
            MTLTextureDescriptor *color =
                [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                   width:(NSUInteger)width
                                                                  height:(NSUInteger)height
                                                               mipmapped:NO];
            color.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
            /* Shared storage enables a one-shot diagnostic CPU readback. */
            color.storageMode = MTLStorageModeShared;
            g_offscreen_color = [g_device newTextureWithDescriptor:color];

            MTLTextureDescriptor *depth =
                [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                   width:(NSUInteger)width
                                                                  height:(NSUInteger)height
                                                               mipmapped:NO];
            depth.usage = MTLTextureUsageRenderTarget;
            depth.storageMode = MTLStorageModePrivate;
            g_offscreen_depth = [g_device newTextureWithDescriptor:depth];

            g_offscreen_width = width;
            g_offscreen_height = height;
        }

        if ( g_offscreen_color == nil || g_offscreen_depth == nil ) {
            return;
        }

        /*
         * Convert preserved OpenGL clip space to Metal:
         *   - OpenGL Z is [-w,+w], Metal Z is [0,+w].
         *   - The diagnostic/presentation bridge uses top-left image
         *     orientation, so invert clip-space Y once at this boundary.
         *
         * Keep world/course coordinates untouched; renderer convention
         * differences belong in the projection transform.
         */
        float vp[16];
        int i;
        for ( i = 0; i < 16; ++i ) vp[i] = (float)camera->view_projection_matrix[i];
        for ( i = 0; i < 4; ++i ) {
            vp[i*4 + 1] = -(float)camera->view_projection_matrix[i*4 + 1];
            vp[i*4 + 2] = 0.5f * ((float)camera->view_projection_matrix[i*4 + 2] +
                                  (float)camera->view_projection_matrix[i*4 + 3]);
        }
        struct {
            float viewProjection[16];
            float cameraAndFogStart[4];
            float fogEndAndPad[4];
        } uniforms;
        memcpy( uniforms.viewProjection, vp, sizeof(vp) );
        uniforms.cameraAndFogStart[0] = (float)camera->position[0];
        uniforms.cameraAndFogStart[1] = (float)camera->position[1];
        uniforms.cameraAndFogStart[2] = (float)camera->position[2];
        {
            const float farClip = (float)camera->far_clip;
            /*
             * Keep nearby terrain crisp. Atmospheric perspective begins in
             * the latter half of the visible course and approaches, but does
             * not fully reach, the camera's far clip.
             */
            uniforms.cameraAndFogStart[3] = farClip * 0.68f;
            uniforms.fogEndAndPad[0] = farClip * 0.98f;
        }
        uniforms.fogEndAndPad[1] = uniforms.fogEndAndPad[2] = uniforms.fogEndAndPad[3] = 0.0f;

        g_camera_uniform_buffer =
            [g_device newBufferWithBytes:&uniforms length:sizeof(uniforms)
                                 options:MTLResourceStorageModeShared];

        g_frame_pass = [MTLRenderPassDescriptor renderPassDescriptor];
        g_frame_pass.colorAttachments[0].texture = g_offscreen_color;
        g_frame_pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        g_frame_pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        g_frame_pass.colorAttachments[0].clearColor = MTLClearColorMake(0.36, 0.48, 0.64, 1.0);
        g_frame_pass.depthAttachment.texture = g_offscreen_depth;
        g_frame_pass.depthAttachment.loadAction = MTLLoadActionClear;
        g_frame_pass.depthAttachment.storeAction = MTLStoreActionDontCare;
        g_frame_pass.depthAttachment.clearDepth = 1.0;

        g_frame_command_buffer = [g_command_queue commandBuffer];
        g_frame_encoder =
            [g_frame_command_buffer renderCommandEncoderWithDescriptor:g_frame_pass];
        g_draw_count = 0;

        /*
         * The quadtree selects visible terrain during the game render pass.
         * Consume its latest stable unified surface only after this Metal
         * frame has a camera, command buffer and encoder.
         */
        {
            const tux_terrain_batch_t *batch = terrain_get_latest_unified_batch();
            if ( batch != NULL ) {
                renderer_metal_consume_terrain_batch( batch, NULL );
            }
        }
    }
}

void renderer_metal_end_offscreen_frame( void )
{
    @autoreleasepool {
        if ( g_frame_encoder == nil || g_frame_command_buffer == nil ) {
            return;
        }

        [g_frame_encoder endEncoding];
        [g_frame_command_buffer commit];
        [g_frame_command_buffer waitUntilCompleted];

        if ( !g_capture_written &&
             g_frame_command_buffer.status == MTLCommandBufferStatusCompleted &&
             g_offscreen_color != nil && g_draw_count > 0 ) {
            const NSUInteger width = (NSUInteger)g_offscreen_width;
            const NSUInteger height = (NSUInteger)g_offscreen_height;
            const NSUInteger bytesPerRow = width * 4;
            const size_t byteCount = (size_t)bytesPerRow * (size_t)height;
            unsigned char *pixels = (unsigned char *)malloc( byteCount );

            if ( pixels != NULL ) {
                MTLRegion region = MTLRegionMake2D( 0, 0, width, height );
                [g_offscreen_color getBytes:pixels
                                bytesPerRow:bytesPerRow
                                 fromRegion:region
                                mipmapLevel:0];

                FILE *fp = fopen( "metal-terrain-frame.ppm", "wb" );
                if ( fp != NULL ) {
                    fprintf( fp, "P6\n%lu %lu\n255\n",
                             (unsigned long)width, (unsigned long)height );
                    for ( NSUInteger y = 0; y < height; ++y ) {
                        for ( NSUInteger x = 0; x < width; ++x ) {
                            const unsigned char *bgra =
                                pixels + y * bytesPerRow + x * 4;
                            fputc( bgra[2], fp );
                            fputc( bgra[1], fp );
                            fputc( bgra[0], fp );
                        }
                    }
                    fclose( fp );
                    g_capture_written = 1;
                    fprintf( stderr,
                             "Tux Racer Modern: wrote Metal diagnostic frame: metal-terrain-frame.ppm (%zu bytes)\n",
                             byteCount );
                }
                free( pixels );
            }
        }

        static int reported = 0;
        if ( !reported ) {
            if ( g_frame_command_buffer.status == MTLCommandBufferStatusCompleted ) {
                fprintf( stderr,
                         "Tux Racer Modern: Metal offscreen terrain frame completed (%llu indexed draws, %dx%d)\n",
                         g_draw_count, g_offscreen_width, g_offscreen_height );
            } else {
                NSError *error = g_frame_command_buffer.error;
                fprintf( stderr,
                         "Tux Racer Modern: Metal offscreen frame failed: %s\n",
                         error ? [[error localizedDescription] UTF8String] : "unknown error" );
            }
            reported = 1;
        }

        g_frame_encoder = nil;
        g_frame_command_buffer = nil;
        g_frame_pass = nil;
    }
}


int renderer_metal_upload_texture( tux_texture_handle_t handle,
                                   int width, int height, int channels,
                                   const unsigned char *pixels,
                                   int repeatable )
{
    (void)repeatable;
    @autoreleasepool {
        if ( handle == TUX_INVALID_TEXTURE_HANDLE || width <= 0 || height <= 0 ||
             pixels == NULL || !renderer_metal_initialize_resources() ) {
            return 0;
        }

        const size_t count = (size_t)width * (size_t)height;
        unsigned char *rgba = (unsigned char *)malloc( count * 4 );
        if ( rgba == NULL ) return 0;

        for ( size_t i = 0; i < count; ++i ) {
            if ( channels >= 3 ) {
                rgba[i*4+0] = pixels[i*channels+0];
                rgba[i*4+1] = pixels[i*channels+1];
                rgba[i*4+2] = pixels[i*channels+2];
                rgba[i*4+3] = channels >= 4 ? pixels[i*channels+3] : 255;
            } else {
                unsigned char v = pixels[i*channels];
                rgba[i*4+0] = v; rgba[i*4+1] = v; rgba[i*4+2] = v;
                rgba[i*4+3] = channels >= 2 ? pixels[i*channels+1] : 255;
            }
        }

        MTLTextureDescriptor *td =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                               width:(NSUInteger)width
                                                              height:(NSUInteger)height
                                                           mipmapped:NO];
        td.usage = MTLTextureUsageShaderRead;
        id<MTLTexture> texture = [g_device newTextureWithDescriptor:td];
        if ( texture != nil ) {
            MTLRegion region = MTLRegionMake2D( 0, 0, (NSUInteger)width, (NSUInteger)height );
            [texture replaceRegion:region mipmapLevel:0 withBytes:rgba bytesPerRow:(NSUInteger)width*4];
            [g_textures setObject:texture forKey:@(handle)];
        }
        free( rgba );
        return texture != nil;
    }
}


void renderer_metal_register_named_texture( const char *name,
                                            tux_texture_handle_t handle )
{
    if ( name == NULL ) return;
    if ( strcmp( name, "snow" ) == 0 ) g_snow_handle = handle;
    else if ( strcmp( name, "rock" ) == 0 ) g_rock_handle = handle;
    else if ( strcmp( name, "ice" ) == 0 ) g_ice_handle = handle;
    else if ( strcmp( name, "modern_mountains_far" ) == 0 ) {
        g_menu_mountain_far_handle = handle;
        g_mountain_far_handle = handle;
    } else if ( strcmp( name, "modern_mountains_mid" ) == 0 ) {
        g_menu_mountain_mid_handle = handle;
        g_mountain_mid_handle = handle;
    } else if ( strcmp( name, "modern_mountains_foothills" ) == 0 ) {
        g_menu_mountain_foothill_handle = handle;
        g_mountain_foothill_handle = handle;
    }
}


void renderer_metal_draw_start_banner( float x,float y,float z,
                                      float radius,float height,
                                      float nx,float nz,
                                      tux_texture_handle_t texture )
{
    @autoreleasepool {
        typedef struct { float px,py,pz,u,v,pad; } object_vertex_t;
        float rx=-radius*nz, rz=radius*nx;
        const object_vertex_t verts[6]={
            {x+rx,y,z+rz,0,0,-1},{x-rx,y,z-rz,1,0,-1},{x-rx,y+height,z-rz,1,1,-1},
            {x+rx,y,z+rz,0,0,-1},{x-rx,y+height,z-rz,1,1,-1},{x+rx,y+height,z+rz,0,1,-1}
        };
        if(g_frame_encoder==nil||g_billboard_pipeline==nil||g_camera_uniform_buffer==nil)return;
        id<MTLTexture> tex=[g_textures objectForKey:@(texture)]; if(tex==nil)return;
        id<MTLBuffer> vb=[g_device newBufferWithBytes:verts length:sizeof(verts) options:MTLResourceStorageModeShared];
        if(vb==nil)return;
        [g_frame_encoder setRenderPipelineState:g_billboard_pipeline];
        [g_frame_encoder setDepthStencilState:g_depth_state];
        [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
        [g_frame_encoder setVertexBuffer:g_camera_uniform_buffer offset:0 atIndex:1];
        [g_frame_encoder setFragmentTexture:tex atIndex:0];
        [g_frame_encoder setFragmentSamplerState:g_clamp_sampler atIndex:0];
        [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    }
}

int renderer_metal_read_present_frame( unsigned char *rgba,
                                       size_t rgba_bytes,
                                       int *width, int *height )
{
    @autoreleasepool {
        if ( g_offscreen_color == nil || rgba == NULL ||
             g_offscreen_width <= 0 || g_offscreen_height <= 0 ) {
            return 0;
        }

        const size_t needed = (size_t)g_offscreen_width *
                              (size_t)g_offscreen_height * 4u;
        if ( rgba_bytes < needed ) return 0;

        MTLRegion region = MTLRegionMake2D( 0, 0,
                                            (NSUInteger)g_offscreen_width,
                                            (NSUInteger)g_offscreen_height );
        [g_offscreen_color getBytes:rgba
                       bytesPerRow:(NSUInteger)g_offscreen_width * 4u
                        fromRegion:region
                       mipmapLevel:0];

        /*
         * Offscreen target is BGRA8. Convert in place for the OpenGL bridge.
         */
        for ( size_t i = 0; i < needed; i += 4 ) {
            unsigned char b = rgba[i + 0];
            rgba[i + 0] = rgba[i + 2];
            rgba[i + 2] = b;
        }

        if ( width ) *width = g_offscreen_width;
        if ( height ) *height = g_offscreen_height;
        return 1;
    }
}


int renderer_metal_attach_native_window( void *sdl_window )
{
    @autoreleasepool {
        if ( g_device == nil && !renderer_metal_probe() ) return 0;
        return metal_present_attach_to_sdl_window(
            sdl_window, (__bridge void *)g_device );
    }
}

void renderer_metal_set_native_visible( int visible )
{
    metal_present_set_visible( visible );
}

static int renderer_metal_prepare_camera_uniforms(
    const tux_renderer_camera_state_t *camera, int flip_y )
{
    float vp[16];
    int i;
    struct {
        float viewProjection[16];
        float cameraAndFogStart[4];
        float fogEndAndPad[4];
    } uniforms;

    if ( camera == NULL || !camera->valid || g_device == nil ) return 0;

    for ( i = 0; i < 16; ++i )
        vp[i] = (float)camera->view_projection_matrix[i];
    for ( i = 0; i < 4; ++i ) {
        vp[i*4 + 1] = (flip_y ? -1.0f : 1.0f) *
                        (float)camera->view_projection_matrix[i*4 + 1];
        vp[i*4 + 2] =
            0.5f * ((float)camera->view_projection_matrix[i*4 + 2] +
                    (float)camera->view_projection_matrix[i*4 + 3]);
    }

    memcpy( uniforms.viewProjection, vp, sizeof(vp) );
    uniforms.cameraAndFogStart[0] = (float)camera->position[0];
    uniforms.cameraAndFogStart[1] = (float)camera->position[1];
    uniforms.cameraAndFogStart[2] = (float)camera->position[2];
    uniforms.cameraAndFogStart[3] = (float)camera->far_clip * 0.68f;
    uniforms.fogEndAndPad[0] = (float)camera->far_clip * 0.98f;
    uniforms.fogEndAndPad[1] = 0.0f;
    uniforms.fogEndAndPad[2] = 0.0f;
    uniforms.fogEndAndPad[3] = 0.0f;

    g_camera_uniform_buffer =
        [g_device newBufferWithBytes:&uniforms
                              length:sizeof(uniforms)
                             options:MTLResourceStorageModeShared];
    return g_camera_uniform_buffer != nil;
}

void renderer_metal_set_mountain_layers( tux_texture_handle_t far_tex,
                                         tux_texture_handle_t mid_tex,
                                         tux_texture_handle_t foothill_tex )
{
    g_mountain_far_handle = far_tex;
    g_mountain_mid_handle = mid_tex;
    g_mountain_foothill_handle = foothill_tex;
    if ( far_tex != TUX_INVALID_TEXTURE_HANDLE ) g_menu_mountain_far_handle = far_tex;
    if ( mid_tex != TUX_INVALID_TEXTURE_HANDLE ) g_menu_mountain_mid_handle = mid_tex;
    if ( foothill_tex != TUX_INVALID_TEXTURE_HANDLE ) g_menu_mountain_foothill_handle = foothill_tex;
}

static void renderer_metal_draw_background_mountain_layer(
    tux_texture_handle_t handle, float bottom, float top, float alpha,
    float u0, float u1 )
{
    typedef struct { float px,py,pz,u,v,pad; } ov_t;
    ov_t v[6];
    id<MTLTexture> tex;
    id<MTLBuffer> vb;
    if(handle==TUX_INVALID_TEXTURE_HANDLE||g_frame_encoder==nil||
       g_mountain_card_pipeline==nil)return;
    tex=[g_textures objectForKey:@(handle)];
    if(tex==nil)return;
    v[0]=(ov_t){-1.02f,bottom-0.015f,0,u0,0,alpha}; v[1]=(ov_t){1.02f,bottom-0.015f,0,u1,0,alpha};
    v[2]=(ov_t){1.02f,top+0.015f,0,u1,1,alpha}; v[3]=(ov_t){-1.02f,bottom-0.015f,0,u0,0,alpha};
    v[4]=(ov_t){1.02f,top+0.015f,0,u1,1,alpha}; v[5]=(ov_t){-1.02f,top+0.015f,0,u0,1,alpha};
    vb=[g_device newBufferWithBytes:v length:sizeof(v) options:MTLResourceStorageModeShared];
    if(vb==nil)return;
    [g_frame_encoder setRenderPipelineState:g_mountain_card_pipeline];
    [g_frame_encoder setDepthStencilState:g_no_depth_state];
    [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
    [g_frame_encoder setVertexBuffer:g_camera_uniform_buffer offset:0 atIndex:1];
    [g_frame_encoder setFragmentTexture:tex atIndex:0];
    [g_frame_encoder setFragmentSamplerState:g_clamp_sampler atIndex:0];
    [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
}

int renderer_metal_begin_native_frame( const tux_renderer_camera_state_t *camera,
                                       int width, int height )
{
    @autoreleasepool {
        void *opaque;
        MTLTextureDescriptor *depth;

        if ( camera == NULL || !camera->valid || width <= 0 || height <= 0 ||
             g_command_queue == nil || g_terrain_pipeline == nil ) return 0;

        /*
         * Strict lifecycle invariant: never replace an active encoder.
         * A native frame owns exactly one command buffer and one encoder.
         */
        if ( g_frame_encoder != nil || g_frame_command_buffer != nil ) {
            fprintf( stderr,
                     "Tux Racer Modern: refusing nested native Metal frame active=%d encoder=%d command=%d drawable=%d\n",
                     g_native_frame_active,
                     g_frame_encoder!=nil,g_frame_command_buffer!=nil,g_native_drawable!=nil );
            return 0;
        }

        if ( !renderer_metal_prepare_camera_uniforms( camera, 0 ) ) return 0;

        metal_present_resize( width, height );
        g_pacing_frame_start_ns = renderer_metal_now_ns();
        g_pacing_drawable_start_ns = g_pacing_frame_start_ns;
        opaque = metal_present_next_drawable();
        if ( opaque == NULL ) return 0;
        g_native_drawable = (__bridge_transfer id<CAMetalDrawable>)opaque;
        g_native_width = width;
        g_native_height = height;

        if ( g_offscreen_depth == nil ||
             width != g_offscreen_width || height != g_offscreen_height ) {
            depth =
                [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                                   width:(NSUInteger)width
                                                                  height:(NSUInteger)height
                                                               mipmapped:NO];
            depth.usage = MTLTextureUsageRenderTarget;
            depth.storageMode = MTLStorageModePrivate;
            g_offscreen_depth = [g_device newTextureWithDescriptor:depth];
            g_offscreen_width = width;
            g_offscreen_height = height;
        }
        if ( g_offscreen_depth == nil ) {
            g_native_drawable = nil;
            g_native_width = g_native_height = 0;
            return 0;
        }

        g_frame_pass = [MTLRenderPassDescriptor renderPassDescriptor];
        g_frame_pass.colorAttachments[0].texture = g_native_drawable.texture;
        g_frame_pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        g_frame_pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        g_frame_pass.colorAttachments[0].clearColor =
            MTLClearColorMake( 0.36, 0.48, 0.64, 1.0 );
        g_frame_pass.depthAttachment.texture = g_offscreen_depth;
        g_frame_pass.depthAttachment.loadAction = MTLLoadActionClear;
        g_frame_pass.depthAttachment.storeAction = MTLStoreActionDontCare;
        g_frame_pass.depthAttachment.clearDepth = 1.0;

        g_frame_command_buffer = [g_command_queue commandBuffer];
        if ( g_frame_command_buffer == nil ) {
            g_frame_pass = nil;
            g_native_drawable = nil;
            g_native_width = g_native_height = 0;
            return 0;
        }

        g_frame_encoder =
            [g_frame_command_buffer renderCommandEncoderWithDescriptor:g_frame_pass];
        if ( g_frame_encoder == nil ) {
            g_frame_command_buffer = nil;
            g_frame_pass = nil;
            g_native_drawable = nil;
            g_native_width = g_native_height = 0;
            return 0;
        }

        g_draw_count = 0;

        /* Native scene background; terrain is encoded immediately after. */
        if ( g_sky_pipeline != nil ) {
            [g_frame_encoder setRenderPipelineState:g_sky_pipeline];
            [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle
                                vertexStart:0
                                vertexCount:3];
        }

        /* Stable distant scenery: screen-space depth layers behind terrain. */
        renderer_metal_draw_background_mountain_layer(
            g_mountain_far_handle, -0.46f, 0.34f, 0.82f, 0.00f, 1.00f );
        /*
         * The mid/foothill bindings are intentionally not submitted until
         * their unique alpha-cut assets replace the duplicated prototype
         * photographs. The compositor now supports independent crop ranges
         * so those layers do not need matching source dimensions.
         */

        /* Procedural mountain shader retained for diagnostics only.
         * Production Modern uses world-space textured mountain cards. */

        g_native_frame_active = 1;
        return 1;
    }
}

void renderer_metal_end_native_frame( void )
{
    @autoreleasepool {
        if ( !g_native_frame_active ) return;

        if ( g_frame_encoder != nil ) {
            [g_frame_encoder endEncoding];
            g_frame_encoder = nil;
        }
        if ( g_frame_command_buffer != nil && g_native_drawable != nil ) {
            [g_frame_command_buffer presentDrawable:g_native_drawable];
            [g_frame_command_buffer commit];
        }

        if ( g_pacing_log_enabled ) {
            uint64_t now = renderer_metal_now_ns();
            if ( g_pacing_last_present_ns != 0 ) {
                double frame_ms = (double)(now - g_pacing_last_present_ns) / 1000000.0;
                g_pacing_sum_ms += frame_ms;
                if ( frame_ms < g_pacing_min_ms ) g_pacing_min_ms = frame_ms;
                if ( frame_ms > g_pacing_max_ms ) g_pacing_max_ms = frame_ms;
                ++g_pacing_samples;
            }
            g_pacing_last_present_ns = now;

            if ( g_pacing_samples >= 120 ) {
                fprintf( stderr,
                         "Tux Racer Modern: Metal pacing avg %.2f ms (%.1f fps), min %.2f, max %.2f, CPU encode %.2f ms\n",
                         g_pacing_sum_ms / g_pacing_samples,
                         1000.0 / (g_pacing_sum_ms / g_pacing_samples),
                         g_pacing_min_ms, g_pacing_max_ms,
                         (double)(now - g_pacing_frame_start_ns) / 1000000.0 );
                g_pacing_sum_ms = 0.0;
                g_pacing_min_ms = 1000000.0;
                g_pacing_max_ms = 0.0;
                g_pacing_samples = 0;
            }
        }

        g_frame_command_buffer = nil;
        g_frame_pass = nil;
        g_native_drawable = nil;
        g_native_frame_active = 0;
    }
}


void renderer_metal_draw_full_grid( const tux_terrain_batch_t *batch )
{
    renderer_metal_consume_terrain_batch( batch, NULL );
}


void renderer_metal_draw_billboard_cross( float x, float y, float z,
                                          float radius, float height,
                                          tux_texture_handle_t texture )
{
    @autoreleasepool {
        typedef struct {
            float px, py, pz;
            float u, v, pad;
        } object_vertex_t;

        const object_vertex_t verts[12] = {
            {x-radius,y,z, 0,0,0}, {x+radius,y,z, 1,0,0}, {x+radius,y+height,z, 1,1,0},
            {x-radius,y,z, 0,0,0}, {x+radius,y+height,z, 1,1,0}, {x-radius,y+height,z, 0,1,0},
            {x,y,z-radius, 0,0,0}, {x,y,z+radius, 1,0,0}, {x,y+height,z+radius, 1,1,0},
            {x,y,z-radius, 0,0,0}, {x,y+height,z+radius, 1,1,0}, {x,y+height,z-radius, 0,1,0}
        };

        if ( g_frame_encoder == nil || g_billboard_pipeline == nil ||
             g_camera_uniform_buffer == nil ) return;

        id<MTLTexture> tex = [g_textures objectForKey:@(texture)];
        if ( tex == nil ) return;

        id<MTLBuffer> vb =
            [g_device newBufferWithBytes:verts length:sizeof(verts)
                                 options:MTLResourceStorageModeShared];
        if ( vb == nil ) return;

        [g_frame_encoder setRenderPipelineState:g_billboard_pipeline];
        [g_frame_encoder setDepthStencilState:g_depth_state];
        [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
        [g_frame_encoder setVertexBuffer:g_camera_uniform_buffer offset:0 atIndex:1];
        [g_frame_encoder setFragmentTexture:tex atIndex:0];
        [g_frame_encoder setFragmentSamplerState:g_repeat_sampler atIndex:0];
        [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle
                            vertexStart:0 vertexCount:12];
    }
}


void renderer_metal_draw_billboard( float x, float y, float z,
                                    float radius, float height,
                                    float nx, float nz,
                                    tux_texture_handle_t texture )
{
    @autoreleasepool {
        typedef struct {
            float px, py, pz;
            float u, v, pad;
        } object_vertex_t;

        float rx = -radius * nz;
        float rz =  radius * nx;
        const object_vertex_t verts[6] = {
            {x+rx,y,z+rz, 0,0,0},
            {x-rx,y,z-rz, 1,0,0},
            {x-rx,y+height,z-rz, 1,1,0},
            {x+rx,y,z+rz, 0,0,0},
            {x-rx,y+height,z-rz, 1,1,0},
            {x+rx,y+height,z+rz, 0,1,0}
        };

        if ( g_frame_encoder == nil || g_billboard_pipeline == nil ||
             g_camera_uniform_buffer == nil ) return;

        id<MTLTexture> tex = [g_textures objectForKey:@(texture)];
        if ( tex == nil ) return;

        id<MTLBuffer> vb =
            [g_device newBufferWithBytes:verts length:sizeof(verts)
                                 options:MTLResourceStorageModeShared];
        if ( vb == nil ) return;

        [g_frame_encoder setRenderPipelineState:g_billboard_pipeline];
        [g_frame_encoder setDepthStencilState:g_depth_state];
        [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
        [g_frame_encoder setVertexBuffer:g_camera_uniform_buffer offset:0 atIndex:1];
        [g_frame_encoder setFragmentTexture:tex atIndex:0];
        [g_frame_encoder setFragmentSamplerState:g_repeat_sampler atIndex:0];
        [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle
                            vertexStart:0 vertexCount:6];
    }
}


void renderer_metal_draw_sphere( const double model[16],
                                 int divisions,
                                 float r, float g, float b, float a )
{
    @autoreleasepool {
        typedef struct { float px,py,pz,nx,ny,nz; } sv_t;
        typedef struct { float mvp[16], model[16], color[4]; } su_t;
        int stacks = divisions < 3 ? 3 : divisions;
        int slices = stacks * 2;
        int count = stacks * slices * 6;
        sv_t *verts;
        int k = 0, i, j;
        float mf[16], mvp[16];
        su_t u;

        if ( g_frame_encoder == nil || g_sphere_pipeline == nil ||
             g_camera_uniform_buffer == nil || model == NULL ) return;

        verts = (sv_t *)malloc( sizeof(sv_t) * count );
        if ( verts == NULL ) return;

        for ( i=0; i<stacks; ++i ) {
            float p0 = (float)(-M_PI_2 + M_PI * i / stacks);
            float p1 = (float)(-M_PI_2 + M_PI * (i+1) / stacks);
            for ( j=0; j<slices; ++j ) {
                float t0=(float)(2*M_PI*j/slices), t1=(float)(2*M_PI*(j+1)/slices);
                float x00=cosf(p0)*cosf(t0), y00=sinf(p0), z00=cosf(p0)*sinf(t0);
                float x10=cosf(p0)*cosf(t1), y10=sinf(p0), z10=cosf(p0)*sinf(t1);
                float x11=cosf(p1)*cosf(t1), y11=sinf(p1), z11=cosf(p1)*sinf(t1);
                float x01=cosf(p1)*cosf(t0), y01=sinf(p1), z01=cosf(p1)*sinf(t0);
                verts[k++]={x00,y00,z00,x00,y00,z00}; verts[k++]={x10,y10,z10,x10,y10,z10}; verts[k++]={x11,y11,z11,x11,y11,z11};
                verts[k++]={x00,y00,z00,x00,y00,z00}; verts[k++]={x11,y11,z11,x11,y11,z11}; verts[k++]={x01,y01,z01,x01,y01,z01};
            }
        }

        for(i=0;i<16;++i) mf[i]=(float)model[i];
        /*
         * Camera uniform begins with the already validated Metal
         * view-projection matrix.
         */
        const float *vp=(const float *)[g_camera_uniform_buffer contents];
        for(int col=0;col<4;++col) for(int row=0;row<4;++row) {
            float v=0;
            for(int q=0;q<4;++q) v += vp[q*4+row]*mf[col*4+q];
            mvp[col*4+row]=v;
        }
        memcpy(u.mvp,mvp,sizeof(mvp)); memcpy(u.model,mf,sizeof(mf));
        u.color[0]=r;u.color[1]=g;u.color[2]=b;u.color[3]=a;

        id<MTLBuffer> vb=[g_device newBufferWithBytes:verts length:sizeof(sv_t)*count options:MTLResourceStorageModeShared];
        id<MTLBuffer> ub=[g_device newBufferWithBytes:&u length:sizeof(u) options:MTLResourceStorageModeShared];
        free(verts);
        if(vb==nil||ub==nil)return;
        [g_frame_encoder setRenderPipelineState:g_sphere_pipeline];
        [g_frame_encoder setDepthStencilState:g_depth_state];
        [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
        [g_frame_encoder setVertexBuffer:ub offset:0 atIndex:1];
        [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:count];
    }
}


static float modern_metal_text( float x, float y,
                                const char *binding, const char *text,
                                float mul, float alpha )
{
    typedef struct { float x, y, u, v; } text_vertex_t;
    typedef struct { float color[4]; } text_uniform_t;

    font_render_info_t fi;
    id<MTLTexture> tex;
    float pen = x;
    int i;

    if ( !get_font_render_info( (char *)binding, &fi ) ||
         g_text_pipeline == nil ) {
        return 0.0f;
    }

    tex = [g_textures objectForKey:@(fi.texture)];
    if ( tex == nil ) return 0.0f;

    for ( i=0; text[i] != '\0'; ++i ) {
        tex_font_glyph_t g;
        float sc, x0, x1, y0, y1, sx, sy;
        float u0, v0, u1, v1;
        text_vertex_t vertices[6];
        text_uniform_t uniforms;
        id<MTLBuffer> vb, ub;

        if ( !get_tex_font_glyph( fi.metrics, text[i], &g ) ) continue;

        sc = (float)fi.scale * mul;
        x0 = pen + (float)g.x0 * sc;
        x1 = pen + (float)g.x1 * sc;
        y0 = y + (float)g.y0 * sc;
        y1 = y + (float)g.y1 * sc;

        /* tex_font_metrics uses scalar_t (double); Metal vertices are float. */
        u0 = (float)g.u0;
        v0 = (float)g.v0;
        u1 = (float)g.u1;
        v1 = (float)g.v1;

        sx = 2.0f / (float)g_native_width;
        sy = 2.0f / (float)g_native_height;

        vertices[0] = (text_vertex_t){ -1.0f+x0*sx, -1.0f+y0*sy, u0, v0 };
        vertices[1] = (text_vertex_t){ -1.0f+x1*sx, -1.0f+y0*sy, u1, v0 };
        vertices[2] = (text_vertex_t){ -1.0f+x1*sx, -1.0f+y1*sy, u1, v1 };
        vertices[3] = (text_vertex_t){ -1.0f+x0*sx, -1.0f+y0*sy, u0, v0 };
        vertices[4] = (text_vertex_t){ -1.0f+x1*sx, -1.0f+y1*sy, u1, v1 };
        vertices[5] = (text_vertex_t){ -1.0f+x0*sx, -1.0f+y1*sy, u0, v1 };

        uniforms.color[0] = (float)fi.colour.r;
        uniforms.color[1] = (float)fi.colour.g;
        uniforms.color[2] = (float)fi.colour.b;
        uniforms.color[3] = (float)fi.colour.a * alpha;

        vb = [g_device newBufferWithBytes:vertices
                                  length:sizeof(vertices)
                                 options:MTLResourceStorageModeShared];
        ub = [g_device newBufferWithBytes:&uniforms
                                  length:sizeof(uniforms)
                                 options:MTLResourceStorageModeShared];

        if ( vb != nil && ub != nil ) {
            [g_frame_encoder setRenderPipelineState:g_text_pipeline];
            [g_frame_encoder setDepthStencilState:g_no_depth_state];
            [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
            [g_frame_encoder setFragmentBuffer:ub offset:0 atIndex:0];
            [g_frame_encoder setFragmentTexture:tex atIndex:0];
            [g_frame_encoder setFragmentSamplerState:g_clamp_sampler atIndex:0];
            [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle
                                vertexStart:0
                                vertexCount:6];
        }

        pen += (float)g.advance * sc;
    }

    return pen - x;
}

int renderer_metal_load_modern_ui_texture( const char *name, const char *filename )
{
    @autoreleasepool {
        tux_image_t *img;
        id<MTLTexture> tex;
        MTLTextureDescriptor *td;
        if(!name||!filename||g_device==nil||g_ui_textures==nil||g_ui_image_pipeline==nil){
            fprintf(stderr,"Tux Racer Modern: Modern UI texture load attempted before UI renderer initialization\n");
            return 0;
        }
        img=tux_image_load(filename);if(!img||img->channels!=4){tux_image_free(img);return 0;}
        td=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
              width:(NSUInteger)img->width height:(NSUInteger)img->height mipmapped:NO];
        tex=[g_device newTextureWithDescriptor:td];if(!tex){tux_image_free(img);return 0;}
        [tex replaceRegion:MTLRegionMake2D(0,0,img->width,img->height) mipmapLevel:0
               withBytes:img->pixels bytesPerRow:(NSUInteger)img->width*4u];
        [g_ui_textures setObject:tex forKey:[NSString stringWithUTF8String:name]];
        fprintf(stderr,"Tux Racer Modern: loaded Modern UI texture %s (%dx%d)\n",name,img->width,img->height);
        tux_image_free(img);return 1;
    }
}

static void modern_draw_ui_image( const char *name )
{
    typedef struct{float x,y,u,v;} V;
    V v[6]={{-1,-1,0,1},{1,-1,1,1},{1,1,1,0},{-1,-1,0,1},{1,1,1,0},{-1,1,0,0}};
    id<MTLTexture> tex;id<MTLBuffer> vb;
    if(!name||g_frame_encoder==nil||g_ui_image_pipeline==nil)return;
    tex=[g_ui_textures objectForKey:[NSString stringWithUTF8String:name]];if(!tex)return;
    vb=[g_device newBufferWithBytes:v length:sizeof(v) options:MTLResourceStorageModeShared];if(!vb)return;
    [g_frame_encoder setRenderPipelineState:g_ui_image_pipeline];
    [g_frame_encoder setDepthStencilState:g_no_depth_state];
    [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
    [g_frame_encoder setFragmentTexture:tex atIndex:0];
    [g_frame_encoder setFragmentSamplerState:g_clamp_sampler atIndex:0];
    [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
}

int renderer_metal_begin_menu_frame( int width, int height )
{
    @autoreleasepool {
        void *opaque;
        if(width<=0||height<=0||g_command_queue==nil||g_overlay_pipeline==nil)return 0;
        renderer_metal_set_native_visible(1);
        opaque=metal_present_next_drawable(); if(!opaque)return 0;
        g_native_drawable=(__bridge_transfer id<CAMetalDrawable>)opaque;
        g_native_width=width;g_native_height=height;
        g_frame_command_buffer=[g_command_queue commandBuffer];if(!g_frame_command_buffer)return 0;
        g_frame_pass=[MTLRenderPassDescriptor renderPassDescriptor];
        g_frame_pass.colorAttachments[0].texture=g_native_drawable.texture;
        g_frame_pass.colorAttachments[0].loadAction=MTLLoadActionClear;
        g_frame_pass.colorAttachments[0].storeAction=MTLStoreActionStore;
        g_frame_pass.colorAttachments[0].clearColor=MTLClearColorMake(.025,.07,.13,1);
        g_frame_encoder=[g_frame_command_buffer renderCommandEncoderWithDescriptor:g_frame_pass];
        if(!g_frame_encoder)return 0;g_native_frame_active=1;return 1;
    }
}
static void menu_box(float x,float y,float w,float h,float r,float g,float b,float a){
    typedef struct{float x,y;}V;typedef struct{float color[4];}U;float sx=2.0f/g_native_width,sy=2.0f/g_native_height;
    float x0=-1+x*sx,x1=-1+(x+w)*sx,y0=-1+y*sy,y1=-1+(y+h)*sy;V v[6]={{x0,y0},{x1,y0},{x1,y1},{x0,y0},{x1,y1},{x0,y1}};U u={{r,g,b,a}};
    id<MTLBuffer>vb=[g_device newBufferWithBytes:v length:sizeof(v) options:MTLResourceStorageModeShared],ub=[g_device newBufferWithBytes:&u length:sizeof(u) options:MTLResourceStorageModeShared];
    [g_frame_encoder setRenderPipelineState:g_overlay_pipeline];[g_frame_encoder setDepthStencilState:g_no_depth_state];[g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];[g_frame_encoder setFragmentBuffer:ub offset:0 atIndex:0];[g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
}
static void modern_menu_backdrop(void);

void renderer_metal_draw_home_menu( int selected )
{
    @autoreleasepool {
        static const char *items[]={"RACE","PRACTICE","CREDITS","QUIT"};
        float ui=(float)g_native_height/2168.0f,cx,y,title_x;
        int i;
        if(ui<.62f)ui=.62f;if(ui>1.45f)ui=1.45f;

        modern_draw_ui_image("home");

        cx=(float)g_native_width*.5f;
        title_x=cx-205.0f*ui;
        y=(float)g_native_height-260.0f*ui;
        modern_metal_text(title_x,y,"modern_hud_small","TUX RACER",1.00f*ui,.72f);
        y-=66.0f*ui;
        modern_metal_text(title_x-20.0f*ui,y,"modern_hud_speed","MODERN",1.18f*ui,1.0f);

        y-=190.0f*ui;
        for(i=0;i<4;i++){
            float alpha=(i==selected)?1.0f:.62f;
            float item_x=cx-145.0f*ui+(i==selected?10.0f*ui:0.0f);
            if(i==selected){
                menu_box(cx-190.0f*ui,y-18.0f*ui,380.0f*ui,66.0f*ui,
                         .015f,.045f,.075f,.42f);
                menu_box(cx-190.0f*ui,y-18.0f*ui,3.0f*ui,66.0f*ui,
                         .78f,.92f,1.0f,.95f);
            }
            modern_metal_text(item_x,y,"modern_hud_speed",items[i],.88f*ui,alpha);
            y-=90.0f*ui;
        }
    }
}

static void modern_menu_backdrop(void)
{
    menu_box(0,0,g_native_width,g_native_height,.075f,.20f,.34f,1.0f);
    renderer_metal_draw_background_mountain_layer(g_menu_mountain_far_handle,-.18f,.72f,.98f,-.015f,1.015f);
    renderer_metal_draw_background_mountain_layer(g_menu_mountain_mid_handle,-.30f,.53f,.86f,.01f,.99f);
    renderer_metal_draw_background_mountain_layer(g_menu_mountain_foothill_handle,-.48f,.30f,.80f,.025f,.975f);
    /* Cinematic edge treatments, not layout panels. */
    menu_box(0,0,g_native_width,g_native_height*.12f,.005f,.012f,.020f,.20f);
    menu_box(0,g_native_height*.88f,g_native_width,g_native_height*.12f,.005f,.012f,.020f,.12f);
}

void renderer_metal_draw_course_menu( const char *course_name,
                                      const char *description,
                                      const char *progress,
                                      const char *requirements,
                                      int can_start )
{
    @autoreleasepool {
        float ui=(float)g_native_height/2168.0f,x,y;
        if(ui<.62f)ui=.62f;if(ui>1.45f)ui=1.45f;
        if(!course_name)course_name="COURSE"; if(!description)description="";
        if(!progress)progress=""; if(!requirements)requirements="";
        modern_menu_backdrop();

        /* Bottom cinematic information shelf; artwork remains the hero. */
        menu_box(0,0,g_native_width,g_native_height*.35f,.004f,.012f,.022f,.64f);
        x=100.0f*ui; y=g_native_height*.30f;
        modern_metal_text(x,y,"modern_hud_small","COURSE",.90f*ui,.66f);
        y-=62.0f*ui;
        modern_metal_text(x,y,"modern_hud_speed",course_name,1.08f*ui,1.0f);
        y-=72.0f*ui;
        modern_metal_text(x,y,"modern_hud_small",description,.78f*ui,.76f);

        x=g_native_width-610.0f*ui; y=g_native_height*.27f;
        modern_metal_text(x,y,"modern_hud_small",progress,.86f*ui,.72f);
        y-=68.0f*ui;
        modern_metal_text(x,y,"modern_hud_small",requirements,.76f*ui,.62f);
        y-=82.0f*ui;
        modern_metal_text(x,y,"modern_hud_speed",can_start?"START RACE":"LOCKED",.82f*ui,can_start?1.0f:.48f);

        modern_metal_text(100.0f*ui,g_native_height-92.0f*ui,
                          "modern_hud_small","TUX RACER MODERN",.76f*ui,.58f);
    }
}

void renderer_metal_draw_results_menu( const char *headline,
                                       const char *message,
                                       const char *time_text,
                                       int herring,
                                       int score )
{
    @autoreleasepool {
        char fish[32],points[32];
        float ui=(float)g_native_height/2168.0f,cx,x,y;
        if(ui<.62f)ui=.62f;if(ui>1.45f)ui=1.45f;
        if(!headline)headline="RACE COMPLETE"; if(!message)message=""; if(!time_text)time_text="";
        snprintf(fish,sizeof(fish),"%d",herring); snprintf(points,sizeof(points),"%d",score);
        menu_box(0,0,g_native_width,g_native_height,.10f,.30f,.52f,1.0f);
        renderer_metal_draw_background_mountain_layer(g_menu_mountain_far_handle,-.18f,.72f,.96f,-.015f,1.015f);
        renderer_metal_draw_background_mountain_layer(g_menu_mountain_mid_handle,-.30f,.53f,.82f,.01f,.99f);
        renderer_metal_draw_background_mountain_layer(g_menu_mountain_foothill_handle,-.48f,.30f,.76f,.025f,.975f);
        menu_box(g_native_width*.27f,g_native_height*.20f,g_native_width*.46f,g_native_height*.60f,
                 .006f,.018f,.034f,.48f);
        cx=g_native_width*.5f;x=cx-235.0f*ui;y=g_native_height-410.0f*ui;
        modern_metal_text(x,y,"modern_hud_small","TUX RACER MODERN",.92f*ui,.68f);
        y-=78.0f*ui; modern_metal_text(x,y,"modern_hud_speed",headline,1.02f*ui,1.0f);
        y-=92.0f*ui; modern_metal_text(x,y,"modern_hud_small",message,.88f*ui,.78f);
        y-=120.0f*ui; modern_metal_text(x,y,"modern_hud_small","TIME",.78f*ui,.58f);
        modern_metal_text(x+150*ui,y,"modern_hud_speed",time_text,.72f*ui,.96f);
        y-=72.0f*ui; modern_metal_text(x,y,"modern_hud_small","FISH",.78f*ui,.58f);
        modern_metal_text(x+150*ui,y,"modern_hud_speed",fish,.72f*ui,.96f);
        y-=72.0f*ui; modern_metal_text(x,y,"modern_hud_small","SCORE",.78f*ui,.58f);
        modern_metal_text(x+150*ui,y,"modern_hud_speed",points,.72f*ui,.96f);
        y-=125.0f*ui; modern_metal_text(x,y,"modern_hud_small","PRESS ANY KEY TO CONTINUE",.78f*ui,.66f);
    }
}

void renderer_metal_draw_event_menu( const char *event_name,
                                     const char *cup_name,
                                     const char *status,
                                     int focus_row )
{
    @autoreleasepool {
        float ui=(float)g_native_height/2168.0f;
        float x,y,card_x,card_w;
        if(ui<.62f)ui=.62f;if(ui>1.45f)ui=1.45f;
        if(event_name==NULL)event_name="EVENT";
        if(cup_name==NULL)cup_name="CUP";
        if(status==NULL)status="";

        menu_box(0,0,g_native_width,g_native_height,.10f,.30f,.52f,1.0f);
        renderer_metal_draw_background_mountain_layer(
            g_menu_mountain_far_handle,-.18f,.72f,.96f,-.015f,1.015f);
        renderer_metal_draw_background_mountain_layer(
            g_menu_mountain_mid_handle,-.30f,.53f,.82f,.01f,.99f);
        renderer_metal_draw_background_mountain_layer(
            g_menu_mountain_foothill_handle,-.48f,.30f,.76f,.025f,.975f);
        menu_box(0,0,g_native_width,g_native_height*.22f,.78f,.88f,.96f,.10f);
        menu_box(0,0,g_native_width*.28f,g_native_height,.006f,.018f,.034f,.48f);
        menu_box(g_native_width*.28f,0,g_native_width*.14f,g_native_height,.006f,.018f,.034f,.24f);

        x=112.0f*ui;y=(float)g_native_height-205.0f*ui;
        modern_metal_text(x,y,"modern_hud_small","TUX RACER",1.00f*ui,.72f);
        y-=64.0f*ui;
        modern_metal_text(x,y,"modern_hud_speed","EVENT",1.10f*ui,1.0f);
        y-=58.0f*ui;
        modern_metal_text(x,y,"modern_hud_small","CHOOSE YOUR CHALLENGE",.86f*ui,.64f);

        card_x=x; card_w=650.0f*ui; y-=150.0f*ui;
        if(focus_row==0)menu_box(card_x-22*ui,y-22*ui,card_w,92*ui,.04f,.12f,.20f,.56f);
        modern_metal_text(x,y+38*ui,"modern_hud_small","EVENT",.82f*ui,.62f);
        modern_metal_text(x,y,"modern_hud_speed",event_name,.78f*ui,focus_row==0?1.0f:.78f);
        if(focus_row==0)menu_box(x-20*ui,y-8*ui,3*ui,35*ui,.78f,.92f,1.0f,.92f);

        y-=132.0f*ui;
        if(focus_row==1)menu_box(card_x-22*ui,y-22*ui,card_w,92*ui,.04f,.12f,.20f,.56f);
        modern_metal_text(x,y+38*ui,"modern_hud_small","CUP",.82f*ui,.62f);
        modern_metal_text(x,y,"modern_hud_speed",cup_name,.78f*ui,focus_row==1?1.0f:.78f);
        if(focus_row==1)menu_box(x-20*ui,y-8*ui,3*ui,35*ui,.78f,.92f,1.0f,.92f);

        y-=130.0f*ui;
        modern_metal_text(x,y,"modern_hud_small",status,.78f*ui,.76f);
        y-=120.0f*ui;
        modern_metal_text(x,y,"modern_hud_speed","START",.72f*ui,.96f);
        modern_metal_text(x+190*ui,y,"modern_hud_small","BACK",.90f*ui,.58f);
    }
}

void renderer_metal_end_menu_frame( void ){renderer_metal_end_native_frame();}

void renderer_metal_draw_hud(float speed_kmh,float race_time,float energy,int herring){@autoreleasepool{int min=(int)(race_time/60),sec=((int)race_time)%60,hh=(int)((race_time-(int)race_time)*100),mph=(int)(speed_kmh*.621371f+.5f);char t[32],sp[32],he[32];float ui=(float)g_native_height/2168.0f,x,y;(void)energy;if(!g_frame_encoder||g_native_width<=0||g_native_height<=0)return;if(ui<.62f)ui=.62f;if(ui>1.45f)ui=1.45f;snprintf(t,sizeof(t),"%d:%02d.%02d",min,sec,hh);snprintf(sp,sizeof(sp),"%d MPH",mph);snprintf(he,sizeof(he),"%d",herring);x=58*ui;y=g_native_height-74*ui;modern_metal_text(x,y,"modern_hud_small","TIME",1.35f*ui,.85f);y-=55*ui;modern_metal_text(x,y,"modern_hud_speed",t,1.10f*ui,1);y-=78*ui;modern_metal_text(x,y,"modern_hud_small","SPEED",1.35f*ui,.85f);y-=55*ui;modern_metal_text(x,y,"modern_hud_speed",sp,1.10f*ui,1);y-=78*ui;modern_metal_text(x,y,"modern_hud_small","HERRING",1.35f*ui,.85f);y-=55*ui;modern_metal_text(x,y,"modern_hud_speed",he,1.10f*ui,1);}}


void renderer_metal_draw_colored_box( float cx,float cy,float cz,
                                     float sx,float sy,float sz,
                                     float r,float g,float b,float a )
{
    @autoreleasepool {
        typedef struct { float px,py,pz,nx,ny,nz; } sv_t;
        typedef struct { float mvp[16], model[16], color[4]; } su_t;
        const float x0=cx-sx*0.5f,x1=cx+sx*0.5f;
        const float y0=cy-sy*0.5f,y1=cy+sy*0.5f;
        const float z0=cz-sz*0.5f,z1=cz+sz*0.5f;
        const sv_t v[36]={
          {x0,y0,z1,0,0,1},{x1,y0,z1,0,0,1},{x1,y1,z1,0,0,1},{x0,y0,z1,0,0,1},{x1,y1,z1,0,0,1},{x0,y1,z1,0,0,1},
          {x1,y0,z0,0,0,-1},{x0,y0,z0,0,0,-1},{x0,y1,z0,0,0,-1},{x1,y0,z0,0,0,-1},{x0,y1,z0,0,0,-1},{x1,y1,z0,0,0,-1},
          {x0,y0,z0,-1,0,0},{x0,y0,z1,-1,0,0},{x0,y1,z1,-1,0,0},{x0,y0,z0,-1,0,0},{x0,y1,z1,-1,0,0},{x0,y1,z0,-1,0,0},
          {x1,y0,z1,1,0,0},{x1,y0,z0,1,0,0},{x1,y1,z0,1,0,0},{x1,y0,z1,1,0,0},{x1,y1,z0,1,0,0},{x1,y1,z1,1,0,0},
          {x0,y1,z1,0,1,0},{x1,y1,z1,0,1,0},{x1,y1,z0,0,1,0},{x0,y1,z1,0,1,0},{x1,y1,z0,0,1,0},{x0,y1,z0,0,1,0},
          {x0,y0,z0,0,-1,0},{x1,y0,z0,0,-1,0},{x1,y0,z1,0,-1,0},{x0,y0,z0,0,-1,0},{x1,y0,z1,0,-1,0},{x0,y0,z1,0,-1,0}
        };
        su_t u; float ident[16]={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};
        const float *vp;
        if(g_frame_encoder==nil||g_sphere_pipeline==nil||g_camera_uniform_buffer==nil)return;
        vp=(const float *)[g_camera_uniform_buffer contents];
        memcpy(u.mvp,vp,sizeof(u.mvp)); memcpy(u.model,ident,sizeof(u.model));
        u.color[0]=r;u.color[1]=g;u.color[2]=b;u.color[3]=a;
        id<MTLBuffer> vb=[g_device newBufferWithBytes:v length:sizeof(v) options:MTLResourceStorageModeShared];
        id<MTLBuffer> ub=[g_device newBufferWithBytes:&u length:sizeof(u) options:MTLResourceStorageModeShared];
        if(vb==nil||ub==nil)return;
        [g_frame_encoder setRenderPipelineState:g_sphere_pipeline];
        [g_frame_encoder setDepthStencilState:g_depth_state];
        [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
        [g_frame_encoder setVertexBuffer:ub offset:0 atIndex:1];
        [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:36];
    }
}

void renderer_metal_draw_ground_strip( float cx,float cz,float width,float depth,
                                      float r,float g,float b,float a )
{
    @autoreleasepool {
        typedef struct { float px,py,pz,nx,ny,nz; } sv_t;
        typedef struct { float mvp[16], model[16], color[4]; } su_t;
        const int seg=24; sv_t v[24*6]; int i,k=0;
        su_t u; float ident[16]={1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1};
        const float *vp;
        if(g_frame_encoder==nil||g_sphere_pipeline==nil||g_camera_uniform_buffer==nil)return;
        for(i=0;i<seg;i++){
            float x0=cx-width*0.5f+width*i/seg, x1=cx-width*0.5f+width*(i+1)/seg;
            float z0=cz-depth*0.5f, z1=cz+depth*0.5f;
            float y00=(float)get_renderer_course_height(x0,z0)+0.018f;
            float y10=(float)get_renderer_course_height(x1,z0)+0.018f;
            float y11=(float)get_renderer_course_height(x1,z1)+0.018f;
            float y01=(float)get_renderer_course_height(x0,z1)+0.018f;
            v[k++]={x0,y00,z0,0,1,0};v[k++]={x1,y10,z0,0,1,0};v[k++]={x1,y11,z1,0,1,0};
            v[k++]={x0,y00,z0,0,1,0};v[k++]={x1,y11,z1,0,1,0};v[k++]={x0,y01,z1,0,1,0};
        }
        vp=(const float *)[g_camera_uniform_buffer contents];
        memcpy(u.mvp,vp,sizeof(u.mvp));memcpy(u.model,ident,sizeof(u.model));
        u.color[0]=r;u.color[1]=g;u.color[2]=b;u.color[3]=a;
        id<MTLBuffer> vb=[g_device newBufferWithBytes:v length:sizeof(v) options:MTLResourceStorageModeShared];
        id<MTLBuffer> ub=[g_device newBufferWithBytes:&u length:sizeof(u) options:MTLResourceStorageModeShared];
        if(vb==nil||ub==nil)return;
        [g_frame_encoder setRenderPipelineState:g_sphere_pipeline];
        [g_frame_encoder setDepthStencilState:g_depth_state];
        [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
        [g_frame_encoder setVertexBuffer:ub offset:0 atIndex:1];
        [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:seg*6];
    }
}

void renderer_metal_draw_shadow_ellipse( float x, float y, float z,
                                         float radius_x, float radius_z,
                                         float alpha )
{
    @autoreleasepool {
        typedef struct { float px,py,pz,a; } shv_t;
        const int segments=32;
        shv_t verts[32 * 3];
        int i, k=0;
        if(g_frame_encoder==nil||g_shadow_pipeline==nil||g_camera_uniform_buffer==nil)return;
        for(i=0;i<segments;++i){
            float a0=(float)(2.0*M_PI*i/segments);
            float a1=(float)(2.0*M_PI*(i+1)/segments);
            verts[k++]=(shv_t){x,y,z,alpha};
            verts[k++]=(shv_t){x+cosf(a0)*radius_x,y,z+sinf(a0)*radius_z,0.0f};
            verts[k++]=(shv_t){x+cosf(a1)*radius_x,y,z+sinf(a1)*radius_z,0.0f};
        }
        id<MTLBuffer> vb=[g_device newBufferWithBytes:verts length:sizeof(verts) options:MTLResourceStorageModeShared];
        if(vb==nil)return;
        [g_frame_encoder setRenderPipelineState:g_shadow_pipeline];
        [g_frame_encoder setDepthStencilState:g_depth_state];
        [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
        [g_frame_encoder setVertexBuffer:g_camera_uniform_buffer offset:0 atIndex:1];
        [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:(32 * 3)];
    }
}


void renderer_metal_draw_skybox( const tux_texture_handle_t faces[6] )
{
    @autoreleasepool {
        typedef struct { float x,y,z,u,v,pad; } sv_t;
        typedef struct { float vp[16]; } su_t;
        static const float face_pos[6][4][3] = {
            {{-1,-1,-1},{ 1,-1,-1},{ 1, 1,-1},{-1, 1,-1}},
            {{-1, 1,-1},{ 1, 1,-1},{ 1, 1, 1},{-1, 1, 1}},
            {{-1,-1, 1},{ 1,-1, 1},{ 1,-1,-1},{-1,-1,-1}},
            {{-1,-1, 1},{-1,-1,-1},{-1, 1,-1},{-1, 1, 1}},
            {{ 1,-1,-1},{ 1,-1, 1},{ 1, 1, 1},{ 1, 1,-1}},
            {{ 1,-1, 1},{-1,-1, 1},{-1, 1, 1},{ 1, 1, 1}}
        };
        static const int tri[6]={0,1,2,0,2,3};
        su_t u;
        int f,i,k;
        if(g_frame_encoder==nil||g_skybox_pipeline==nil||g_camera_uniform_buffer==nil||faces==NULL)return;
        memcpy(u.vp,[g_camera_uniform_buffer contents],sizeof(u.vp));
        /* Remove camera translation: skybox follows eye position infinitely. */
        u.vp[12]=u.vp[13]=u.vp[14]=0.0f;

        [g_frame_encoder setRenderPipelineState:g_skybox_pipeline];
        [g_frame_encoder setDepthStencilState:g_depth_state];
        for(f=0;f<6;++f){
            id<MTLTexture> tex=[g_textures objectForKey:@(faces[f])];
            sv_t verts[6];
            if(tex==nil)continue;
            for(i=0;i<6;++i){
                k=tri[i];
                verts[i]=(sv_t){face_pos[f][k][0],face_pos[f][k][1],face_pos[f][k][2],
                                (k==1||k==2)?1.0f:0.0f,(k>=2)?1.0f:0.0f,0.0f};
            }
            id<MTLBuffer> vb=[g_device newBufferWithBytes:verts length:sizeof(verts) options:MTLResourceStorageModeShared];
            id<MTLBuffer> ub=[g_device newBufferWithBytes:&u length:sizeof(u) options:MTLResourceStorageModeShared];
            if(vb==nil||ub==nil)continue;
            [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
            [g_frame_encoder setVertexBuffer:ub offset:0 atIndex:1];
            [g_frame_encoder setFragmentTexture:tex atIndex:0];
            [g_frame_encoder setFragmentSamplerState:g_repeat_sampler atIndex:0];
            [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
        }
    }
}


void renderer_metal_draw_textured_quad( const float positions[12],
                                       const float uvs[8],
                                       float alpha,
                                       tux_texture_handle_t texture )
{
    @autoreleasepool {
        typedef struct { float px,py,pz,u,v,pad; } qv_t;
        static const int idx[6]={0,1,2,0,2,3};
        qv_t v[6]; int i,k;
        if(g_frame_encoder==nil||g_billboard_pipeline==nil||g_camera_uniform_buffer==nil||
           positions==NULL||uvs==NULL)return;
        id<MTLTexture> tex=[g_textures objectForKey:@(texture)];
        if(tex==nil)return;
        for(i=0;i<6;++i){k=idx[i];v[i]=(qv_t){positions[k*3],positions[k*3+1],positions[k*3+2],
                                               uvs[k*2],uvs[k*2+1],alpha};}
        id<MTLBuffer> vb=[g_device newBufferWithBytes:v length:sizeof(v) options:MTLResourceStorageModeShared];
        if(vb==nil)return;
        [g_frame_encoder setRenderPipelineState:g_billboard_pipeline];
        [g_frame_encoder setDepthStencilState:g_depth_state];
        [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
        [g_frame_encoder setVertexBuffer:g_camera_uniform_buffer offset:0 atIndex:1];
        [g_frame_encoder setFragmentTexture:tex atIndex:0];
        [g_frame_encoder setFragmentSamplerState:g_repeat_sampler atIndex:0];
        [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    }
}


void renderer_metal_draw_billboard_uv( float x,float y,float z,
                                       float radius,float height,
                                       float nx,float nz,
                                       float u0,float v0,float u1,float v1,
                                       float alpha,
                                       tux_texture_handle_t texture )
{
    @autoreleasepool {
        typedef struct { float px,py,pz,u,v,pad; } ov_t;
        float rx=-radius*nz, rz=radius*nx;
        ov_t v[6]={
            {x+rx,y,z+rz,u0,v0,alpha},{x-rx,y,z-rz,u1,v0,alpha},{x-rx,y+height,z-rz,u1,v1,alpha},
            {x+rx,y,z+rz,u0,v0,alpha},{x-rx,y+height,z-rz,u1,v1,alpha},{x+rx,y+height,z+rz,u0,v1,alpha}
        };
        if(g_frame_encoder==nil||g_billboard_pipeline==nil||g_camera_uniform_buffer==nil)return;
        id<MTLTexture> tex=[g_textures objectForKey:@(texture)];
        if(tex==nil)return;
        id<MTLBuffer> vb=[g_device newBufferWithBytes:v length:sizeof(v) options:MTLResourceStorageModeShared];
        if(vb==nil)return;
        [g_frame_encoder setRenderPipelineState:g_billboard_pipeline];
        [g_frame_encoder setDepthStencilState:g_depth_state];
        [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
        [g_frame_encoder setVertexBuffer:g_camera_uniform_buffer offset:0 atIndex:1];
        [g_frame_encoder setFragmentTexture:tex atIndex:0];
        [g_frame_encoder setFragmentSamplerState:g_repeat_sampler atIndex:0];
        [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    }
}


void renderer_metal_draw_mountain_card( float center_x, float base_y, float center_z,
                                        float width, float height,
                                        float alpha,
                                        tux_texture_handle_t texture )
{
    @autoreleasepool {
        typedef struct { float px,py,pz,u,v,pad; } ov_t;
        ov_t v[6];
        float hw=width*0.5f;
        if(g_frame_encoder==nil||g_mountain_card_pipeline==nil||
           g_camera_uniform_buffer==nil||texture==TUX_INVALID_TEXTURE_HANDLE)return;
        id<MTLTexture> tex=[g_textures objectForKey:@(texture)];
        if(tex==nil)return;

        /*
         * Backdrop cards span world X and stand vertically in Y at a fixed
         * distant Z. They are not camera-facing billboards: the world owns
         * their orientation, which keeps the horizon visually stable.
         */
        v[0]=(ov_t){center_x-hw,base_y,center_z,0,0,alpha};
        v[1]=(ov_t){center_x+hw,base_y,center_z,1,0,alpha};
        v[2]=(ov_t){center_x+hw,base_y+height,center_z,1,1,alpha};
        v[3]=(ov_t){center_x-hw,base_y,center_z,0,0,alpha};
        v[4]=(ov_t){center_x+hw,base_y+height,center_z,1,1,alpha};
        v[5]=(ov_t){center_x-hw,base_y+height,center_z,0,1,alpha};

        id<MTLBuffer> vb=[g_device newBufferWithBytes:v length:sizeof(v)
                                              options:MTLResourceStorageModeShared];
        if(vb==nil)return;
        [g_frame_encoder setRenderPipelineState:g_mountain_card_pipeline];
        [g_frame_encoder setDepthStencilState:g_depth_readonly_state];
        [g_frame_encoder setVertexBuffer:vb offset:0 atIndex:0];
        [g_frame_encoder setVertexBuffer:g_camera_uniform_buffer offset:0 atIndex:1];
        [g_frame_encoder setFragmentTexture:tex atIndex:0];
        [g_frame_encoder setFragmentSamplerState:g_repeat_sampler atIndex:0];
        [g_frame_encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6];
    }
}



