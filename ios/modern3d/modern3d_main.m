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
#import <UIKit/UIKit.h>
#include <SDL.h>
#include <SDL_metal.h>
#include <simd/simd.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include "race_system.h"

typedef struct { vector_float3 position; vector_float3 normal; vector_float4 color; } Vertex;
typedef struct { matrix_float4x4 mvp; matrix_float4x4 model; } Uniforms;

typedef struct {
    float length, width, slope, startSpeed, maxSpeed;
} CourseConfig;

static const char *shaderSource =
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"struct V { float3 p; float3 n; float4 color; };\n"
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

/* Procedural three-dimensional penguin for renderer validation only.
 * The final character will be a rigged, textured asset with animations.
 * Each part uses tessellated ellipsoids with its own material color.
 */
static void add_ellipsoid(Vertex *verts,unsigned *count,unsigned maximum,
                          vector_float3 center,vector_float3 radii,
                          vector_float4 pigment){
    const int segments=16,rings=12;
    for(int j=0;j<rings;j++){
        float p0=(float)j/rings*3.14159265f;
        float p1=(float)(j+1)/rings*3.14159265f;
        for(int i=0;i<segments;i++){
            float t0=(float)i/segments*6.2831853f;
            float t1=(float)(i+1)/segments*6.2831853f;
            float ps[6]={p0,p1,p0,p0,p1,p1};
            float ts[6]={t0,t0,t1,t1,t0,t1};
            for(int k=0;k<6;k++){
                vector_float3 normal={sinf(ps[k])*cosf(ts[k]),cosf(ps[k]),sinf(ps[k])*sinf(ts[k])};
                vector_float3 pos=center+normal*radii;
                add_vertex(verts,count,maximum,pos,normal,pigment);
            }
        }
    }
}
static Vertex *make_penguin(unsigned *count){
    const unsigned max=11000;
    Vertex *v=(Vertex *)calloc(max,sizeof(Vertex));
    if(!v)return NULL;
    *count=0;
    const vector_float4 black={.065f,.12f,.18f,1};
    const vector_float4 white={.93f,.96f,.93f,1};
    const vector_float4 orange={1.0f,.58f,.09f,1};
    add_ellipsoid(v,count,max,(vector_float3){0,1.10f,0},
                  (vector_float3){.51f,.86f,.39f},black);
    add_ellipsoid(v,count,max,(vector_float3){0,1.03f,-.285f},
                  (vector_float3){.37f,.67f,.16f},white);
    add_ellipsoid(v,count,max,(vector_float3){0,1.94f,0},
                  (vector_float3){.39f,.43f,.34f},black);
    add_ellipsoid(v,count,max,(vector_float3){0,1.83f,-.355f},
                  (vector_float3){.24f,.11f,.15f},orange);
    add_ellipsoid(v,count,max,(vector_float3){-.50f,1.05f,0},
                  (vector_float3){.18f,.49f,.20f},black);
    add_ellipsoid(v,count,max,(vector_float3){.50f,1.05f,0},
                  (vector_float3){.18f,.49f,.20f},black);
    add_ellipsoid(v,count,max,(vector_float3){-.25f,.19f,-.20f},
                  (vector_float3){.23f,.12f,.35f},orange);
    add_ellipsoid(v,count,max,(vector_float3){.25f,.19f,-.20f},
                  (vector_float3){.23f,.12f,.35f},orange);
    return v;
}
static void add_cone(Vertex *v,unsigned *count,unsigned max,
                     float base_y,float tip_y,float radius,vector_float4 tint){
    const int sides=12;
    for(int i=0;i<sides;i++){
        float a=(float)i/sides*6.2831853f,b=(float)(i+1)/sides*6.2831853f;
        vector_float3 tip={0,tip_y,0};
        vector_float3 left={cosf(a)*radius,base_y,sinf(a)*radius};
        vector_float3 right={cosf(b)*radius,base_y,sinf(b)*radius};
        vector_float3 normal=simd_normalize(simd_cross(right-tip,left-tip));
        add_vertex(v,count,max,tip,normal,tint);
        add_vertex(v,count,max,right,normal,tint);
        add_vertex(v,count,max,left,normal,tint);
    }
}
static Vertex *make_tree(unsigned *count){
    Vertex *v=(Vertex *)calloc(1300,sizeof(Vertex));if(!v)return NULL;
    *count=0;
    vector_float4 green={.08f,.43f,.29f,1},green2={.06f,.32f,.25f,1};
    vector_float4 brown={.32f,.22f,.16f,1};
    add_ellipsoid(v,count,1300,(vector_float3){0,.6f,0},(vector_float3){.18f,.7f,.18f},brown);
    add_cone(v,count,1300,.9f,4.0f,1.24f,green);
    add_cone(v,count,1300,1.5f,4.7f,.91f,green2);
    return v;
}
static Vertex *make_fish(unsigned *count){
    Vertex *v=(Vertex *)calloc(3500,sizeof(Vertex));if(!v)return NULL;
    *count=0;
    vector_float4 gold={1.0f,.72f,.13f,1},fin={1.0f,.50f,.08f,1};
    add_ellipsoid(v,count,3500,(vector_float3){0,0,0},
                  (vector_float3){.60f,.24f,.22f},gold);
    add_cone(v,count,3500,-.15f,.48f,.23f,fin);
    return v;
}
static void add_box(Vertex *v,unsigned *count,unsigned max,vector_float3 a,
                    vector_float3 b,vector_float4 tint){
    const int faces[6][4]={{0,1,3,2},{4,6,7,5},{0,2,6,4},
      {1,5,7,3},{2,3,7,6},{0,4,5,1}};
    vector_float3 p[8];
    for(int i=0;i<8;i++)p[i]=(vector_float3){
      (i&1)?b.x:a.x,(i&2)?b.y:a.y,(i&4)?b.z:a.z};
    for(int i=0;i<6;i++){
        vector_float3 u=p[faces[i][1]]-p[faces[i][0]];
        vector_float3 w=p[faces[i][2]]-p[faces[i][0]];
        vector_float3 norm=simd_normalize(simd_cross(u,w));
        int tri[6]={0,1,2,0,2,3};
        for(int j=0;j<6;j++)add_vertex(v,count,max,p[faces[i][tri[j]]],norm,tint);
    }
}
static Vertex *make_gate(unsigned *count,int finish){
    Vertex *v=(Vertex *)calloc(256,sizeof(Vertex));if(!v)return NULL;*count=0;
    vector_float4 pole={.12f,.20f,.28f,1};
    vector_float4 beam=finish?(vector_float4){1.0f,.72f,.10f,1}:
                              (vector_float4){.19f,.83f,.91f,1};
    add_box(v,count,256,(vector_float3){-8,0,-.20f},
            (vector_float3){-7.45f,6,.20f},pole);
    add_box(v,count,256,(vector_float3){7.45f,0,-.20f},
            (vector_float3){8,6,.20f},pole);
    add_box(v,count,256,(vector_float3){-8,5.4f,-.4f},
            (vector_float3){8,6,.4f},beam);
    return v;
}
static matrix_float4x4 translate(float x,float y,float z){
    matrix_float4x4 result=matrix_identity_float4x4;
    result.columns[3]=(vector_float4){x,y,z,1};
    return result;
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
    UIView *metalUIKitView=(__bridge UIView *)metalView;
    UILabel *hud=[[UILabel alloc] initWithFrame:CGRectZero];
    hud.textColor=[UIColor whiteColor];
    hud.font=[UIFont monospacedSystemFontOfSize:15 weight:UIFontWeightSemibold];
    hud.numberOfLines=3;
    hud.text=@"SUMMIT RUN\\nStarting race...";
    hud.backgroundColor=[[UIColor colorWithRed:.02 green:.10 blue:.18 alpha:1] colorWithAlphaComponent:.57];
    hud.layer.cornerRadius=11;
    hud.layer.masksToBounds=YES;
    [metalUIKitView addSubview:hud];

    UILabel *controls=[[UILabel alloc] initWithFrame:CGRectZero];
    controls.text=@"◀ STEER       TAP CENTER TO JUMP / HOLD LOWER CENTER TO BRAKE       STEER ▶";
    controls.textAlignment=NSTextAlignmentCenter;
    controls.textColor=[[UIColor whiteColor] colorWithAlphaComponent:.85];
    controls.font=[UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    controls.backgroundColor=[[UIColor blackColor] colorWithAlphaComponent:.22];
    [metalUIKitView addSubview:controls];


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

    unsigned tuxCount=0;
    Vertex *tuxVertices=make_penguin(&tuxCount);
    if(!tuxVertices){SDL_Log("Tux mesh allocation failed");return 9;}
    id<MTLBuffer> tuxBuffer=[device newBufferWithBytes:tuxVertices
        length:sizeof(Vertex)*tuxCount options:MTLResourceStorageModeShared];
    free(tuxVertices);
    if(!tuxBuffer){SDL_Log("Tux GPU buffer failed");return 10;}

    unsigned treeCount=0,fishCount=0,startCount=0,finishCount=0;
    Vertex *treeVertices=make_tree(&treeCount),*fishVertices=make_fish(&fishCount);
    Vertex *startVertices=make_gate(&startCount,0),*finishVertices=make_gate(&finishCount,1);
    if(!treeVertices||!fishVertices||!startVertices||!finishVertices){
        SDL_Log("World object mesh allocation failed");return 11;
    }
    id<MTLBuffer> treeBuffer=[device newBufferWithBytes:treeVertices
        length:treeCount*sizeof(Vertex) options:MTLResourceStorageModeShared];
    id<MTLBuffer> fishBuffer=[device newBufferWithBytes:fishVertices
        length:fishCount*sizeof(Vertex) options:MTLResourceStorageModeShared];
    id<MTLBuffer> startBuffer=[device newBufferWithBytes:startVertices
        length:startCount*sizeof(Vertex) options:MTLResourceStorageModeShared];
    id<MTLBuffer> finishBuffer=[device newBufferWithBytes:finishVertices
        length:finishCount*sizeof(Vertex) options:MTLResourceStorageModeShared];
    free(treeVertices);free(fishVertices);free(startVertices);free(finishVertices);
    if(!treeBuffer||!fishBuffer||!startBuffer||!finishBuffer){
        SDL_Log("World object GPU buffer creation failed");return 12;
    }

    RaceConfig settings={course.length,course.width,course.startSpeed,
       course.maxSpeed,20.0f,38.0f,150.0f,8241u};
    RaceState race={0};
    race_reset(&race,&settings);
    bool was_finished=false;
    int previousWidth=0,previousHeight=0;
    id<MTLTexture> depthTexture=nil;
    float smoothCameraX=0,smoothCameraZ=-15.0f,smoothCameraY=7;
    bool running=true,suspended=false;
    SDL_GameController *controller=NULL;
    for(int i=0;i<SDL_NumJoysticks();i++)
        if(SDL_IsGameController(i)){controller=SDL_GameControllerOpen(i);if(controller)break;}
    Uint64 last=SDL_GetPerformanceCounter(),frequency=SDL_GetPerformanceFrequency();
    while(running){
        @autoreleasepool {
            SDL_Event ev;
            int restart=0,pause=0;
            while(SDL_PollEvent(&ev)){
                if(ev.type==SDL_QUIT)running=false;
                if(ev.type==SDL_APP_WILLENTERBACKGROUND || ev.type==SDL_APP_DIDENTERBACKGROUND)suspended=true;
                if(ev.type==SDL_APP_WILLENTERFOREGROUND || ev.type==SDL_APP_DIDENTERFOREGROUND)suspended=false;
                if(ev.type==SDL_KEYDOWN && ev.key.repeat==0){
                    if(ev.key.keysym.sym==SDLK_r || ev.key.keysym.sym==SDLK_RETURN)restart=1;
                    if(ev.key.keysym.sym==SDLK_p || ev.key.keysym.sym==SDLK_ESCAPE)pause=1;
                }
                if(ev.type==SDL_CONTROLLERDEVICEADDED && !controller &&
                   SDL_IsGameController(ev.cdevice.which))
                    controller=SDL_GameControllerOpen(ev.cdevice.which);
                if(ev.type==SDL_CONTROLLERDEVICEREMOVED && controller &&
                   SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(controller))==ev.cdevice.which){
                    SDL_GameControllerClose(controller);controller=NULL;
                }
            }
            if(!running)break;
            if(suspended){SDL_Delay(30);last=SDL_GetPerformanceCounter();continue;}
            Uint64 now=SDL_GetPerformanceCounter();
            float dt=fminf((float)((double)(now-last)/frequency),.033f);last=now;
            const Uint8 *keys=SDL_GetKeyboardState(NULL);
            RaceInput input={0};
            input.steer=(keys[SDL_SCANCODE_A]||keys[SDL_SCANCODE_LEFT])?-1:
                  (keys[SDL_SCANCODE_D]||keys[SDL_SCANCODE_RIGHT])?1:0;
            input.brake=keys[SDL_SCANCODE_S]||keys[SDL_SCANCODE_DOWN];
            input.jump=keys[SDL_SCANCODE_SPACE]||keys[SDL_SCANCODE_UP];
            input.restart=restart;
            input.pause=pause;
            int touches=SDL_GetNumTouchDevices();
            for(int i=0;i<touches;i++){
                SDL_TouchID id=SDL_GetTouchDevice(i);
                for(int j=0;j<SDL_GetNumTouchFingers(id);j++){
                    SDL_Finger *finger=SDL_GetTouchFinger(id,j);
                    if(!finger)continue;
                    if(finger->x<.30f)input.steer=-1;
                    if(finger->x>.70f)input.steer=1;
                    if(finger->x>.36f&&finger->x<.64f){
                       if(finger->y>.83f)input.brake=1;
                       else input.jump=1;
                    }
                    if(race.phase==RACE_FINISHED)input.restart=1;
                }
            }
            if(controller){
                float lx=SDL_GameControllerGetAxis(controller,SDL_CONTROLLER_AXIS_LEFTX)/32768.0f;
                if(fabsf(lx)>.17f)input.steer=lx;
                if(SDL_GameControllerGetButton(controller,SDL_CONTROLLER_BUTTON_A))input.jump=1;
                if(SDL_GameControllerGetButton(controller,SDL_CONTROLLER_BUTTON_B))input.brake=1;
            }
            if(input.restart){smoothCameraX=0;smoothCameraZ=-15;smoothCameraY=7;was_finished=false;}
            race_step(&race,&settings,input,dt);
            if(race.phase==RACE_FINISHED && !was_finished){
                SDL_Log("FINISH Summit Run: %.2fs, fish %d, hits %d, checkpoints %d",
                        race.time_seconds,race.fish,race.hits,race.checkpoints);
                was_finished=true;
            }
            if((int)(race.time_seconds*2)!=(int)((race.time_seconds-dt)*2) &&
                race.phase==RACE_RUNNING){
                SDL_LogDebug(SDL_LOG_CATEGORY_APPLICATION,
                  "Summit Run %.0f/%.0fm speed %.0f km/h fish %d hits %d",
                  race.distance,settings.length,race.speed*3.6f,race.fish,race.hits);
            }
            CGRect display=metalUIKitView.bounds;
            CGFloat screenWidth=display.size.width,screenHeight=display.size.height;
            hud.frame=CGRectMake(screenWidth*.075,screenHeight*.025,
                                  screenWidth*.62,screenHeight*.125);
            controls.frame=CGRectMake(screenWidth*.14,screenHeight*.91,
                                      screenWidth*.72,screenHeight*.045);
            if((int)(race.time_seconds*6)!=(int)((race.time_seconds-dt)*6)
                ||race.phase!=RACE_RUNNING){
                NSString *status=race.phase==RACE_FINISHED?@"FINISHED! TAP TO RESTART":
                                 race.phase==RACE_PAUSED?@"PAUSED  P TO RESUME":@"SUMMIT RUN";
                hud.text=[NSString stringWithFormat:
                    @"  %@\\n  %03.0f / %.0fm   %02.0f km/h\\n  TIME %.1fs   FISH %d   HITS %d",
                    status,race.distance,course.length,race.speed*3.6f,
                    race.time_seconds,race.fish,race.hits];
            }
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
            /* Chase camera follows the sampled snow surface, not an arbitrary
             * fixed Y target; avoids looking through/under the hill. */
            float desiredCamX=race.lateral*.82f;
            float desiredCamZ=race.distance-15.0f;
            float desiredCamY=ground(desiredCamX,desiredCamZ,course.slope)+6.5f;
            float spring=1.0f-expf(-5.5f*dt);
            smoothCameraX+=(desiredCamX-smoothCameraX)*spring;
            smoothCameraZ+=(desiredCamZ-smoothCameraZ)*spring;
            smoothCameraY+=(desiredCamY-smoothCameraY)*spring;
            vector_float3 eye={smoothCameraX,smoothCameraY,smoothCameraZ};
            float lookZ=race.distance+24.0f;
            float lookY=ground(race.lateral,lookZ,course.slope)+2.2f;
            vector_float3 target={race.lateral,lookY,lookZ};
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
            matrix_float4x4 tuxModel=translate(race.lateral,
                ground(race.lateral,race.distance+3.5f,course.slope)+race.jump_height,
                race.distance+3.5f);
            Uniforms tuxUniform={simd_mul(proj,simd_mul(view,tuxModel)),tuxModel};
            [encoder setVertexBuffer:tuxBuffer offset:0 atIndex:0];
            [encoder setVertexBytes:&tuxUniform length:sizeof(tuxUniform) atIndex:1];
            [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:tuxCount];
            /* Draw authored-course objects with the same depth buffer and
             * world coordinates as terrain and player. Cull behind-camera
             * instances to keep command count bounded on mobile. */
            const int max_tree=race_objects_count(&settings,0);
            const int max_fish=race_objects_count(&settings,1);
            for(int kind=0;kind<2;kind++){
                int count=kind?max_fish:max_tree;
                for(int i=0;i<count;i++){
                    float x=0,z=0;race_object_at(&settings,kind,i,&x,&z);
                    if(z<race.distance-11.0f||z>race.distance+170.0f)continue;
                    if(kind && z<race.distance-2.0f)continue;
                    float groundHeight=ground(x,z,course.slope);
                    float hover=kind?(1.20f+.22f*sinf(race.time_seconds*3.2f+i)):0;
                    matrix_float4x4 model=translate(x,groundHeight+hover,z);
                    Uniforms u={simd_mul(proj,simd_mul(view,model)),model};
                    [encoder setVertexBuffer:(kind?fishBuffer:treeBuffer) offset:0 atIndex:0];
                    [encoder setVertexBytes:&u length:sizeof(u) atIndex:1];
                    [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                        vertexStart:0 vertexCount:(kind?fishCount:treeCount)];
                }
            }
            for(int gate=0;gate<2;gate++){
                float z=gate?course.length:8.0f;
                if(z<race.distance-30.0f||z>race.distance+175.0f)continue;
                matrix_float4x4 model=translate(0,ground(0,z,course.slope),z);
                Uniforms u={simd_mul(proj,simd_mul(view,model)),model};
                [encoder setVertexBuffer:(gate?finishBuffer:startBuffer) offset:0 atIndex:0];
                [encoder setVertexBytes:&u length:sizeof(u) atIndex:1];
                [encoder drawPrimitives:MTLPrimitiveTypeTriangle
                    vertexStart:0 vertexCount:(gate?finishCount:startCount)];
            }
            [encoder endEncoding];
            [command presentDrawable:drawable];
            [command commit];
        }
    }
    if(controller)SDL_GameControllerClose(controller);
    SDL_Metal_DestroyView(metalView);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 0;
}
