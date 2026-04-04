/*
* Copyright (c) 2014-2021, NVIDIA CORPORATION. All rights reserved.
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

#ifndef FORWARD_VERTEX_HLSLI
#define FORWARD_VERTEX_HLSLI

struct SceneVertex
{
    float3 pos : POS;
    float3 prevPos : PREV_POS;
    float2 texCoord : TEXCOORD;
    float3 normal : NORMAL;
    float4 tangent : TANGENT;
};

//For ERAA
struct SceneVertexData
{
	float3 posWorld : POS_WORLD;
	float3 posView  : POS_VIEW;
    float2 texCoord : TEXCOORD;
    float3 normal : NORMAL;
    float3 normalView: NORMAL4;
    float4 tangent : TANGENT;
};

struct GSOutputERAA
{
    float3 posVS                                    : POS_VIEW;
    float3 normal                                   : NORMAL;
    float3 normalView                               : NORMAL4;
    float3 normalNDC                                : NORMAL8;
    nointerpolation float3 normalVS[3]              : NORMAL12;
    nointerpolation float3 normalNDCoords[3]        : NORMAL24;
    nointerpolation float2 posScreenSpace[3]        : TEXCOORD0;
    nointerpolation float3 posViewSpace[3]          : COLOR0;
    nointerpolation float3 surfaceNormalNDC         : COLOR10;
    nointerpolation float3 adjSurfaceNormalsNDC[3]  : COLOR14;
    nointerpolation float3 surfaceNormalVS          : COLOR24;
    nointerpolation float3 adjSurfaceNormalsVS[3]   : COLOR28;
    nointerpolation float3 isDiscontinuityEdge      : POSITION15;
};
#endif
