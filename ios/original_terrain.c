/*
 * Safe SGI .rgb reader: supports 8-bit planar uncompressed and RLE images.
 * Original game data is not re-encoded. Only channel zero is needed for
 * elevation and terrain; source image rows are flipped as in course_load.c.
 * SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "original_terrain.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>

static unsigned short be16(const unsigned char *p)
{ return (unsigned short)((p[0]<<8)|p[1]); }
static unsigned int be32(const unsigned char *p)
{ return ((unsigned int)p[0]<<24)|((unsigned int)p[1]<<16)|((unsigned int)p[2]<<8)|p[3]; }

static int decode_row(const unsigned char *src,size_t size,unsigned char *dst,int width) {
    size_t i=0;
    int out=0,done=0;
    while(i<size){
        unsigned int token=src[i++];
        int count=(int)(token&127);
        if(count==0){done=1;break;}
        if(count>width-out)return 0;
        if(token&128){
            if((size_t)count>size-i)return 0;
            memcpy(dst+out,src+i,(size_t)count);
            i+=(size_t)count;
        }else{
            if(i>=size)return 0;
            memset(dst+out,src[i++],(size_t)count);
        }
        out+=count;
    }
    return done&&out==width;
}
static int read_map(const char *path,unsigned char **out,int *width,int *height){
    FILE *f=NULL;
    unsigned char *file=NULL,*pixels=NULL;
    int ok=0,w=0,h=0;
    long file_size;
    if(!path||!out||!width||!height)return 0;
    f=fopen(path,"rb");
    if(!f)return 0;
    if(fseek(f,0,SEEK_END)!=0)goto end;
    file_size=ftell(f);
    if(file_size<512||file_size>64*1024*1024)goto end;
    if(fseek(f,0,SEEK_SET)!=0)goto end;
    file=(unsigned char *)malloc((size_t)file_size);
    if(!file||fread(file,1,(size_t)file_size,f)!=(size_t)file_size)goto end;
    if(be16(file)!=474||file[2]>1||file[3]!=1)goto end;
    w=be16(file+6);h=be16(file+8);
    int channels=be16(file+10);
    if(w<2||h<2||w>4096||h>4096||channels<1||channels>4)goto end;
    if((size_t)w*(size_t)h>16000000u)goto end;
    pixels=(unsigned char *)malloc((size_t)w*(size_t)h);
    if(!pixels)goto end;
    if(file[2]==0){
        /* SGI channel-major, bottom-up. Match the original game image flip. */
        size_t needed=512u+(size_t)w*(size_t)h*(size_t)channels;
        if(needed>(size_t)file_size)goto end;
        for(int y=0;y<h;y++)for(int x=0;x<w;x++)
            pixels[(h-1-y)*w+(w-1-x)]=file[512+(size_t)y*w+x];
    }else{
        size_t count=(size_t)h*(size_t)channels;
        size_t table_end=512+count*8;
        if(table_end>(size_t)file_size)goto end;
        unsigned char *row=(unsigned char *)malloc((size_t)w);
        if(!row)goto end;
        int valid=1;
        for(int y=0;y<h;y++){
            size_t index=(size_t)y;
            size_t start=be32(file+512+index*4);
            size_t size=be32(file+512+count*4+index*4);
            if(start<table_end||start>(size_t)file_size||
               size>(size_t)file_size-start||
               !decode_row(file+start,size,row,w)){valid=0;break;}
            for(int x=0;x<w;x++)pixels[(h-1-y)*w+(w-1-x)]=row[x];
        }
        free(row);
        if(!valid)goto end;
    }
    *out=pixels;pixels=NULL;*width=w;*height=h;ok=1;
end:
    free(file);free(pixels);
    if(f)fclose(f);
    return ok;
}
int tux_original_terrain_load(tux_original_terrain *out,
                             const char *elevation_path,
                             const char *terrain_path){
    int w=0,h=0,tw=0,th=0;
    unsigned char *elev=NULL,*surf=NULL;
    if(!out)return 0;
    if(!read_map(elevation_path,&elev,&w,&h)||
       !read_map(terrain_path,&surf,&tw,&th)||
       w!=tw||h!=th){
        free(elev);free(surf);return 0;
    }
    tux_original_terrain_free(out);
    out->width=w;out->height=h;out->elevation=elev;out->surface=surf;
    return 1;
}
void tux_original_terrain_free(tux_original_terrain *map){
    if(!map)return;
    free(map->elevation);free(map->surface);
    memset(map,0,sizeof(*map));
}
static float bound(float x){return x<0?0:x>1?1:x;}
float tux_original_elevation(const tux_original_terrain *map,float x,float z){
    if(!map||!map->elevation||map->width<2||map->height<2)return 0;
    float fx=bound(x)*(map->width-1),fy=bound(z)*(map->height-1);
    int x0=(int)fx,y0=(int)fy;
    int x1=x0+1<map->width?x0+1:x0;
    int y1=y0+1<map->height?y0+1:y0;
    float tx=fx-x0,ty=fy-y0;
    const uint8_t *p=map->elevation;
    float a=p[y0*map->width+x0]*(1-tx)+p[y0*map->width+x1]*tx;
    float b=p[y1*map->width+x0]*(1-tx)+p[y1*map->width+x1]*tx;
    return a*(1-ty)+b*ty;
}
int tux_original_surface(const tux_original_terrain *map,float x,float z){
    if(!map||!map->surface||map->width<2||map->height<2)return 255;
    int ix=(int)(bound(x)*(map->width-1)+.5f);
    int iy=(int)(bound(z)*(map->height-1)+.5f);
    return map->surface[iy*map->width+ix];
}
