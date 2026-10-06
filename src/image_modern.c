/*
 * Tux Racer Modern native image decoding for Apple platforms.
 *
 * PNG and JPEG are decoded through ImageIO/CoreGraphics into a stable RGBA8
 * representation. Legacy SGI .rgb files continue through ImageLoad().
 */
#include "tuxracer.h"
#include "image.h"
#include <stdlib.h>
#include <string.h>
#include <limits.h>

#ifdef __APPLE__
#include <CoreFoundation/CoreFoundation.h>
#include <CoreGraphics/CoreGraphics.h>
#include <ImageIO/ImageIO.h>
#endif

static int has_suffix_ci( const char *s, const char *suffix )
{
    size_t a,b,i;
    if(!s||!suffix)return 0;
    a=strlen(s);b=strlen(suffix);if(b>a)return 0;
    s+=a-b;
    for(i=0;i<b;i++){
        char x=s[i],y=suffix[i];
        if(x>='A'&&x<='Z')x=(char)(x-'A'+'a');
        if(y>='A'&&y<='Z')y=(char)(y-'A'+'a');
        if(x!=y)return 0;
    }
    return 1;
}

static tux_image_t *load_legacy_sgi( const char *filename )
{
    IMAGE *legacy;
    tux_image_t *out;
    size_t bytes;
    legacy=ImageLoad((char *)filename);
    if(!legacy)return NULL;
    if(legacy->sizeX==0||legacy->sizeY==0||
       (legacy->sizeZ!=3&&legacy->sizeZ!=4)){
        free(legacy->data);free(legacy);return NULL;
    }
    if((size_t)legacy->sizeX>SIZE_MAX/(size_t)legacy->sizeY/(size_t)legacy->sizeZ){
        free(legacy->data);free(legacy);return NULL;
    }
    bytes=(size_t)legacy->sizeX*legacy->sizeY*legacy->sizeZ;
    out=(tux_image_t *)calloc(1,sizeof(*out));
    if(!out){free(legacy->data);free(legacy);return NULL;}
    out->pixels=(unsigned char *)malloc(bytes);
    if(!out->pixels){free(out);free(legacy->data);free(legacy);return NULL;}
    /*
     * Legacy IMAGE rows may contain 4-byte alignment padding. Copy row by row
     * into the tightly packed modern representation.
     */
    {
        size_t src_stride=((size_t)legacy->sizeX*legacy->sizeZ+3u)&~3u;
        size_t dst_stride=(size_t)legacy->sizeX*legacy->sizeZ;
        int y;
        for(y=0;y<legacy->sizeY;y++)
            memcpy(out->pixels+(size_t)y*dst_stride,
                   legacy->data+(size_t)y*src_stride,dst_stride);
    }
    out->width=legacy->sizeX;out->height=legacy->sizeY;
    out->channels=legacy->sizeZ;
    out->format=legacy->sizeZ==4?TUX_IMAGE_FORMAT_RGBA8:TUX_IMAGE_FORMAT_RGB8;
    free(legacy->data);free(legacy);
    return out;
}

#ifdef __APPLE__
static tux_image_t *load_imageio( const char *filename )
{
    CFURLRef url=NULL;
    CGImageSourceRef source=NULL;
    CGImageRef image=NULL;
    CGColorSpaceRef cs=NULL;
    CGContextRef ctx=NULL;
    tux_image_t *out=NULL;
    size_t w,h,bytes;

    url=CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault,
            (const UInt8 *)filename,(CFIndex)strlen(filename),false);
    if(!url)goto done;
    source=CGImageSourceCreateWithURL(url,NULL);if(!source)goto done;
    image=CGImageSourceCreateImageAtIndex(source,0,NULL);if(!image)goto done;
    w=CGImageGetWidth(image);h=CGImageGetHeight(image);
    if(w==0||h==0||w>16384||h>16384||w>SIZE_MAX/h/4u)goto done;
    bytes=w*h*4u;
    out=(tux_image_t *)calloc(1,sizeof(*out));if(!out)goto done;
    out->pixels=(unsigned char *)calloc(1,bytes);
    if(!out->pixels){free(out);out=NULL;goto done;}
    cs=CGColorSpaceCreateDeviceRGB();if(!cs)goto fail;
    ctx=CGBitmapContextCreate(out->pixels,w,h,8,w*4u,cs,
            kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    if(!ctx)goto fail;
    /* Match the historical texture orientation expected by the renderer. */
    CGContextTranslateCTM(ctx,0,(CGFloat)h);
    CGContextScaleCTM(ctx,1,-1);
    CGContextDrawImage(ctx,CGRectMake(0,0,(CGFloat)w,(CGFloat)h),image);
    out->width=(int)w;out->height=(int)h;out->channels=4;
    out->format=TUX_IMAGE_FORMAT_RGBA8;
    goto done;
fail:
    free(out->pixels);free(out);out=NULL;
done:
    if(ctx)CGContextRelease(ctx);if(cs)CGColorSpaceRelease(cs);
    if(image)CGImageRelease(image);if(source)CFRelease(source);if(url)CFRelease(url);
    return out;
}
#endif

tux_image_t *tux_image_load( const char *filename )
{
    if(!filename||!*filename)return NULL;
    if(has_suffix_ci(filename,".rgb")||has_suffix_ci(filename,".sgi"))
        return load_legacy_sgi(filename);
#ifdef __APPLE__
    if(has_suffix_ci(filename,".png")||has_suffix_ci(filename,".jpg")||
       has_suffix_ci(filename,".jpeg"))
        return load_imageio(filename);
#endif
    return NULL;
}

void tux_image_free( tux_image_t *image )
{
    if(!image)return;
    free(image->pixels);
    free(image);
}
