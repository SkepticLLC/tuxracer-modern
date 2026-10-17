/* Self-contained SGI reader validation: RLE, raw, flips, interpolation,
 * invalid/truncated files. Does not require the iOS SDK.
 */
#include "original_terrain.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
static void be16(unsigned char *p,int v){p[0]=(unsigned char)(v>>8);p[1]=(unsigned char)v;}
static void be32(unsigned char *p,unsigned int v){p[0]=(unsigned char)(v>>24);p[1]=(unsigned char)(v>>16);p[2]=(unsigned char)(v>>8);p[3]=(unsigned char)v;}
static int write_sgi(const char *path,int rle,int reverse){
    FILE *f=fopen(path,"wb");if(!f)return 0;
    unsigned char hdr[512]={0};be16(hdr,474);
    hdr[2]=(unsigned char)rle;hdr[3]=1;
    be16(hdr+4,3);be16(hdr+6,4);be16(hdr+8,3);be16(hdr+10,3);
    if(fwrite(hdr,1,sizeof(hdr),f)!=sizeof(hdr)){fclose(f);return 0;}
    unsigned char pixels[12]={1,2,3,4,11,12,13,14,21,22,23,24};
    if(reverse)for(int i=0;i<12;i++)pixels[i]=(unsigned char)(255-pixels[i]);
    if(!rle){
        for(int channel=0;channel<3;channel++)
            if(fwrite(pixels,1,12,f)!=12){fclose(f);return 0;}
    }else{
        unsigned char offsets[36*4];
        unsigned int tablebytes=3*3*8;
        unsigned int data_at=512+tablebytes;
        for(int i=0;i<9;i++){
            be32(offsets+i*4,data_at+(unsigned int)i*6);
            be32(offsets+(9+i)*4,6);
        }
        if(fwrite(offsets,1,72,f)!=72){fclose(f);return 0;}
        for(int channel=0;channel<3;channel++)for(int row=0;row<3;row++){
            unsigned char encoded[6]={132,0,0,0,0,0};
            memcpy(encoded+1,pixels+row*4,4);
            if(fwrite(encoded,1,6,f)!=6){fclose(f);return 0;}
        }
    }
    fclose(f);return 1;
}
int main(int argc,char **argv){
    const char *e="/tmp/tux_sgi_elev_test.rgb";
    const char *t="/tmp/tux_sgi_surface_test.rgb";
    tux_original_terrain map={0};
    for(int mode=0;mode<=1;mode++){
        if(!write_sgi(e,mode,0)||!write_sgi(t,mode,1))return 1;
        if(!tux_original_terrain_load(&map,e,t)){fprintf(stderr,"FAIL: mode %d decode\n",mode);return 1;}
        if(map.width!=4||map.height!=3||
           map.elevation[0]!=24||map.elevation[11]!=1||
           map.surface[0]!=(unsigned char)(255-24)||
           (int)tux_original_elevation(&map,0,0)!=24 ||
           (int)tux_original_elevation(&map,1,1)!=1) {
           fprintf(stderr,"FAIL: flipped map samples in mode %d\n",mode);return 1;
        }
        tux_original_terrain_free(&map);
    }
    /* Reject truncated image with no payload. */
    FILE *f=fopen(e,"wb");if(!f)return 1;
    fputc(1,f);fputc(218,f);fclose(f);
    if(tux_original_terrain_load(&map,e,t)){
        fprintf(stderr,"FAIL: truncated map accepted\n");return 1;
    }
    remove(e);remove(t);
    if(argc==3) {
        if(!tux_original_terrain_load(&map,argv[1],argv[2])){
            fprintf(stderr,"FAIL: could not decode real original Bunny Hill maps\n");
            return 1;
        }
        if(map.width!=90 || map.height!=240) {
            fprintf(stderr,"FAIL: original map dimensions %dx%d expected 90x240\n",
              map.width,map.height);
            return 1;
        }
        printf("PASS: ORIGINAL Bunny Hill terrain maps %dx%d, center elev %.1f, center type %d\n",
          map.width,map.height,tux_original_elevation(&map,.5f,.5f),
          tux_original_surface(&map,.5f,.5f));
        tux_original_terrain_free(&map);
    }
    puts("PASS: raw + RLE SGI RGB decoding, original coordinate flip, sampling and invalid-file guard");
    return 0;
}
