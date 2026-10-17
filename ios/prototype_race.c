/*
 * Tux Racer Modern — iOS interactive course-loop prototype.
 *
 * PROTOTYPE ONLY: 2.5D SDL Metal-rendered downhill control sandbox.
 * This is not the original Tcl course loader, physics, or renderer.
 * Its purpose is to validate a playable input/render/frame loop on iOS.
 *
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include <SDL.h>
#include <SDL_render.h>
#include <math.h>
#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include "mobile_input.h"
#include "original_course.h"

#define FALLBACK_TRACK_METERS 1200.0f
static tux_original_course g_course;
static float g_track_meters = FALLBACK_TRACK_METERS;
static int g_original_course_loaded = 0;
#define PI 3.14159265358979323846f

typedef struct {
    float x, distance, speed, time, jump_time;
    int hits, fish, finished, paused;
} Race;

static const char *const font[] = {
    "A:01110100011000111111100011000110001",
    "B:11110100011000111110100011000111110",
    "C:01111100001000010000100001000001111",
    "D:11110100011000110001100011000111110",
    "E:11111100001000011110100001000011111",
    "F:11111100001000011110100001000010000",
    "G:01111100001000010111100011000101111",
    "H:10001100011000111111100011000110001",
    "I:11111001000010000100001000010011111",
    "J:00111000100001000010100101001001100",
    "K:10001100101010011000101001001010001",
    "L:10000100001000010000100001000011111",
    "M:10001110111010110101100011000110001",
    "N:10001110011010110011100011000110001",
    "O:01110100011000110001100011000101110",
    "P:11110100011000111110100001000010000",
    "R:11110100011000111110101001001010001",
    "S:01111100001000001110000010000111110",
    "T:11111001000010000100001000010000100",
    "U:10001100011000110001100011000101110",
    "V:10001100011000110001010100101000100",
    "W:10001100011000110101101011101110001",
    "X:10001100010101000100010101000110001",
    "Y:10001100010101000100001000010000100",
    "Z:11111000010001000100010001000011111",
    "0:01110100011001110101110011000101110",
    "1:00100011000010000100001000010001110",
    "2:01110100010000100010001000100011111",
    "3:11110000010000101110000010000111110",
    "4:00010001100101010010111110001000010",
    "5:11111100001000011110000010000111110",
    "6:01110100001000011110100011000101110",
    "7:11111000010001000100010000100001000",
    "8:01110100011000101110100011000101110",
    "9:01110100011000101111000010000101110",
    ".:00000000000000000000000000110001100",
    ":00000011000110000000011000110000000",
    "/:00001000010001000100010001000010000",
    "-:00000000000000011111000000000000000",
    " :00000000000000000000000000000000000",
    NULL
};
static void color(SDL_Renderer *r, int R, int G, int B, int A)
{ SDL_SetRenderDrawColor(r,(Uint8)R,(Uint8)G,(Uint8)B,(Uint8)A); }
static void rect(SDL_Renderer *r,float x,float y,float w,float h)
{ SDL_Rect q={(int)x,(int)y,(int)w,(int)h};SDL_RenderFillRect(r,&q); }
static void line(SDL_Renderer *r,float x,float y,float xx,float yy)
{ SDL_RenderDrawLine(r,(int)x,(int)y,(int)xx,(int)yy); }
static void text(SDL_Renderer *r,const char *message,int x,int y,int scale) {
    for(const char *s=message;*s;s++,x+=6*scale) {
        const char *bits=NULL;
        for(int i=0;font[i];i++)if(font[i][0]==*s&&font[i][1]==':') {bits=font[i]+2;break;}
        if(!bits)continue;
        for(int row=0;row<7;row++)for(int col=0;col<5;col++)
            if(bits[row*5+col]=='1')rect(r,x+col*scale,y+row*scale,scale,scale);
    }
}
static float clampf(float x,float a,float b) {return x<a?a:x>b?b:x;}
static void load_original_course(void) {
    /* SDL_GetBasePath points into the .app bundle on iOS. Asset paths stay
     * read-only; save data must use SDL_GetPrefPath separately. */
    char path[2048];
    char *base = SDL_GetBasePath();
    if (!base) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,"SDL_GetBasePath unavailable");
        return;
    }
    int n=snprintf(path,sizeof(path),"%sdata/courses/bunny_hill/course.tcl",base);
    SDL_free(base);
    if(n<0||(size_t)n>=sizeof(path))return;
    if(tux_original_course_load(path,&g_course)){
        g_original_course_loaded=1;
        g_track_meters=g_course.play_length_m;
        SDL_Log("Loaded ORIGINAL course metadata: %s, %.0f x %.0f m, slope %.1f deg, elevation %s, terrain %s",
          g_course.name,g_course.width_m,g_course.length_m,g_course.angle_deg,
          g_course.elevation_file,g_course.terrain_file);
    }else SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
      "Original Bunny Hill course metadata missing at %s; retaining prototype track",path);
}
static void reset(Race *race) {
    memset(race,0,sizeof(*race));
    race->speed=9.0f;
}
static float path(float z){return sinf(z*0.0068f)*0.30f+sinf(z*0.013f)*0.12f;}
static float obstacle_x(int i){return sinf(i*12.73f)*0.78f;}
static float obstacle_z(int i){return 55.0f+i*31.0f;}
static void polygon_course(SDL_Renderer *r,float a,float b,float c,float d,float top,float bottom,int R,int G,int B){
    /* scanline fill trapezoid, left at top/bottom = a/b, right = c/d */
    color(r,R,G,B,255);
    int yt=(int)top,yb=(int)bottom;
    if(yb<=yt)return;
    for(int y=yt;y<=yb;y+=3){
        float t=(float)(y-yt)/(float)(yb-yt);
        float left=a+(b-a)*t,right=c+(d-c)*t;
        rect(r,left,(float)y,right-left,4);
    }
}
static void draw_tree(SDL_Renderer *r,float x,float y,float s){
    if(s<2)return;
    color(r,72,56,48,255);rect(r,x-s*.08f,y-s*.10f,s*.16f,s*.34f);
    color(r,17,73,64,255);
    for(int i=0;i<3;i++){
        float yy=y-s*(0.20f+i*.22f),wide=s*(.4f-i*.09f);
        for(int k=0;k<(int)(s*.35f);k+=3){
            float t=(float)k/(s*.35f),xx=wide*(1.0f-t);
            rect(r,x-xx,yy-k,xx*2+2,4);
        }
    }
}
static void draw_penguin(SDL_Renderer *r,float x,float y,float s,float tilt,int airborne) {
    color(r,16,28,40,120);
    rect(r,x-s*.40f,y+s*.22f,s*.8f,s*.12f);
    float by=y-(airborne?s*.28f:0);
    color(r,7,22,35,255);rect(r,x-s*.24f+tilt,by-s*.85f,s*.48f,s*.77f);
    color(r,245,247,236,255);rect(r,x-s*.15f+tilt,by-s*.68f,s*.30f,s*.48f);
    color(r,10,20,29,255);rect(r,x-s*.40f+tilt,by-s*.50f,s*.20f,s*.16f);
    rect(r,x+s*.20f+tilt,by-s*.50f,s*.20f,s*.16f);
    color(r,244,177,52,255);rect(r,x-s*.15f+tilt,by-s*.09f,s*.12f,s*.09f);
    rect(r,x+s*.05f+tilt,by-s*.09f,s*.12f,s*.09f);
    color(r,251,181,46,255);rect(r,x-s*.11f+tilt,by-s*.62f,s*.22f,s*.07f);
    color(r,255,255,255,255);rect(r,x-s*.12f+tilt,by-s*.76f,s*.08f,s*.07f);
    rect(r,x+s*.04f+tilt,by-s*.76f,s*.08f,s*.07f);
}
static void draw_scene(SDL_Renderer *r,int w,int h,const Race *race,const tux_mobile_input *in){
    float horizon=h*.34f,ground=h*.83f;
    color(r,10,35,59,255);SDL_RenderClear(r);
    color(r,21,60,85,255);rect(r,0,h*.18f,w,h*.20f);
    color(r,175,209,220,255);
    for(int k=0;k<24;k++){
        float p=k/23.0f,center=w*p;
        float mountain=h*(.19f+.10f*sinf(k*2.34f));
        for(int yy=(int)(horizon-mountain);yy<(int)horizon;yy+=4){
            float b=(float)(yy-(horizon-mountain))/mountain;
            float half=w*.030f*b;
            rect(r,center-half,yy,half*2+2,4);
        }
    }
    color(r,219,238,240,255);rect(r,0,horizon,w,h-horizon);
    color(r,235,247,247,255);rect(r,0,h*.70f,w,h*.30f);
    const int strips=65;
    for(int i=strips-1;i>=0;i--){
        float neari=(float)i/strips,far=(float)(i+1)/strips;
        float dn=5.0f+neari*190.0f,df=5.0f+far*190.0f;
        float yn=ground-(ground-horizon)*(dn/(dn+30.0f));
        float yf=ground-(ground-horizon)*(df/(df+30.0f));
        float hn=w*(.12f+.42f/(1.0f+dn*.055f));
        float hf=w*(.12f+.42f/(1.0f+df*.055f));
        float cn=w*.5f+(path(race->distance+dn)-race->x*.24f)*w*.18f;
        float cf=w*.5f+(path(race->distance+df)-race->x*.24f)*w*.18f;
        int shade= ((int)((race->distance+dn)/13))%2;
        polygon_course(r,cf-hf,cn-hn,cf+hf,cn+hn,yf,yn,shade?200:212,shade?231:241,241);
        if(((int)((race->distance+dn)/19))%3==0){
            color(r,131,187,206,255);line(r,cn-hn*.80f,yn,cf-hf*.80f,yf);
            line(r,cn+hn*.80f,yn,cf+hf*.80f,yf);
        }
    }
    for(int i=0;i<45;i++){
        float dz=obstacle_z(i)-race->distance;
        if(dz<3||dz>160)continue;
        float p=1.0f/(1.0f+dz*.045f);
        float cy=ground-(ground-horizon)*(dz/(dz+30.0f));
        float cx=w*.5f+(path(race->distance+dz)-race->x*.24f)*w*.18f;
        float treeX=cx+obstacle_x(i)*w*(.12f+.30f*p);
        draw_tree(r,treeX,cy,clampf(p*w*.095f,4,125));
    }
    draw_penguin(r,w*.50f,ground+h*.065f,clampf(h*.17f,30,155),-in->steering*w*.013f,race->jump_time>0);
    color(r,10,40,64,220);rect(r,0,0,w,h*.13f);
    color(r,245,250,252,255);
    char buf[96];
    text(r,g_original_course_loaded?"BUNNY HILL - ORIGINAL COURSE DATA":"TUX RACER - MOBILE PROTOTYPE",
      (int)(w*.02f),(int)(h*.024f),clampf(w/250,2,5));
    snprintf(buf,sizeof(buf),"TIME %02d:%02d  SPEED %02d  FISH %d  HITS %d",
      (int)race->time/60,(int)race->time%60,(int)(race->speed*3.6f),race->fish,race->hits);
    text(r,buf,(int)(w*.02f),(int)(h*.085f),clampf(w/280,2,4));
    color(r,15,50,78,190);rect(r,w*.15f,h*.945f,w*.70f,h*.027f);
    color(r,238,183,56,255);rect(r,w*.15f,h*.945f,w*.70f*clampf(race->distance/g_track_meters,0,1),h*.027f);
    color(r,18,41,66,155);
    rect(r,0,h*.69f,w*.19f,h*.24f);rect(r,w*.81f,h*.69f,w*.19f,h*.24f);
    rect(r,w*.40f,h*.70f,w*.20f,h*.24f);
    color(r,255,255,255,255);
    text(r,"LEFT",(int)(w*.025f),(int)(h*.78f),clampf(w/255,2,4));
    text(r,"RIGHT",(int)(w*.824f),(int)(h*.78f),clampf(w/255,2,4));
    text(r,"JUMP",(int)(w*.435f),(int)(h*.78f),clampf(w/255,2,4));
    if(race->finished){
        color(r,11,35,57,240);rect(r,w*.19f,h*.24f,w*.62f,h*.38f);
        color(r,244,240,179,255);
        text(r,"FINISH!",(int)(w*.37f),(int)(h*.32f),clampf(w/180,3,7));
        text(r,"TAP TO RESTART",(int)(w*.30f),(int)(h*.49f),clampf(w/210,2,5));
    }else if(race->paused){
        color(r,13,31,52,215);rect(r,w*.30f,h*.36f,w*.40f,h*.18f);
        color(r,255,255,255,255);text(r,"PAUSED",(int)(w*.39f),(int)(h*.42f),clampf(w/210,2,5));
    }
    SDL_RenderPresent(r);
}
static void accumulate_touch(tux_mobile_input *in,float x,float y){
    if(x<.32f)in->steering=-1;
    else if(x>.68f)in->steering=1;
    if(y>.89f&&x>.34f&&x<.66f)in->brake=1;
    if(x>=.32f&&x<=.68f&&y<.89f)in->jump=1;
    in->accelerate=1;
}
int main(int argc,char **argv) {
    (void)argc;(void)argv;
    SDL_SetHint(SDL_HINT_RENDER_DRIVER,"metal");
    SDL_SetHint(SDL_HINT_ORIENTATIONS,"LandscapeLeft LandscapeRight");
    if(SDL_Init(SDL_INIT_VIDEO|SDL_INIT_EVENTS|SDL_INIT_GAMECONTROLLER)!=0){
        SDL_Log("SDL_Init failed: %s",SDL_GetError());return 1;
    }
    SDL_Window *window=SDL_CreateWindow("Tux Racer Modern — playable input prototype",
       SDL_WINDOWPOS_UNDEFINED,SDL_WINDOWPOS_UNDEFINED,1280,720,
       SDL_WINDOW_METAL|SDL_WINDOW_ALLOW_HIGHDPI|SDL_WINDOW_FULLSCREEN);
    if(!window){SDL_Log("SDL_CreateWindow: %s",SDL_GetError());SDL_Quit();return 2;}
    SDL_Renderer *renderer=SDL_CreateRenderer(window,-1,
       SDL_RENDERER_ACCELERATED|SDL_RENDERER_PRESENTVSYNC);
    if(!renderer){SDL_Log("SDL_CreateRenderer: %s",SDL_GetError());SDL_DestroyWindow(window);SDL_Quit();return 3;}
    SDL_RendererInfo info;
    SDL_GetRendererInfo(renderer,&info);
    SDL_Log("Tux iOS playable prototype renderer: %s",info.name);
    if(strcmp(info.name,"metal")!=0)SDL_LogWarn(SDL_LOG_CATEGORY_RENDER,"Metal renderer was requested but not selected");
    SDL_SetRenderDrawBlendMode(renderer,SDL_BLENDMODE_BLEND);
    SDL_GameController *controller=NULL;
    for(int i=0;i<SDL_NumJoysticks();i++){
        if(SDL_IsGameController(i)){
            controller=SDL_GameControllerOpen(i);
            if(controller)break;
        }
    }
    load_original_course();
    Race race;reset(&race);
    bool mouse_down=false;
    float mouse_x=0,mouse_y=0;
    Uint64 last=SDL_GetPerformanceCounter();
    Uint64 frequency=SDL_GetPerformanceFrequency();
    bool running=true;
    while(running){
        SDL_Event event;
        while(SDL_PollEvent(&event)){
            switch(event.type){
            case SDL_QUIT:running=false;break;
            case SDL_CONTROLLERDEVICEADDED:
                if(!controller&&SDL_IsGameController(event.cdevice.which))
                    controller=SDL_GameControllerOpen(event.cdevice.which);
                break;
            case SDL_CONTROLLERDEVICEREMOVED:
                if(controller&&SDL_JoystickInstanceID(SDL_GameControllerGetJoystick(controller))==event.cdevice.which){
                    SDL_GameControllerClose(controller);controller=NULL;
                }
                break;
            case SDL_APP_WILLENTERBACKGROUND:
            case SDL_APP_DIDENTERBACKGROUND:race.paused=1;break;
            case SDL_APP_DIDENTERFOREGROUND:race.paused=0;break;
            case SDL_FINGERDOWN:
                if(race.finished)reset(&race);
                break;
            case SDL_MOUSEBUTTONDOWN:
                if(event.button.which==SDL_TOUCH_MOUSEID)break;
                if(race.finished)reset(&race);
                mouse_down=true;
                break;
            case SDL_MOUSEBUTTONUP:
                if(event.button.which!=SDL_TOUCH_MOUSEID)mouse_down=false;
                break;
            case SDL_KEYDOWN:
                if(event.key.keysym.sym==SDLK_p||event.key.keysym.sym==SDLK_ESCAPE)race.paused=!race.paused;
                if(event.key.keysym.sym==SDLK_r)reset(&race);
                break;
            default:break;
            }
        }
        const Uint8 *keys=SDL_GetKeyboardState(NULL);
        tux_mobile_input frame;
        tux_mobile_input_reset(&frame);
        /* Recompute simultaneous active touches each frame: steer + jump/brake. */
        int devices=SDL_GetNumTouchDevices();
        for(int t=0;t<devices;t++){
            SDL_TouchID id=SDL_GetTouchDevice(t);
            int fingers=SDL_GetNumTouchFingers(id);
            for(int k=0;k<fingers;k++){
                SDL_Finger *finger=SDL_GetTouchFinger(id,k);
                if(finger)accumulate_touch(&frame,finger->x,finger->y);
            }
        }
        if(mouse_down){
            int w=0,h=0,mx=0,my=0;
            SDL_GetWindowSize(window,&w,&h);
            SDL_GetMouseState(&mx,&my);
            if(w>0&&h>0)accumulate_touch(&frame,(float)mx/w,(float)my/h);
        }
        if(keys[SDL_SCANCODE_LEFT]||keys[SDL_SCANCODE_A])frame.steering=-1;
        if(keys[SDL_SCANCODE_RIGHT]||keys[SDL_SCANCODE_D])frame.steering=1;
        if(keys[SDL_SCANCODE_SPACE]||keys[SDL_SCANCODE_UP])frame.jump=1;
        if(keys[SDL_SCANCODE_DOWN]||keys[SDL_SCANCODE_S])frame.brake=1;
        if(controller){
            Sint16 axis=SDL_GameControllerGetAxis(controller,SDL_CONTROLLER_AXIS_LEFTX);
            float analog=(float)axis/32768.0f;
            if(fabsf(analog)>.16f)frame.steering=analog;
            if(SDL_GameControllerGetButton(controller,SDL_CONTROLLER_BUTTON_A))
                frame.jump=1;
            if(SDL_GameControllerGetButton(controller,SDL_CONTROLLER_BUTTON_B))
                frame.brake=1;
            if(SDL_GameControllerGetButton(controller,SDL_CONTROLLER_BUTTON_START))
                frame.pause=1;
        }
        Uint64 now=SDL_GetPerformanceCounter();
        float dt=clampf((float)((double)(now-last)/(double)frequency),0.0f,.05f);
        last=now;
        if(!race.paused&&!race.finished){
            float prev=race.distance;
            float force=frame.brake?-24.0f:8.0f;
            race.speed=clampf(race.speed+force*dt,4.0f,29.0f);
            race.x=clampf(race.x+frame.steering*dt*(.68f+race.speed*.026f),-1.25f,1.25f);
            if(frame.jump&&race.jump_time<=0)race.jump_time=.75f;
            else race.jump_time=clampf(race.jump_time-dt,0,1);
            race.distance+=race.speed*dt;
            race.time+=dt;
            for(int i=0;i<45;i++)if(obstacle_z(i)>prev&&obstacle_z(i)<=race.distance){
                if(fabsf(race.x-obstacle_x(i))<.19f&&race.jump_time<=0){
                    race.hits++;race.speed*=.50f;
                } else race.fish++;
            }
            if(race.distance>=g_track_meters){race.distance=g_track_meters;race.finished=1;}
        }
        int w=0,h=0;SDL_GetRendererOutputSize(renderer,&w,&h);
        if(w>0&&h>0)draw_scene(renderer,w,h,&race,&frame);
        else SDL_Delay(16);
    }
    if(controller)SDL_GameControllerClose(controller);
    SDL_DestroyRenderer(renderer);SDL_DestroyWindow(window);SDL_Quit();return 0;
}
