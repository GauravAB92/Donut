#ifndef USE_GS_ADJACENCY_DATA
#define USE_GS_ADJACENCY_DATA 0
#endif

#include <donut/shaders/forward_cb.h>
#include <donut/shaders/forward_vertex.hlsli>
#include <donut/shaders/binding_helpers.hlsli>


DECLARE_CBUFFER(ForwardShadingViewConstants, g_ForwardView, FORWARD_BINDING_VIEW_CONSTANTS, FORWARD_SPACE_VIEW);


struct VSOutput
{
    float4 posClip : SV_Position;
	SceneVertexData vtx;
};


struct GSOutput
{ 
    float4 posClip    : SV_Position;
    GSOutputERAA gsOut;
};

float3 getScreenSpacePos(float4 posClip, float2 viewportSize)
{
    // Convert to screen space
    float3 screenPos = posClip.xyz / posClip.w;
    screenPos = screenPos * 0.5 + 0.5;
    screenPos.y = 1.0 - screenPos.y; // flip y
    screenPos.x = screenPos.x * viewportSize.x;
    screenPos.y = screenPos.y * viewportSize.y;
    return screenPos;
}

float3 getNDCPos(float4 posClip)
{
    // Convert to NDC
    float3 ndcPos = (posClip.xyz / posClip.w);
    ndcPos.y = 1.0 - ndcPos.y; // flip y
    return ndcPos;
}

