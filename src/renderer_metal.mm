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
#include "renderer_metal.h"
#include "metal_present.h"

static id<MTLDevice> g_device = nil;
static id<MTLCommandQueue> g_command_queue = nil;
static id<MTLBuffer> g_course_vertex_buffer = nil;
static id<MTLBuffer> g_last_index_buffer = nil;
static id<MTLLibrary> g_terrain_library = nil;
static id<MTLRenderPipelineState> g_terrain_pipeline = nil;
static id<MTLRenderPipelineState> g_sky_pipeline = nil;
static id<MTLRenderPipelineState> g_billboard_pipeline = nil;
static id<MTLDepthStencilState> g_depth_state = nil;
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

static int g_capture_written = 0;
static NSMutableDictionary<NSNumber *, id<MTLTexture>> *g_textures = nil;
static id<MTLSamplerState> g_repeat_sampler = nil;
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
                "fragment float4 sky_fragment(SkyOut in [[stage_in]]) { "
                "float y=saturate(in.uv.y); "
                "float3 horizon=float3(0.70,0.80,0.91); float3 zenith=float3(0.20,0.38,0.62); "
                "float3 c=mix(horizon,zenith,smoothstep(0.0,0.92,y)); "
                "float sun=exp(-distance(in.uv,float2(0.72,0.72))*18.0); "
                "c+=float3(1.0,0.82,0.58)*sun*0.16; return float4(c,1.0); }\n"
                "struct ObjectVertex { packed_float3 position; float2 uv; };\n"
                "struct ObjectOut { float4 position [[position]]; float2 uv; };\n"
                "vertex ObjectOut object_vertex(uint vid [[vertex_id]], const device ObjectVertex *v [[buffer(0)]], constant TerrainUniforms &u [[buffer(1)]]) { "
                "ObjectOut o; o.position=u.viewProjection*float4(float3(v[vid].position),1.0); o.uv=v[vid].uv; return o; }\n"
                "fragment float4 object_fragment(ObjectOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler samp [[sampler(0)]]) { "
                "float4 c=tex.sample(samp,in.uv); if(c.a<0.18) discard_fragment(); return c; }\n"
                "vertex TerrainVarying terrain_vertex(uint vid [[vertex_id]], const device TerrainVertex *v [[buffer(0)]], constant TerrainUniforms &u [[buffer(1)]]) { "
                "TerrainVarying o; o.position=u.viewProjection*float4(v[vid].position,1.0); o.worldPosition=v[vid].position; o.normal=v[vid].normal; o.texcoord=v[vid].texcoord; o.weights=max(v[vid].terrainWeights.xyz,float3(0.0)); return o; }\n"
                "fragment float4 terrain_fragment(TerrainVarying in [[stage_in]], constant TerrainUniforms &u [[buffer(1)]], texture2d<float> snow [[texture(0)]], texture2d<float> rock [[texture(1)]], texture2d<float> ice [[texture(2)]], sampler samp [[sampler(0)]]) { "
                "float3 w=in.weights/max(in.weights.x+in.weights.y+in.weights.z,0.0001); "
                "float2 macroUV=in.texcoord; float2 detailUV=in.texcoord*5.75; "
                "float3 snowMacro=snow.sample(samp,macroUV).rgb; float3 snowDetail=snow.sample(samp,detailUV).rgb; "
                "float3 rockBase=rock.sample(samp,macroUV*0.85).rgb; float3 iceBase=ice.sample(samp,macroUV*1.15).rgb; "
                "float snowVariation=dot(snowDetail,float3(0.3333)); "
                "float3 snowMat=snowMacro*(0.86+0.18*snowVariation); "
                "float3 rockMat=rockBase*float3(0.78,0.75,0.72); "
                "float3 iceMat=iceBase*float3(0.82,0.93,1.08); "
                "float3 albedo=snowMat*w.x+rockMat*w.y+iceMat*w.z; "
                "float3 n=normalize(in.normal); float3 sunDir=normalize(float3(-0.28,-0.90,-0.32)); "
                "float ndl=saturate(dot(n,-sunDir)); float hemi=0.60+0.40*saturate(n.y); "
                "float3 ambient=float3(0.48,0.56,0.70)*hemi; float3 sun=float3(0.82,0.78,0.70)*ndl; "
                "float snowSpark=pow(saturate(ndl),24.0)*w.x*0.10; "
                "float iceGlint=pow(saturate(ndl),48.0)*w.z*0.24; "
                "float3 lit=albedo*(ambient+sun)+float3(snowSpark)+float3(0.72,0.86,1.0)*iceGlint; "
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

            MTLDepthStencilDescriptor *depthDesc = [[MTLDepthStencilDescriptor alloc] init];
            depthDesc.depthCompareFunction = MTLCompareFunctionLessEqual;
            depthDesc.depthWriteEnabled = YES;
            g_depth_state = [g_device newDepthStencilStateWithDescriptor:depthDesc];
            if ( g_depth_state == nil ) {
                fprintf( stderr, "Tux Racer Modern: Metal depth state creation failed\n" );
                return 0;
            }

            fprintf( stderr, "Tux Racer Modern: Metal terrain pipeline ready\n" );
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
        g_terrain_pipeline = nil;
        g_sky_pipeline = nil;
        g_billboard_pipeline = nil;
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
                     "Tux Racer Modern: refusing nested native Metal frame\n" );
            return 0;
        }

        if ( !renderer_metal_prepare_camera_uniforms( camera, 0 ) ) return 0;

        metal_present_resize( width, height );
        opaque = metal_present_next_drawable();
        if ( opaque == NULL ) return 0;
        g_native_drawable = (__bridge_transfer id<CAMetalDrawable>)opaque;

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
            return 0;
        }

        g_frame_encoder =
            [g_frame_command_buffer renderCommandEncoderWithDescriptor:g_frame_pass];
        if ( g_frame_encoder == nil ) {
            g_frame_command_buffer = nil;
            g_frame_pass = nil;
            g_native_drawable = nil;
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
            float u, v;
        } object_vertex_t;

        const object_vertex_t verts[12] = {
            {x-radius,y,z, 0,0}, {x+radius,y,z, 1,0}, {x+radius,y+height,z, 1,1},
            {x-radius,y,z, 0,0}, {x+radius,y+height,z, 1,1}, {x-radius,y+height,z, 0,1},
            {x,y,z-radius, 0,0}, {x,y,z+radius, 1,0}, {x,y+height,z+radius, 1,1},
            {x,y,z-radius, 0,0}, {x,y+height,z+radius, 1,1}, {x,y+height,z-radius, 0,1}
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
