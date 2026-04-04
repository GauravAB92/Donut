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
#include <donut/shaders/bindless.h>
#include <donut/shaders/packing.hlsli>

DECLARE_CBUFFER(ForwardShadingViewConstants, g_ForwardView, FORWARD_BINDING_VIEW_CONSTANTS, FORWARD_SPACE_VIEW);

StructuredBuffer<InstanceData> t_Instances  : REGISTER_SRV(FORWARD_BINDING_INSTANCE_BUFFER, FORWARD_SPACE_INPUT);
ByteAddressBuffer t_Vertices                : REGISTER_SRV(FORWARD_BINDING_VERTEX_BUFFER, FORWARD_SPACE_INPUT);
DECLARE_PUSH_CONSTANTS(ForwardPushConstants, g_Push, FORWARD_BINDING_PUSH_CONSTANTS, FORWARD_SPACE_INPUT);


// Version of the vertex shader that uses buffer loads to read vertex attributes and transforms.
void main_vs(
    in uint i_vertex : SV_VertexID,
	in uint i_instance : SV_InstanceID,
    out float4 o_position : SV_Position,
    out SceneVertexData o_vtx
)
{
    i_instance 	+= g_Push.startInstanceLocation;
    i_vertex 	+= g_Push.startVertexLocation;

    const InstanceData instance = t_Instances[i_instance];

    float3 pos 			= asfloat(t_Vertices.Load3(g_Push.positionOffset + i_vertex * c_SizeOfPosition));
    float2 texCoord 	= asfloat(t_Vertices.Load2(g_Push.texCoordOffset + i_vertex * c_SizeOfTexcoord));
    uint packedNormal 	= t_Vertices.Load(g_Push.normalOffset + i_vertex * c_SizeOfNormal);
    uint packedTangent 	= t_Vertices.Load(g_Push.tangentOffset + i_vertex * c_SizeOfNormal);
    float3 normal 		= Unpack_RGB8_SNORM(packedNormal);
    float4 tangent 		= Unpack_RGBA8_SNORM(packedTangent);

    float3 worldPos 	= mul(instance.transform, float4(pos, 1.0)).xyz;

	o_vtx.posWorld      = worldPos;
	o_vtx.posView       = mul(float4(worldPos,1.0), g_ForwardView.view.matWorldToView).xyz;
	o_vtx.texCoord      = texCoord;
	o_vtx.normal        = mul(instance.transform, float4(normal, 0)).xyz;
	o_vtx.normalView    = mul(float4(o_vtx.normal, 0),g_ForwardView.view.matWorldToView).xyz;
	o_vtx.tangent.xyz   = mul(instance.transform, float4(tangent.xyz, 0)).xyz;
	o_vtx.tangent.w     = tangent.w;

    o_position 			= mul(float4(worldPos,1.0), g_ForwardView.view.matWorldToClip);
}