[maxvertexcount(3)]
void main_gs0_adj(
    triangleadj VSOutput Input[6],
    inout TriangleStream<GSOutput> Output)
{

    static const uint triIdx[3] = {0, 2, 4};
    static const uint adjIdx[3] = {1, 3, 5};

    // Calculate normals in view space
    float3 vNormals[3];
    float2 posScreen[3];
    float3 posViewSpace[3];
    float3 adjNormalsNDC[3];
    float3 adjNormalsVS[3];
    float3 isDiscontinuityEdge  = float3(0, 0, 0);
    float3 posNDC[6];
    float3 posView[6];

    [unroll] for(int v = 0; v < 6; v++)
    {
        posNDC[v] = (getNDCPos(Input[v].posClip)); // Convert to NDC
        posView[v] = Input[v].vtx.posView.xyz;
    }
    
    float3 edge0 = posNDC[4] - posNDC[0];
    float3 edge1 = posNDC[2] - posNDC[0];
    float3 surfaceNormalNDC = normalize(cross(edge0, edge1));

    float3 edge0VS = posView[4] - posView[0];
    float3 edge1VS = posView[2] - posView[0];
    float3 surfaceNormalVS = normalize(cross(edge0VS, edge1VS));

    
    //Clockwise surface normals for adjacent triangles
    float3 adjEdge0 = posNDC[2] - posNDC[0];
    float3 adjEdge1 = posNDC[1] - posNDC[0];
    adjNormalsNDC[0] = normalize(cross(adjEdge0, adjEdge1));

    float3 adjEdge0VS = posView[2] - posView[0];
    float3 adjEdge1VS = posView[1] - posView[0];
    adjNormalsVS[0] = normalize(cross(adjEdge0VS, adjEdge1VS));


    float3 adjEdge2 = posNDC[4] - posNDC[2];
    float3 adjEdge3 = posNDC[3] - posNDC[2];
    adjNormalsNDC[1] = normalize(cross(adjEdge2, adjEdge3));

    float3 adjEdge2VS = posView[4] - posView[2];
    float3 adjEdge3VS = posView[3] - posView[2];
    adjNormalsVS[1] = normalize(cross(adjEdge2VS, adjEdge3VS));


    float3 adjEdge4 = posNDC[0] - posNDC[4];
    float3 adjEdge5 = posNDC[5] - posNDC[4];
    adjNormalsNDC[2] = normalize(cross(adjEdge4, adjEdge5));

    float3 adjEdge4VS = posView[0] - posView[4];
    float3 adjEdge5VS = posView[5] - posView[4];
    adjNormalsVS[2] = normalize(cross(adjEdge4VS, adjEdge5VS));


    [unroll] for(int i = 0; i < 3; i++)
    {
        uint idx                 = triIdx[i]; // 0, 2, 4
        uint adIdx               = adjIdx[i]; // 1, 3, 5
        uint nextIndx            = triIdx[(i + 1) % 3]; // 2, 4, 0
        
        vNormals[i]              = Input[idx].vtx.normalView;
        posScreen[i]             = getScreenSpacePos(Input[idx].posClip, g_ForwardView.view.viewportSize).xy;
        posViewSpace[i]          = Input[idx].vtx.posView.xyz;
        isDiscontinuityEdge[i]   = all(Input[adIdx].vtx.posWorld.xyz == Input[nextIndx].vtx.posWorld.xyz) ? 1.0f : 0.0f; //  with floats can miss matches due to precision

        //TODO: try this:
        //isDiscontinuityEdge[i] = all(abs(Input[adIdx].vtx.posWorld.xyz - Input[nextIndx].vtx.posWorld.xyz) < 0.0001) ? 1.0f : 0.0f;
    }
  
    [unroll] for(int j = 0; j < 3; j++)
    {
        uint idx = triIdx[j];
        GSOutput OutputVertex;
		OutputVertex.posClip            = Input[idx].posClip;
        OutputVertex.gsOut.posVS        = Input[idx].vtx.posView;
		OutputVertex.gsOut.normal       = Input[idx].vtx.normal; // Use normal from input
        OutputVertex.gsOut.normalView   = Input[idx].vtx.normalView;
        OutputVertex.gsOut.normalNDC    = Input[idx].vtx.normalView;

        OutputVertex.gsOut.normalVS[0]  = vNormals[0];
        OutputVertex.gsOut.normalVS[1]  = vNormals[1];
        OutputVertex.gsOut.normalVS[2]  = vNormals[2];
        
        OutputVertex.gsOut.normalNDCoords[0] = vNormals[0];
        OutputVertex.gsOut.normalNDCoords[1] = vNormals[1];
        OutputVertex.gsOut.normalNDCoords[2] = vNormals[2];

        OutputVertex.gsOut.posScreenSpace[0] = posScreen[0];
        OutputVertex.gsOut.posScreenSpace[1] = posScreen[1];
        OutputVertex.gsOut.posScreenSpace[2] = posScreen[2];

        OutputVertex.gsOut.posViewSpace[0] = posViewSpace[0];
        OutputVertex.gsOut.posViewSpace[1] = posViewSpace[1];
        OutputVertex.gsOut.posViewSpace[2] = posViewSpace[2];

        OutputVertex.gsOut.surfaceNormalNDC        = surfaceNormalNDC;
        OutputVertex.gsOut.adjSurfaceNormalsNDC[0] = adjNormalsNDC[0];
        OutputVertex.gsOut.adjSurfaceNormalsNDC[1] = adjNormalsNDC[1];
        OutputVertex.gsOut.adjSurfaceNormalsNDC[2] = adjNormalsNDC[2];

        OutputVertex.gsOut.surfaceNormalVS         = surfaceNormalVS;
        OutputVertex.gsOut.adjSurfaceNormalsVS[0]  = adjNormalsVS[0];
        OutputVertex.gsOut.adjSurfaceNormalsVS[1]  = adjNormalsVS[1];
        OutputVertex.gsOut.adjSurfaceNormalsVS[2]  = adjNormalsVS[2];

        OutputVertex.gsOut.isDiscontinuityEdge[0] = isDiscontinuityEdge[0];
        OutputVertex.gsOut.isDiscontinuityEdge[1] = isDiscontinuityEdge[1];
        OutputVertex.gsOut.isDiscontinuityEdge[2] = isDiscontinuityEdge[2];

    	Output.Append(OutputVertex);
    }
}





