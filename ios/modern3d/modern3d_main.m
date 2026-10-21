/*
 * Tux Racer Modern — clean-slate iOS Metal 3D vertical slice.
 * Uses SDL2 for UIKit UIScene & input only. Rendering is native Metal with
 * depth testing (unlike the previous SDL_RenderGeometry projection).
 *
 * This is original prototype code, NOT historical Tux Racer gameplay.
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <SDL.h>
#include <SDL_metal.h>
#include <simd/simd.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

typedef struct { vector_float3 position; vector_float3 normal; vector_float4 color; } Vertex;
typedef struct { matrix_float4x4 mvp; matrix_float4x4 model; } Uniforms;

typedef struct {
    float length, width, slope, startSpeed, maxSpeed;
} CourseConfig;

static const char *shaderSource =
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct V { packed_float3 p; packed_float3 n; float4 color; };\n"
"struct U { float4x4 mvp; float4x4 model; };\n"
"struct Out { float4 position [[position]]; float4 color; float3 normal; float haze; };\n"
"vertex Out vertex_main(uint id [[vertex_id]], const device V *v [[buffer(0)]],"
" constant U &u [[buffer(1)]]) {\n"
"Out o; float4 p=float4(float3(v[id].p),1);"
"o.position=u.mvp*p;"
"o.normal=normalize((u.model*float4(float3(v[id].n),0)).xyz);"
"o.color=v[id].color;"
"o.haze=clamp(o.position.w/310.0,0.0,1.0); return o; }\n"
"fragment float4 fragment_main(Out in [[stage_in]]) {\n"
"float diffuse=max(dot(normalize(in.normal),normalize(float3(-0.55,0.85,0.40))),0.0);"
"float3 lit=in.color.rgb*(0.65+0.35*diffuse);"
"float3 fog=float3(0.58,0.73,0.82);"
"return float4(mix(lit,fog,in.haze*0.65),in.color.a); }\n";

static matrix_float4x4 perspective(float fov,float aspect,float near,float far) {
    float y=1.0f/tanf(fov*.5f),x=y/aspect;
    matrix_float4x4 m={0};
    m.columns[0]=(vector_float4){x,0,0,0};
    m.columns[1]=(vector_float4){0,y,0,0};
    m.columns[2]=(vector_float4){0,0,far/(near-far),-1};
    m.columns[3]=(vector_float4){0,0,far*near/(near-far),0};
    return m;
}
static matrix_float4x4 view_matrix(vector_float3 eye,vector_float3 target) {
    vector_float3 f=simd_normalize(target-eye);
    vector_float3 right=simd_normalize(simd_cross(f,(vector_float3){0,1,0}));
    vector_float3 up=simd_cross(right,f);
    matrix_float4x4 m=matrix_identity_float4x4;
    m.columns[0]=(vector_float4){right.x,up.x,-f.x,0};
    m.columns[1]=(vector_float4){right.y,up.y,-f.y,0};
    m.columns[2]=(vector_float4){right.z,up.z,-f.z,0};
    m.columns[3]=(vector_float4){-simd_dot(right,eye),-simd_dot(up,eye),simd_dot(f,eye),1};
    return m;
}
static CourseConfig read_course(void) {
    CourseConfig c={600,62,18,11,30};
    NSString *path=[[NSBundle mainBundle] pathForResource:@"course" ofType:@"json" inDirectory:@"modern3d"];
    if(!path) {
        NSLog(@"Modern3D: course.json not found; using defaults");
        return c;
    }
    NSData *data=[NSData dataWithContentsOfFile:path];
    NSError *error=nil;
    NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if(![json isKindOfClass:[NSDictionary class]]) {
        NSLog(@"Modern3D: JSON rejected: %@",error);
        return c;
    }
    NSNumber *length=json[@"lengthMeters"],*width=json[@"widthMeters"];
    NSNumber *slope=json[@"slopeDegrees"],*speed=json[@"startingSpeedMps"],*max=json[@"maxSpeedMps"];
    if(length.floatValue>150 && length.floatValue<10000)c.length=length.floatValue;
    if(width.floatValue>20 && width.floatValue<300)c.width=width.floatValue;
    if(slope.floatValue>0 && slope.floatValue<45)c.slope=slope.floatValue;
    if(speed.floatValue>0 && speed.floatValue<60)c.startSpeed=speed.floatValue;
    if(max.floatValue>=c.startSpeed && max.floatValue<90)c.maxSpeed=max.floatValue;
    NSLog(@"Modern3D course: %@ — %.0fm, %.0fm wide",json[@"name"],c.length,c.width);
    return c;
}

static float ground(float x,float z,float slope){
    return -tanf(slope*0.01745329252f)*z
        +2.3f*sinf(x*.085f+z*.039f)*cosf(z*.024f)
        +.75f*sinf(x*.26f-z*.058f);
}
static void add_vertex(Vertex *v,unsigned *count,unsigned max,
                       vector_float3 pos,vector_float3 normal,vector_float4 color){
    if(*count>=max)return;
    v[(*count)++]=(Vertex){pos,normal,color};
}
static Vertex *make_course(CourseConfig c,unsigned *count) {
    const unsigned nx=72,nz=240,max=nx*nz*6;
    Vertex *v=(Vertex *)calloc(max,sizeof(Vertex));
    if(!v)return NULL;
    *count=0;
    for(unsigned iz=0;iz<nz;iz++){
        float z0=(float)iz/nz*c.length,z1=(float)(iz+1)/nz*c.length;
        for(unsigned ix=0;ix<nx;ix++){
            float x0=((float)ix/nx-.5f)*c.width;
            float x1=((float)(ix+1)/nx-.5f)*c.width;
            vector_float3 a={x0,ground(x0,z0,c.slope),z0};
            vector_float3 b={x1,ground(x1,z0,c.slope),z0};
            vector_float3 d={x0,ground(x0,z1,c.slope),z1};
            vector_float3 e={x1,ground(x1,z1,c.slope),z1};
            vector_float3 n=simd_normalize(simd_cross(d-a,b-a));
            float ice=sinf(x0*.20f+z0*.072f)*cosf(z0*.043f);
            vector_float4 snow={.87f,.95f,.99f,1};
            vector_float4 blue={.31f,.76f,.90f,1};
            vector_float4 rock={.48f,.58f,.62f,1};
            vector_float4 color=ice>.68f?blue:ice<-.78f?rock:snow;
            add_vertex(v,count,max,a,n,color);
            add_vertex(v,count,max,d,n,color);
            add_vertex(v,count,max,b,n,color);
            add_vertex(v,count,max,b,n,color);
            add_vertex(v,count,max,d,n,color);
            add_vertex(v,count,max,e,n,color);
        }
    }
    return v;
}

int main(int argc,char **argv){
    (void)argc;(void)argv;
    if(SDL_Init(SDL_INIT_VIDEO|SDL_INIT_GAMECONTROLLER|SDL_INIT_EVENTS)!=0){
        fprintf(stderr,"SDL init: %s\n",SDL_GetError());return 1;
    }
    SDL_Window *window=SDL_CreateWindow("Tux Racer Modern — 3D",
        SDL_WINDOWPOS_UNDEFINED,SDL_WINDOWPOS_UNDEFINED,1280,720,
        SDL_WINDOW_METAL|SDL_WINDOW_ALLOW_HIGHDPI|SDL_WINDOW_FULLSCREEN);
    if(!window){SDL_Log("SDL window: %s",SDL_GetError());SDL_Quit();return 2;}
    SDL_MetalView metalView=SDL_Metal_CreateView(window);
    if(!metalView){SDL_Log("Metal view: %s",SDL_GetError());SDL_DestroyWindow(window);SDL_Quit();return 3;}
    CAMetalLayer *layer=(__bridge CAMetalLayer *)SDL_Metal_GetLayer(metalView);
    id<MTLDevice> device=MTLCreateSystemDefaultDevice();
    if(!device){SDL_Log("Metal device unavailable");return 4;}
    layer.device=device;
    layer.pixelFormat=MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly=YES;
    id<MTLCommandQueue> queue=[device newCommandQueue];

    NSError *error=nil;
    NSString *source=[NSString stringWithUTF8String:shaderSource];
    id<MTLLibrary> library=[device newLibraryWithSource:source options:nil error:&error];
    if(!library){NSLog(@"Shader compilation: %@",error);return 5;}
    MTLRenderPipelineDescriptor *desc=[MTLRenderPipelineDescriptor new];
    desc.vertexFunction=[library newFunctionWithName:@"vertex_main"];
    desc.fragmentFunction=[library newFunctionWithName:@"fragment_main"];
    desc.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
    desc.depthAttachmentPixelFormat=MTLPixelFormatDepth32Float;
    id<MTLRenderPipelineState> pipeline=[device newRenderPipelineStateWithDescriptor:desc error:&error];
    if(!pipeline){NSLog(@"Pipeline: %@",error);return 6;}
    MTLDepthStencilDescriptor *depthDesc=[MTLDepthStencilDescriptor new];
    depthDesc.depthCompareFunction=MTLCompareFunctionLess;
    depthDesc.depthWriteEnabled=YES;
    id<MTLDepthStencilState> depthState=[device newDepthStencilStateWithDescriptor:depthDesc];

    CourseConfig course=read_course();
    unsigned vertexCount=0;
    Vertex *vertices=make_course(course,&vertexCount);
    if(!vertices){SDL_Log("Terrain allocation failed");return 7;}
    id<MTLBuffer> terrainBuffer=[device newBufferWithBytes:vertices
        length:sizeof(Vertex)*vertexCount options:MTLResourceStorageModeShared];
    free(vertices);
    if(!terrainBuffer){SDL_Log("Terrain GPU buffer failed");return 8;}

    int previousWidth=0,previousHeight=0;
    id<MTLTexture> depthTexture=nil;
    float distance=0,lateral=0,speed=course.startSpeed,steer=0;
    bool running=true,suspended=false,braking=false;
    Uint64 last=SDL_GetPerformanceCounter(),frequency=SDL_GetPerformanceFrequency();
    while(running){
        @autoreleasepool {
            SDL_Event ev;
            while(SDL_PollEvent(&ev)){
                if(ev.type==SDL_QUIT)running=false;
                if(ev.type==SDL_APP_WILLENTERBACKGROUND || ev.type==SDL_APP_DIDENTERBACKGROUND)suspended=true;
                if(ev.type==SDL_APP_WILLENTERFOREGROUND || ev.type==SDL_APP_DIDENTERFOREGROUND)suspended=false;
                if(ev.type==SDL_KEYDOWN && ev.key.keysym.sym==SDLK_r){distance=0;lateral=0;speed=course.startSpeed;}
            }
            if(!running)break;
            if(suspended){SDL_Delay(30);last=SDL_GetPerformanceCounter();continue;}
            Uint64 now=SDL_GetPerformanceCounter();
            float dt=fminf((float)((double)(now-last)/frequency),.033f);last=now;
            const Uint8 *keys=SDL_GetKeyboardState(NULL);
            steer=(keys[SDL_SCANCODE_A]||keys[SDL_SCANCODE_LEFT])?-1:
                  (keys[SDL_SCANCODE_D]||keys[SDL_SCANCODE_RIGHT])?1:0;
            braking=keys[SDL_SCANCODE_S]||keys[SDL_SCANCODE_DOWN];
            /* Multitouch regions are deliberately independent of UI graphics. */
            int touches=SDL_GetNumTouchDevices();
            for(int i=0;i<touches;i++){
                SDL_TouchID id=SDL_GetTouchDevice(i);
                for(int j=0;j<SDL_GetNumTouchFingers(id);j++){
                    SDL_Finger *finger=SDL_GetTouchFinger(id,j);
                    if(!finger)continue;
                    if(finger->x<.30f)steer=-1;
                    if(finger->x>.70f)steer=1;
                    if(finger->x>.36f&&finger->x<.64f&&finger->y>.8f)braking=true;
                }
            }
            speed=fminf(course.maxSpeed,fmaxf(4,speed+(braking?-22.0f:6.0f)*dt));
            lateral=fminf(course.width*.43f,fmaxf(-course.width*.43f,
               lateral+steer*dt*(5.0f+speed*.4f)));
            distance+=speed*dt;
            if(distance>=course.length){distance=0;speed=course.startSpeed;}
            int width=0,height=0;
            SDL_Metal_GetDrawableSize(window,&width,&height);
            if(width<1||height<1){SDL_Delay(15);continue;}
            layer.drawableSize=CGSizeMake(width,height);
            if(width!=previousWidth||height!=previousHeight||!depthTexture){
                MTLTextureDescriptor *d=[MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                    width:width height:height mipmapped:NO];
                d.storageMode=MTLStorageModePrivate;
                d.usage=MTLTextureUsageRenderTarget;
                depthTexture=[device newTextureWithDescriptor:d];
                previousWidth=width;previousHeight=height;
            }
            id<CAMetalDrawable> drawable=[layer nextDrawable];
            if(!drawable||!depthTexture){SDL_Delay(15);continue;}
            float y=ground(lateral,distance,course.slope);
            vector_float3 eye={lateral,y+5,distance-14};
            vector_float3 target={lateral,y-3,distance+29};
            matrix_float4x4 view=view_matrix(eye,target);
            matrix_float4x4 proj=perspective(65.0f*.01745329252f,(float)width/height,.12f,800.0f);
            Uniforms uniform={simd_mul(proj,view),matrix_identity_float4x4};

            MTLRenderPassDescriptor *pass=[MTLRenderPassDescriptor renderPassDescriptor];
            pass.colorAttachments[0].texture=drawable.texture;
            pass.colorAttachments[0].loadAction=MTLLoadActionClear;
            pass.colorAttachments[0].storeAction=MTLStoreActionStore;
            pass.colorAttachments[0].clearColor=MTLClearColorMake(.24,.49,.66,1);
            pass.depthAttachment.texture=depthTexture;
            pass.depthAttachment.loadAction=MTLLoadActionClear;
            pass.depthAttachment.storeAction=MTLStoreActionDontCare;
            pass.depthAttachment.clearDepth=1.0;

            id<MTLCommandBuffer> command=[queue commandBuffer];
            id<MTLRenderCommandEncoder> encoder=[command renderCommandEncoderWithDescriptor:pass];
            [encoder setRenderPipelineState:pipeline];
            [encoder setDepthStencilState:depthState];
            [encoder setFrontFacingWinding:MTLWindingCounterClockwise];
            [encoder setCullMode:MTLCullModeNone];
            [encoder setVertexBuffer:terrainBuffer offset:0 atIndex:0];
            [encoder setVertexBytes:&uniform length:sizeof(uniform) atIndex:1];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertexCount];
            [encoder endEncoding];
            [command presentDrawable:drawable];
            [command commit];
        }
    }
    SDL_Metal_DestroyView(metalView);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
