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

#define USE_GS_ADJACENCY_DATA 1
#define DEBUG_OFFSETS 0
#define DETECT_IMPLICIT_EDGES 0

#pragma pack_matrix(row_major)

#include <donut/shaders/forward_cb.h>
#include <donut/shaders/forward_vertex.hlsli>
#include <donut/shaders/binding_helpers.hlsli>
#include <donut/shaders/eraa_shared_data.hlsli>
#include <donut/shaders/eraa_core_routines.hlsli>
#include <donut/shaders/eraa_silhouette_edge_routines.hlsli>
#include <donut/shaders/eraa_extent_data_routines.hlsli>
#include <donut/shaders/eraa_intersection_edge_routines.hlsli>


DECLARE_CBUFFER(ForwardShadingViewConstants, g_ForwardView, FORWARD_BINDING_VIEW_CONSTANTS, FORWARD_SPACE_VIEW);

void detectExplicitEdges(
in float4 posScreen,
in GSOutputERAA input,
in bool isConservativelyGenerated,
in float3 barycentricCoords,
out EdgeType edgeType,
out float4 outputColor
)
{ 
    edgeType = EdgeType::Edge_None;
    outputColor = float4(0.0, 0.0, 0.0, 0.0);
    float4 edgeCoords[3] = {float4(0,0,0,0), float4(0,0,0,0), float4(0,0,0,0)};
    float3 xiyiA = float3(0,0,0);
    float3 viewVector =  -normalize(input.posVS.xyz);  
    float  weight = 1.0f;
    bool backFace;

	for(int edgeIdx = 0; edgeIdx < 3; ++edgeIdx)
	{
        float4 LRUDOffsets      = float4(0.0, 0.0, 0.0, 0.0);
		float2 edgeVertices[2]  = {input.posScreenSpace[edgeIdx], input.posScreenSpace[(edgeIdx + 1) % 3]};
        float  confidence       = 1.0f;
        float3 localxiyiA        = float3(0.0, 0.0, 0.0);
        float3 computedNormal     = float3(0.0, 0.0, 0.0);
    
    	if(intersectEdgeWithPixel(posScreen, input.posScreenSpace, edgeVertices, barycentricCoords,
         isConservativelyGenerated, true, LRUDOffsets, localxiyiA))
        { 
             #if USE_GS_ADJACENCY_DATA
                if(input.isDiscontinuityEdge[edgeIdx] == 1.0f)
                {  
                    outputColor     = max(outputColor,  LRUDOffsets);
                    edgeType        = EdgeType::Edge_Discontinuity;
                }
                else if(detectSilhouetteEdgeVS_GSADJ(normalize(input.surfaceNormalVS), normalize(input.adjSurfaceNormalsVS[edgeIdx]), viewVector, weight))
                {  
                    outputColor     = max(outputColor, LRUDOffsets);
                    edgeType        = EdgeType::Edge_Silhouette;
                }
             #else
                if(input.isDiscontinuityEdge[edgeIdx])
                {
                    outputColor     = max(outputColor,  LRUDOffsets);
                    edgeType        = EdgeType::Edge_Discontinuity;
                }
                else if(detectSilhouetteEdgeVSConfidenceTest(edgeIdx, input.normalVS, input.posViewSpace, input.surfaceNormalVS, viewVector, computedNormal, backFace, confidence))
                {
                    outputColor     = max(outputColor,  LRUDOffsets * confidence);
                    edgeType        = EdgeType::Edge_Silhouette;
                }
             #endif

            edgeCoords[edgeIdx] = float4(edgeVertices[0].xy, edgeVertices[1].xy);
            xiyiA = localxiyiA;
		}
	}
}


bool detectImplicitEdges(
    float2 pixelCenter,
    float currDepths          [9],
    float prevDepths          [9],
    float depthDiffs          [9],
    float prevExtents         [9],
    bool  pixelInTriangle     [9],
    float extent,
    float extent_prev,
    out float4 LRUDOffsets)
{
    LRUDOffsets = float4(0.0, 0.0, 0.0, 0.0);
    float eprime = 0.0f;
    float3 xiyiA = float3(0.0f, 0.0f, 0.0f);
    float4 edgeSegment = float4(0.0f, 0.0f, 0.0f, 0.0f);

    return buildIntersectionEdge(
        pixelCenter,
        currDepths,
        prevDepths,
        depthDiffs,
        prevExtents,
        pixelInTriangle,
        extent,
        extent_prev,
        LRUDOffsets,
        xiyiA,
        eprime,
        edgeSegment
        );
}


void main_ps(
    in float4 posScreen     : SV_Position,
    in GSOutputERAA Input,
    in bool i_isFrontFace   : SV_IsFrontFace,
    in float3 barycentrics  : SV_Barycentrics,
    VK_LOCATION_INDEX(0, 0) out float4 o_color : SV_Target0
)
{

    bool   isConservativelyGenerated    = (barycentrics.x < 0.0 || barycentrics.y < 0.0 || barycentrics.z < 0.0);
    bool   depthTestPassed              = true;
    int2   pixelCoord                   = int2(posScreen.xy);
    float  depthCurr                    = posScreen.z;
    float  extentCurr                   = posScreen.z;
    float  extentMax                    = posScreen.z;

    float4 LRUDOffsetsFB                = u_eraaReadOffsets[pixelCoord];
    float  depthPrev                    = u_eraaDepthRead[pixelCoord];
    float  extentPrev                   = u_eraaExtentRead[pixelCoord];

    float currDepths        [9]         = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0, 0.0, 0.0, 0.0 };
    float prevDepths        [9]         = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0, 0.0, 0.0, 0.0 };
    float depthDiffs        [9]         = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0, 0.0, 0.0, 0.0 };
    float currExtents       [9]         = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0, 0.0, 0.0, 0.0 };
    float extentFramebuffer [9]         = { 0.0f, 0.0f, 0.0f, 0.0f, 0.0f, 0.0, 0.0, 0.0, 0.0 };
    bool  pixelInTriangle   [9]         = { false, false, false, false, false, false, false, false , false };

    EdgeType edgeType = EdgeType::Edge_None;
    float4 outputColor = float4(0, 0, 0, 0);

    evaluateExtentedDepth(depthCurr, extentCurr, extentMax);
    //extentCurr = intersectFitSphere2(Input.posVS, Input.posViewSpace, Input.normalVS, g_ForwardView.view.matViewToClipNoOffset);
    currExtents[4] = extentCurr; //center pixel extent
    buildDepthDeltas(posScreen.xyz, currDepths, prevDepths, depthDiffs, currExtents, extentFramebuffer);

    detectExplicitEdges(posScreen, Input, isConservativelyGenerated, barycentrics, edgeType, outputColor);
    inclusionTest(Input.posScreenSpace, posScreen.xy, pixelInTriangle);
 
