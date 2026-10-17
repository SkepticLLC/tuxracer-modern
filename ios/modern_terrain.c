/*
 * Modern iOS terrain visualization for original Tux Racer course heightmaps.
 * Keeps continuous shared vertex topology, perspective-projected slope,
 * material-aware shading and distance fog. Draws via SDL2 Metal renderer.
 *
 * Transitional camera and player movement. The historic physics, vegetation,
 * Tux model and race modes have not yet been ported.
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "modern_terrain.h"
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define MESH_X 64
#define MESH_Z 112
#define N_VERT ((MESH_X + 1) * (MESH_Z + 1))
#define N_INDEX (MESH_X * MESH_Z * 6)
#define PI_F 3.14159265358979323846f

struct tux_modern_terrain {
    SDL_Vertex *vertices;
    int *indices;
    float camera_x;
    float camera_z;
    float camera_y;
    float last_distance;
    float last_x;
    int initialized;
};

static float clamp01(float v) { return v < 0.0f ? 0.0f : v > 1.0f ? 1.0f : v; }
static float mixf(float a,float b,float t){return a+(b-a)*t;}
static float bound(float x,float lo,float hi){return x<lo?lo:x>hi?hi:x;}
static Uint8 bytef(float f){return (Uint8)(bound(f,0.0f,255.0f)+0.5f);}
static SDL_Color blend(SDL_Color a,SDL_Color b,float t){
    float q=clamp01(t);
    SDL_Color result={
        bytef(mixf(a.r,b.r,q)),bytef(mixf(a.g,b.g,q)),
        bytef(mixf(a.b,b.b,q)),255
    };
    return result;
}
static SDL_Color tint(SDL_Color c,float brightness){
    SDL_Color result={bytef(c.r*brightness),bytef(c.g*brightness),
                      bytef(c.b*brightness),255};
    return result;
}
/* Pixel values 0=ice,127=rock,255=snow, per original course_load.c.
 * Bilinear color blending reduces grid-aligned stair steps at transitions.
 */
