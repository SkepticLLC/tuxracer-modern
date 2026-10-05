#import <AppKit/AppKit.h>
#import <OpenGL/gl.h>
#include "modern_text.h"

static NSMutableDictionary *gModernTextCache;

static NSString *cache_key(const char *text,float size,int weight,float r,float g,float b,float a){
    return [NSString stringWithFormat:@"%s|%.1f|%d|%.3f|%.3f|%.3f|%.3f",text,size,weight,r,g,b,a];
}
static NSDictionary *make_text(const char *utf8,float size,int weight,float r,float g,float b,float a){
    @autoreleasepool {
        NSString *str=[NSString stringWithUTF8String:utf8?utf8:""];
        NSFontWeight fw=weight?NSFontWeightSemibold:NSFontWeightRegular;
        NSFont *font=[NSFont systemFontOfSize:size weight:fw];
        NSDictionary *attrs=@{NSFontAttributeName:font,
          NSForegroundColorAttributeName:[NSColor colorWithCalibratedRed:r green:g blue:b alpha:a]};
        NSSize sz=[str sizeWithAttributes:attrs];
        int w=(int)ceil(sz.width)+8,h=(int)ceil(sz.height)+8;
        if(w<1)w=1;if(h<1)h=1;
        unsigned char *pixels=(unsigned char*)calloc((size_t)w*h*4,1);
        CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
        CGContextRef ctx=CGBitmapContextCreate(pixels,w,h,8,w*4,cs,
            kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(cs);
        if(!ctx){free(pixels);return nil;}
        NSGraphicsContext *gc=[NSGraphicsContext graphicsContextWithCGContext:ctx flipped:NO];
        [NSGraphicsContext saveGraphicsState];[NSGraphicsContext setCurrentContext:gc];
        [str drawAtPoint:NSMakePoint(4,4) withAttributes:attrs];
        [NSGraphicsContext restoreGraphicsState];
        CGContextRelease(ctx);
        GLuint tex=0;glGenTextures(1,&tex);glBindTexture(GL_TEXTURE_2D,tex);
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_S,GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_WRAP_T,GL_CLAMP_TO_EDGE);
        glPixelStorei(GL_UNPACK_ALIGNMENT,1);
        glTexImage2D(GL_TEXTURE_2D,0,GL_RGBA,w,h,0,GL_RGBA,GL_UNSIGNED_BYTE,pixels);
        free(pixels);
        return @{@"tex":@(tex),@"w":@(w),@"h":@(h)};
    }
}
void modern_text_draw(const char *text,float x,float y,float size,float r,float g,float b,float a,int weight){
    @autoreleasepool {
        if(!gModernTextCache)gModernTextCache=[NSMutableDictionary dictionary];
        NSString *key=cache_key(text,size,weight,r,g,b,a);
        NSDictionary *item=gModernTextCache[key];
        if(!item){item=make_text(text,size,weight,r,g,b,a);if(item)gModernTextCache[key]=item;}
        if(!item)return;
        GLuint tex=[item[@"tex"] unsignedIntValue];float w=[item[@"w"] floatValue],h=[item[@"h"] floatValue];
        glPushAttrib(GL_ENABLE_BIT|GL_COLOR_BUFFER_BIT|GL_TEXTURE_BIT|GL_CURRENT_BIT);
        glEnable(GL_TEXTURE_2D);glEnable(GL_BLEND);glBlendFunc(GL_SRC_ALPHA,GL_ONE_MINUS_SRC_ALPHA);
        glBindTexture(GL_TEXTURE_2D,tex);glColor4f(1,1,1,1);
        /*
         * CoreGraphics bitmap rows and OpenGL texture coordinates use
         * opposite vertical conventions. Flip V at presentation time so the
         * cached text texture remains in its native raster orientation.
         */
        glBegin(GL_QUADS);
        glTexCoord2f(0,1);glVertex2f(x,y);
        glTexCoord2f(1,1);glVertex2f(x+w,y);
        glTexCoord2f(1,0);glVertex2f(x+w,y+h);
        glTexCoord2f(0,0);glVertex2f(x,y+h);
        glEnd();
        glPopAttrib();
    }
}
void modern_text_clear_cache(void){
    @autoreleasepool {
        for(NSDictionary *item in [gModernTextCache allValues]){
            GLuint t=[item[@"tex"] unsignedIntValue];if(t)glDeleteTextures(1,&t);
        }
        [gModernTextCache removeAllObjects];
    }
}