#if DETECT_IMPLICIT_EDGES
    float4 outputImplicit = float4(0.0, 0.0, 0.0, 0.0);
    if(detectImplicitEdges(posScreen.xy,currDepths, prevDepths, depthDiffs, extentFramebuffer, pixelInTriangle, extentCurr, extentPrev, outputImplicit))
    {
        edgeType    = EdgeType::Edge_Intersection;
        outputColor = outputImplicit;
    }
#endif

    if((depthCurr < depthPrev))
    {
        depthTestPassed = false;
        if(edgeType != EdgeType::Edge_Intersection)
        {
            discard;
        }
    }

   pixelInTriangle[4] =  !isConservativelyGenerated; //fill in center pixel

#if DEBUG_OFFSETS
    if(edgeType == EdgeType::Edge_Silhouette)
    {
        outputColor = float4(1.0, 1.0, 1.0, 1.0);
    }
    else if(edgeType == EdgeType::Edge_Discontinuity)
    {
        outputColor = float4(1.0, 1.0, 0.0, 1.0);
    }
    else if(edgeType == EdgeType::Edge_Intersection)
    {             
        outputColor = float4(0.0, 1.0, 0.0, 1.0);
    }
#endif

    float threshold = 0.1f;
    bool coplanar = false;
    if( ((abs(extentCurr - depthCurr)) < threshold))
    {
      //  extentCurr = depthCurr + 0.1f;
    }
   
    //If edge is not intersection edge and depth test failed then discard pixel to avoid writing incorrect depth and extent values to framebuffer
    float4 currentOutputColor               = max(outputColor, LRUDOffsetsFB);
    bool   occluding                        =  ( (extentCurr - 1e-4f) > extentPrev)  ; //center pixel depth vs extent from previous frame 
    
        if(occluding && (edgeType != EdgeType::Edge_None) )
        {
            if(currentOutputColor.r != 0.0f)        //Left offset added
            {
                //remove previous right offset from left neighbor
                int2 neighborPixelCoord                     = pixelCoord + pixelIdOffsets[3]; //left neighbor
                u_eraaWriteOffsets[neighborPixelCoord].g    = 0.0f;
                if(pixelInTriangle[4])
                {
                    u_eraaExtentWrite[pixelCoord]           = extentCurr;
                }
                else
                {
                    u_eraaExtentWrite[neighborPixelCoord]   = extentCurr;
                }
            }

            if(currentOutputColor.g != 0.0f)        //Right offset added
            {
                //remove previous left offset from right neighbor
                int2 neighborPixelCoord                     = pixelCoord + pixelIdOffsets[5]; //right neighbor
                u_eraaWriteOffsets[neighborPixelCoord].r    = 0.0f;
                if(pixelInTriangle[4])
                {
                    u_eraaExtentWrite[pixelCoord] = extentCurr;
                }
                else
                {
                    u_eraaExtentWrite[neighborPixelCoord] = extentCurr;
                }
            }

            if(currentOutputColor.b != 0.0f)        //Up offset added
            {
                //remove previous down offset from up neighbor
                int2 neighborPixelCoord                     = pixelCoord + pixelIdOffsets[1]; //up neighbor
                u_eraaWriteOffsets[neighborPixelCoord].a    = 0.0f;
                if(pixelInTriangle[4])
                {
                    u_eraaExtentWrite[pixelCoord] = extentCurr;
                }
                else
                {
                    u_eraaExtentWrite[neighborPixelCoord] = extentCurr;
                }
            }
            
            if(currentOutputColor.a != 0.0f)        //Down offset added
            {
                //remove previous up offset from down neighbor
                int2 neighborPixelCoord                     = pixelCoord + pixelIdOffsets[7]; //down neighbor
                u_eraaWriteOffsets[neighborPixelCoord].b    = 0.0f;
                if(pixelInTriangle[4])
                {
                    u_eraaExtentWrite[pixelCoord] = extentCurr;
                }
                else
                {
                    u_eraaExtentWrite[neighborPixelCoord] = extentCurr;
                }
            }
        }
        else if(occluding && (edgeType == EdgeType::Edge_None) && pixelInTriangle[4])
        {
            currentOutputColor = float4(0.0f, 0.0f, 0.0f, 0.0f); //not occluding so no offsets
        }

    // Set depth and extent outputs
    // If intersection edge found then don't update depth and extent
    if(depthTestPassed && (!isConservativelyGenerated))
    {
        u_eraaDepthWrite[pixelCoord]                    =  depthCurr;
    }

    
    u_eraaWriteOffsets[pixelCoord]                      =  currentOutputColor;
   // o_color = outputColor;
}