static SDL_Color pixel_material(unsigned int pixel){
    static const SDL_Color ice={113,197,224,255};
    static const SDL_Color rock={112,131,149,255};
    static const SDL_Color snow={231,242,246,255};
    if(pixel<=127)return blend(ice,rock,(float)pixel/127.0f);
    return blend(rock,snow,(float)(pixel-127)/128.0f);
}
static SDL_Color surface_color(const tux_original_terrain *map,float u,float v){
    float fx=clamp01(u)*(map->width-1);
    float fy=clamp01(v)*(map->height-1);
    int x=(int)fx,y=(int)fy;
    int xx=x+1<map->width?x+1:x;
    int yy=y+1<map->height?y+1:y;
    float tx=fx-x,ty=fy-y;
    SDL_Color a=blend(pixel_material(map->surface[y*map->width+x]),
                      pixel_material(map->surface[y*map->width+xx]),tx);
    SDL_Color b=blend(pixel_material(map->surface[yy*map->width+x]),
                      pixel_material(map->surface[yy*map->width+xx]),tx);
    return blend(a,b,ty);
}
static float ground_y(const tux_original_terrain *map,const tux_original_course *course,
                       float world_x,float world_z){
    float u=clamp01(world_x/course->width_m);
    float v=clamp01(world_z/course->length_m);
    float slope=tanf(course->angle_deg*PI_F/180.0f);
    /* The original heightmap is embedded in a downhill 25-degree plane. */
    return -world_z*slope
         +tux_original_elevation(map,u,v)*course->elevation_scale/255.0f;
}
static SDL_Color light_terrain(const tux_original_terrain *map,
                               const tux_original_course *course,
                               float x,float z,float distance){
    const float step_x=course->width_m/(float)(map->width-1);
    const float step_z=course->length_m/(float)(map->height-1);
    float hl=ground_y(map,course,x-step_x,z);
    float hr=ground_y(map,course,x+step_x,z);
    float hn=ground_y(map,course,x,z-step_z);
    float hf=ground_y(map,course,x,z+step_z);
    float dx=(hr-hl)/(2*step_x);
    float dz=(hf-hn)/(2*step_z);
    /* Light comes from upper left and a little behind the camera. */
    float magnitude=sqrtf(1.0f+dx*dx+dz*dz);
    float diffuse=(-dx*.38f+1.0f*.87f-dz*.31f)/magnitude;
    float illumination=bound(.75f+diffuse*.22f,.67f,1.08f);
    SDL_Color surface=surface_color(map,x/course->width_m,z/course->length_m);
    SDL_Color shaded=tint(surface,illumination);
    static const SDL_Color haze={198,224,234,255};
    float fog=clamp01((distance-75.0f)/180.0f);
    fog=fog*fog*(3.0f-2.0f*fog);
    return blend(shaded,haze,fog*.78f);
}
static void fill_background(SDL_Renderer *render,int w,int h){
    enum{SLICES=28};
    SDL_Vertex vertices[(SLICES+1)*2];
    int indices[SLICES*6],n=0;
    for(int y=0;y<=SLICES;y++){
        float t=(float)y/SLICES;
        SDL_Color dark={7,34,58,255};
        SDL_Color mid={60,113,143,255};
        SDL_Color pale={197,224,235,255};
        SDL_Color c=t<.48f?blend(dark,mid,t/.48f):blend(mid,pale,(t-.48f)/.52f);
        float sy=t*h*.69f;
        vertices[y*2]=(SDL_Vertex){{0,sy},c,{0,0}};
        vertices[y*2+1]=(SDL_Vertex){{(float)w,sy},c,{0,0}};
        if(y<SLICES){
            int k=y*2;
            indices[n++]=k;indices[n++]=k+1;indices[n++]=k+2;
            indices[n++]=k+1;indices[n++]=k+3;indices[n++]=k+2;
        }
    }
    SDL_RenderGeometry(render,NULL,vertices,(SLICES+1)*2,indices,n);
    /* Far horizon snow haze; terrain fills foreground below this line. */
    SDL_SetRenderDrawColor(render,198,224,234,255);
    SDL_Rect below={0,(int)(h*.69f),w,h};
    SDL_RenderFillRect(render,&below);
}

tux_modern_terrain *tux_modern_terrain_create(void){
    tux_modern_terrain *r=(tux_modern_terrain *)calloc(1,sizeof(*r));
    if(!r)return NULL;
    r->vertices=(SDL_Vertex *)calloc(N_VERT,sizeof(SDL_Vertex));
    r->indices=(int *)malloc(N_INDEX*sizeof(int));
    if(!r->vertices||!r->indices){tux_modern_terrain_destroy(r);return NULL;}
    int n=0;
    /* One connected strip of quads. Shared vertices eliminate cracks. */
    for(int iz=0;iz<MESH_Z;iz++)for(int ix=0;ix<MESH_X;ix++){
        int a=iz*(MESH_X+1)+ix;
        int b=a+1,c=a+(MESH_X+1),d=c+1;
        r->indices[n++]=a;r->indices[n++]=b;r->indices[n++]=c;
        r->indices[n++]=b;r->indices[n++]=d;r->indices[n++]=c;
    }
    return r;
}
void tux_modern_terrain_destroy(tux_modern_terrain *r){
    if(!r)return;
    free(r->vertices);free(r->indices);free(r);
}
void tux_modern_terrain_reset(tux_modern_terrain *r,float distance,float x){
    if(!r)return;
    r->last_distance=distance;
    r->last_x=x;
    r->initialized=0;
}
void tux_modern_terrain_update(tux_modern_terrain *r,float dt,
                               float distance,float player_x,
                               const tux_original_course *course){
    if(!r||!course)return;
    float desired_x=course->width_m*(.5f+player_x*.23f);
    float desired_z=distance-11.0f;
    if(!r->initialized){
        r->camera_x=desired_x;
        r->camera_z=desired_z;
        r->initialized=1;
    }else{
        float t=1.0f-expf(-bound(dt,0,.05f)*6.5f);
        r->camera_x=mixf(r->camera_x,desired_x,t);
        r->camera_z=mixf(r->camera_z,desired_z,t);
    }
    r->last_distance=distance;
    r->last_x=player_x;
}

