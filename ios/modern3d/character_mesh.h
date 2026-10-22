/* Segmented prototype character geometry: parts may later be swapped
 * for imported rigged mesh parts without changing the renderer.
 */
#ifndef TUX_CHARACTER_MESH_H
#define TUX_CHARACTER_MESH_H
#import <simd/simd.h>
typedef struct { vector_float3 position; vector_float3 normal; vector_float4 color; } Vertex;
typedef enum {TUX_BODY=0,TUX_LEFT_WING,TUX_RIGHT_WING,TUX_SCARF,TUX_HAT,TUX_PART_COUNT} TuxPart;
Vertex *tux_make_part(TuxPart part,unsigned *count);
#endif
