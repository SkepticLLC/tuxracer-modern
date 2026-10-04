/*
 * Tux Racer Modern Metal backend foundation.
 *
 * OpenGL still presents pixels in this milestone. Metal owns real GPU
 * resources in parallel so terrain data can be validated before presentation
 * switches backends.
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <stdio.h>
#include "renderer_metal.h"

static id<MTLDevice> g_device = nil;
static id<MTLCommandQueue> g_command_queue = nil;
static id<MTLBuffer> g_course_vertex_buffer = nil;
static id<MTLBuffer> g_last_index_buffer = nil;
static id<MTLLibrary> g_terrain_library = nil;
static id<MTLRenderPipelineState> g_terrain_pipeline = nil;
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
static int g_capture_written = 0;
static NSMutableDictionary<NSNumber *, id<MTLTexture>> *g_textures = nil;
static id<MTLSamplerState> g_repeat_sampler = nil;

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
                "struct TerrainVertex { float3 position; float3 normal; float2 texcoord; float3 terrainWeights; };\n"
                "struct CameraUniforms { float4x4 viewProjection; };\n"
                "struct TerrainVarying { float4 position [[position]]; float3 normal; float2 texcoord; float3 terrainWeights; };\n"
                "vertex TerrainVarying terrain_vertex(uint vid [[vertex_id]], const device TerrainVertex *v [[buffer(0)]], constant CameraUniforms &u [[buffer(1)]]) { "
                "TerrainVarying o; o.position=u.viewProjection*float4(v[vid].position,1.0); o.normal=v[vid].normal; o.texcoord=v[vid].texcoord; o.terrainWeights=v[vid].terrainWeights; return o; }\n"
                "fragment float4 terrain_fragment(TerrainVarying in [[stage_in]], texture2d<float> snow [[texture(0)]], texture2d<float> rock [[texture(1)]], texture2d<float> ice [[texture(2)]], sampler samp [[sampler(0)]]) { "
                "float3 w=max(in.terrainWeights,float3(0.0)); float sum=max(w.x+w.y+w.z,0.0001); w/=sum; "
                "float4 s=snow.sample(samp,in.texcoord); float4 r=rock.sample(samp,in.texcoord); float4 i=ice.sample(samp,in.texcoord); "
                "float4 a=s*w.x+r*w.y+i*w.z; float l=0.45+0.55*saturate(dot(normalize(in.normal),normalize(float3(0.25,0.9,0.35)))); "
                "return float4(a.rgb*l,1.0); }\n";

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
                id<MTLTexture> snow = [g_textures objectForKey:@(1)];
                id<MTLTexture> rock = [g_textures objectForKey:@(2)];
                id<MTLTexture> ice  = [g_textures objectForKey:@(3)];
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
         * Convert the preserved OpenGL clip-space Z range [-w,+w] to Metal's
         * [0,+w] while retaining X/Y and the original camera transform.
         */
        float vp[16];
        int i;
        for ( i = 0; i < 16; ++i ) vp[i] = (float)camera->view_projection_matrix[i];
        for ( i = 0; i < 4; ++i ) {
            vp[i*4 + 2] = 0.5f * ((float)camera->view_projection_matrix[i*4 + 2] +
                                  (float)camera->view_projection_matrix[i*4 + 3]);
        }
        g_camera_uniform_buffer =
            [g_device newBufferWithBytes:vp length:sizeof(vp)
                                 options:MTLResourceStorageModeShared];

        g_frame_pass = [MTLRenderPassDescriptor renderPassDescriptor];
        g_frame_pass.colorAttachments[0].texture = g_offscreen_color;
        g_frame_pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        g_frame_pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        g_frame_pass.colorAttachments[0].clearColor = MTLClearColorMake(0.08, 0.10, 0.14, 1.0);
        g_frame_pass.depthAttachment.texture = g_offscreen_depth;
        g_frame_pass.depthAttachment.loadAction = MTLLoadActionClear;
        g_frame_pass.depthAttachment.storeAction = MTLStoreActionDontCare;
        g_frame_pass.depthAttachment.clearDepth = 1.0;

        g_frame_command_buffer = [g_command_queue commandBuffer];
        g_frame_encoder =
            [g_frame_command_buffer renderCommandEncoderWithDescriptor:g_frame_pass];
        g_draw_count = 0;
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