int tux_modern_terrain_project(const tux_modern_terrain *r,
                               const tux_original_terrain *map,
                               const tux_original_course *course,
                               int width,int height,
                               float world_x,float world_z,float height_offset,
                               float *screen_x,float *screen_y,float *pixel_per_meter){
    if(!r||!map||!course||!screen_x||!screen_y||!pixel_per_meter||
       course->width_m<=0||course->length_m<=0||height<=0||width<=0)
        return 0;
    float dz=world_z-r->camera_z;
    if(dz<2.5f||dz>215.0f)return 0;
    float pitch=bound(course->angle_deg+4.0f,18.0f,38.0f)*PI_F/180.0f;
    float s=sinf(pitch),co=cosf(pitch);
    float cam_y=ground_y(map,course,r->camera_x,r->camera_z)+4.9f;
    float dy=ground_y(map,course,world_x,world_z)+height_offset-cam_y;
    float depth=dz*co-dy*s;
    if(depth<.1f)return 0;
    float focal=height*.99f;
    float scale=focal/depth;
    *screen_x=width*.5f+(world_x-r->camera_x)*scale;
    *screen_y=height*.50f-(dy*co+dz*s)*scale;
    *pixel_per_meter=scale;
    return 1;
}

int tux_modern_terrain_draw(tux_modern_terrain *r,SDL_Renderer *render,
                            int width,int height,
                            const tux_original_terrain *map,
                            const tux_original_course *course){
    if(!r||!render||!map||!map->elevation||!map->surface||
       !course||course->width_m<=0||course->length_m<=0||
       width<=0||height<=0)return 0;

    fill_background(render,width,height);
    /* Virtual camera: behind and above the penguin, aimed down the actual
     * slope. This keeps the mountain readable while driving in landscape. */
    const float pitch=bound(course->angle_deg+4.0f,18.0f,38.0f)*PI_F/180.0f;
    const float sinp=sinf(pitch),cosp=cosf(pitch);
    const float focal=height*.99f;
    const float center_y=height*.50f;
    const float camera_height=4.9f;
    const float camera_z=r->camera_z;
    const float camera_y=ground_y(map,course,r->camera_x,camera_z)+camera_height;
    const float far_distance=215.0f;
    for(int iz=0;iz<=MESH_Z;iz++){
        /* Quadratic spacing increases near-field fidelity where players
         * notice movement and collisions, without huge vertex counts. */
        float t=(float)iz/MESH_Z;
        float dz=2.5f+(far_distance-2.5f)*t*t;
        float z=camera_z+dz;
        for(int ix=0;ix<=MESH_X;ix++){
            float u=(float)ix/MESH_X;
            float x=u*course->width_m;
            float dy=ground_y(map,course,x,z)-camera_y;
            float depth=dz*cosp-dy*sinp;
            float up=dy*cosp+dz*sinp;
            if(depth<.10f)depth=.10f;
            float scale=focal/depth;
            SDL_Vertex *v=&r->vertices[iz*(MESH_X+1)+ix];
            v->position.x=width*.5f+(x-r->camera_x)*scale;
            v->position.y=center_y-up*scale;
            v->tex_coord=(SDL_FPoint){0,0};
            v->color=light_terrain(map,course,x,z,dz);
        }
    }
    return SDL_RenderGeometry(render,NULL,r->vertices,N_VERT,r->indices,N_INDEX)==0;
}
