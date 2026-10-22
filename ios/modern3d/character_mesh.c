/* Segmented high-density procedural character mesh for the new iOS game.
 * Temporary geometry; the TuxPart interface is the import/rigging seam.
 */
#include "character_mesh.h"
#include <stdlib.h>
#include <math.h>
static void vertex(Vertex *v,unsigned *count,unsigned max,
                   vector_float3 p,vector_float3 n,vector_float4 color){
 if(*count<max)v[(*count)++]=(Vertex){p,n,color};
}
static void ellipsoid(Vertex *v,unsigned *count,unsigned max,
                      vector_float3 center,vector_float3 radii,vector_float4 color){
 const int ring=18,segments=24;
 for(int j=0;j<ring;j++)for(int i=0;i<segments;i++){
   float p[6]={(float)j/ring,(float)(j+1)/ring,(float)j/ring,
               (float)j/ring,(float)(j+1)/ring,(float)(j+1)/ring};
   float t[6]={(float)i/segments,(float)i/segments,(float)(i+1)/segments,
               (float)(i+1)/segments,(float)i/segments,(float)(i+1)/segments};
   for(int k=0;k<6;k++){
      float a=p[k]*3.14159265f,b=t[k]*6.2831853f;
      vector_float3 direction={sinf(a)*cosf(b),cosf(a),sinf(a)*sinf(b)};
      vector_float3 position=center+direction*radii;
      vector_float3 n=simd_normalize((vector_float3){
          direction.x/radii.x,direction.y/radii.y,direction.z/radii.z});
      vertex(v,count,max,position,n,color);
   }
 }
}
Vertex *tux_make_part(TuxPart part,unsigned *count){
 const unsigned max=16000;
 Vertex *v=(Vertex *)calloc(max,sizeof(Vertex));
 if(!v)return NULL;
 *count=0;
 vector_float4 black={.052f,.105f,.15f,1};
 vector_float4 white={.94f,.967f,.96f,1};
 vector_float4 orange={1.0f,.58f,.075f,1};
 vector_float4 blue={.11f,.57f,.86f,1};
 vector_float4 red={.93f,.23f,.20f,1};
 switch(part){
 case TUX_BODY:
   ellipsoid(v,count,max,(vector_float3){0,1.08f,0},
             (vector_float3){.51f,.86f,.39f},black);
   ellipsoid(v,count,max,(vector_float3){0,1.02f,-.31f},
             (vector_float3){.40f,.67f,.16f},white);
   ellipsoid(v,count,max,(vector_float3){0,1.92f,0},
             (vector_float3){.385f,.42f,.35f},black);
   ellipsoid(v,count,max,(vector_float3){0,1.80f,-.37f},
             (vector_float3){.225f,.105f,.16f},orange);
   ellipsoid(v,count,max,(vector_float3){-.17f,2.03f,-.31f},
             (vector_float3){.075f,.095f,.05f},white);
   ellipsoid(v,count,max,(vector_float3){.17f,2.03f,-.31f},
             (vector_float3){.075f,.095f,.05f},white);
   ellipsoid(v,count,max,(vector_float3){-.17f,2.025f,-.353f},
             (vector_float3){.033f,.052f,.019f},black);
   ellipsoid(v,count,max,(vector_float3){.17f,2.025f,-.353f},
             (vector_float3){.033f,.052f,.019f},black);
   ellipsoid(v,count,max,(vector_float3){-.245f,.19f,-.20f},
             (vector_float3){.23f,.12f,.35f},orange);
   ellipsoid(v,count,max,(vector_float3){.245f,.19f,-.20f},
             (vector_float3){.23f,.12f,.35f},orange);
   break;
 case TUX_LEFT_WING:
 case TUX_RIGHT_WING: {
   float sign=part==TUX_LEFT_WING?-1.0f:1.0f;
   ellipsoid(v,count,max,(vector_float3){sign*.51f,1.18f,0},
             (vector_float3){.20f,.55f,.20f},black);
   break;
 }
 case TUX_SCARF:
   ellipsoid(v,count,max,(vector_float3){0,1.61f,-.015f},
             (vector_float3){.45f,.11f,.34f},blue);
   ellipsoid(v,count,max,(vector_float3){.35f,1.36f,.10f},
             (vector_float3){.115f,.31f,.10f},blue);
   break;
 case TUX_HAT:
   ellipsoid(v,count,max,(vector_float3){0,2.275f,0},
             (vector_float3){.39f,.19f,.32f},red);
   ellipsoid(v,count,max,(vector_float3){0,2.44f,0},
             (vector_float3){.21f,.12f,.21f},white);
   break;
 default: break;
 }
 return v;
}
