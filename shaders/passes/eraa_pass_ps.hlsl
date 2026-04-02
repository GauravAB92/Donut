/*
* Copyright (c) 2014-2024, NVIDIA CORPORATION. All rights reserved.
*
* Permission is hereby granted, free of charge, to any person obtaining a
* copy of this software and associated documentation files (the "Software"),
* to deal in the Software without restriction, including without limitation
* the rights to use, copy, modify, merge, publish, distribute, sublicense,
* and/or sell copies of the Software, and to permit persons to whom the
* Software is furnished to do so, subject to the following conditions:
*
* The above copyright notice and this permission notice shall be included in
* all copies or substantial portions of the Software.
*
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
* DEALINGS IN THE SOFTWARE.
*/

#pragma pack_matrix(row_major)

#include <donut/shaders/forward_cb.h>
#include <donut/shaders/forward_vertex.hlsli>
#include <donut/shaders/binding_helpers.hlsli>

DECLARE_CBUFFER(ForwardShadingViewConstants, g_ForwardView, FORWARD_BINDING_VIEW_CONSTANTS, FORWARD_SPACE_VIEW);


RWTexture2D<float4> u_eraaOffsets                           : register(u1);
RWTexture2D<float>  u_eraaDepthRead                         : register(u2);
RWTexture2D<float>  u_eraaDepthWrite                        : register(u3);
RWTexture2D<float>  u_eraaExtentRead                        : register(u4); 
RWTexture2D<float>  u_eraaExtentWrite                       : register(u5); 

void main_ps(
    in float4 i_position : SV_Position,
    in SceneVertex i_vtx,
    in bool i_isFrontFace : SV_IsFrontFace,
    in float3 barycentrics : SV_Barycentrics,
    VK_LOCATION_INDEX(0, 0) out float4 o_color : SV_Target0
)
{

   uint2 pixelCoord = uint2(i_position.xy);

   float prevDepth = u_eraaDepthRead[pixelCoord];

   if(i_position.z < prevDepth)
   {
       discard;
   }

   u_eraaDepthWrite[pixelCoord] = i_position.z;

   o_color = float4(1, 0, 0, 1);
}
