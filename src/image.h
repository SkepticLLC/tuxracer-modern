/* 
 * Tux Racer 
 * Copyright (C) 1999-2001 Jasmin F. Patry
 * 
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#ifdef __cplusplus
extern "C"
{
#endif

/* This code taken from Mesa 3Dfx demos by David Bucciarelli (tech.hmw@plus.it)
 */

#ifndef __IMAGE_H__
#define __IMAGE_H__

typedef struct
{
    unsigned short imagic;
    unsigned short type;
    unsigned short dim;
    unsigned short sizeX, sizeY, sizeZ;
    char name[128];
    unsigned char *data;
} IMAGE;

IMAGE *ImageLoad(char *);

/* Modern format-neutral image representation. Pixels are tightly packed. */
typedef enum {
    TUX_IMAGE_FORMAT_RGB8 = 3,
    TUX_IMAGE_FORMAT_RGBA8 = 4
} tux_image_format_t;

typedef struct {
    int width;
    int height;
    int channels;
    tux_image_format_t format;
    unsigned char *pixels;
} tux_image_t;

/*
 * Loads PNG/JPEG through the native platform decoder where available and
 * falls back to the preserved SGI loader for legacy .rgb assets.
 */
tux_image_t *tux_image_load( const char *filename );
void tux_image_free( tux_image_t *image );

#endif /* !__IMAGE_H__! */

#ifdef __cplusplus
} /* extern "C" */
#endif
