#ifndef USE_GS_ADJACENCY_DATA
#define USE_GS_ADJACENCY_DATA 0
#endif

#include <donut/shaders/forward_cb.h>
#include <donut/shaders/forward_vertex.hlsli>

/*
cbuffer CB : register(b0)
{   
    float4x4 g_Transform;
	float4x4 g_ForwardView;  // Forward view matrix, used for screen space calculations
    float4x4 g_Projection;   // Projection matrix
    float4x4 g_InverseProjection; // Inverse projection matrix
    float2   g_ViewportSize; // Viewport size for screen space calculations
    float 	 pad[62];
};

struct VSOutput
{
	float4 posClip   : SV_Position; 	  // Clip space position
    float4 posView   : POSITION;          // View space position
	float4 posWorld  : POSITION5;       // World space position
    float3 normal    : NORMAL;            // Vertex normal
    float3 normalVS  : NORMAL4; 		  // Vertex normal in view space
};

struct GSOutput
{
	float4 posClip                                  : SV_Position; 	    // Clip space position
    float4 posView                                  : POSITION;         //  View space position
    float3 normal                                   : NORMAL;           //  Vertex normal
    uint primitiveID                                : SV_PrimitiveID;
    nointerpolation float3 normalVS[3]              : NORMAL4;
    nointerpolation float3 normalNDC[3]             : NORMAL14;              // Vertex normals in NDC
    nointerpolation float2 posScreenSpace[3]        : TEXCOORD3;
    nointerpolation float3 posViewSpace[3]          : COLOR0;
    nointerpolation float3 surfaceNormalNDC         : COLOR10;
    nointerpolation float3 adjSurfaceNormalsNDC[3]  : COLOR14;           // Edge opposite normal in view space
    nointerpolation float3 surfaceNormalVS          : COLOR24;
    nointerpolation float3 adjSurfaceNormalsVS[3]   : COLOR28;           // Edge opposite normal in view space
    nointerpolation bool   isDiscontinuityEdge[3]   : POSITION15; // Edge opposite normal in view space
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
void main_gs(
    triangle VSOutput Input[3],
    uint primitiveID : SV_PrimitiveID,
    inout TriangleStream<GSOutput> Output)
{
    // Calculate normals in view space
    float3 vNormals[3];
    float3 ndcNormals[3];
    float2 screenPos[3];
    float3 posViewSpace[3];
    float3 posViewShiftedNDC[3];
    float3 adjNormalsNDC[3];
    float3 adjNormalsVS[3];
    float3 posNDC[3];

    for(int i = 0; i < 3; ++i)
    {
        vNormals[i]             = Input[i].normalVS;
        screenPos[i]            = getScreenSpacePos(Input[i].posClip, g_ViewportSize).xy;
        posViewSpace[i]         = Input[i].posView.xyz;
        posViewShiftedNDC[i]    = getNDCPos(mul(g_Projection, float4(Input[i].posView.xyz + Input[i].normalVS, 1.0f)));
        posNDC[i]               = getNDCPos(Input[i].posClip); // Convert to NDC
        ndcNormals[i]           = normalize(posNDC[i] - posViewShiftedNDC[i]); // Calculate NDC normals
    }
    
    float3 edge0NDC = posNDC[1] - posNDC[0];
    float3 edge1NDC = posNDC[2] - posNDC[0];
    float3 surfaceNormalNDC = normalize(cross(edge0NDC, edge1NDC));

    float3 edge0            = Input[1].posView.xyz - Input[0].posView.xyz;
    float3 edge1            = Input[2].posView.xyz - Input[0].posView.xyz;
    float3 surfaceNormalVS  = normalize(cross(edge0, edge1));

    //Clockwise Surface Normals for Adjacent Triangles
    adjNormalsNDC[0] = normalize(Input[0].normalVS + Input[1].normalVS - Input[2].normalVS);
    adjNormalsNDC[1] = normalize(Input[1].normalVS + Input[2].normalVS - Input[0].normalVS);
    adjNormalsNDC[2] = normalize(Input[2].normalVS + Input[0].normalVS - Input[1].normalVS);

    adjNormalsVS[0]  = normalize(Input[0].normalVS + Input[1].normalVS - Input[2].normalVS);
    adjNormalsVS[1]  = normalize(Input[1].normalVS + Input[2].normalVS - Input[0].normalVS);
    adjNormalsVS[2]  = normalize(Input[2].normalVS + Input[0].normalVS - Input[1].normalVS);

    for(int v = 0; v < 3; ++v)
    {
        GSOutput OutputVertex;
		OutputVertex.posClip = Input[v].posClip;
        OutputVertex.posView = Input[v].posView;
        OutputVertex.normal  = Input[v].normal; // Use normal from input
    
        OutputVertex.normalVS[0] = vNormals[0];
        OutputVertex.normalVS[1] = vNormals[1];
        OutputVertex.normalVS[2] = vNormals[2];

        OutputVertex.normalNDC[0] = ndcNormals[0];
        OutputVertex.normalNDC[1] = ndcNormals[1];
        OutputVertex.normalNDC[2] = ndcNormals[2];

        OutputVertex.posScreenSpace[0] = screenPos[0];
        OutputVertex.posScreenSpace[1] = screenPos[1];
        OutputVertex.posScreenSpace[2] = screenPos[2];

        OutputVertex.posViewSpace[0] = posViewSpace[0];
        OutputVertex.posViewSpace[1] = posViewSpace[1];
        OutputVertex.posViewSpace[2] = posViewSpace[2];

        OutputVertex.surfaceNormalNDC           = surfaceNormalNDC;
        OutputVertex.adjSurfaceNormalsNDC[0]    = adjNormalsNDC[0];
        OutputVertex.adjSurfaceNormalsNDC[1]    = adjNormalsNDC[1];
        OutputVertex.adjSurfaceNormalsNDC[2]    = adjNormalsNDC[2];

        OutputVertex.surfaceNormalVS        = surfaceNormalVS;
        OutputVertex.adjSurfaceNormalsVS[0] = adjNormalsVS[0];
        OutputVertex.adjSurfaceNormalsVS[1] = adjNormalsVS[1];
        OutputVertex.adjSurfaceNormalsVS[2] = adjNormalsVS[2];
  
  
        OutputVertex.isDiscontinuityEdge[0] = false;
        OutputVertex.isDiscontinuityEdge[1] = false;
        OutputVertex.isDiscontinuityEdge[2] = false;

        OutputVertex.primitiveID = primitiveID;
    	Output.Append(OutputVertex);
    }
    //Output.RestartStrip();
}

bool IsDiscontinuity(float3 adjPosModel)
{
    return 
        (abs(adjPosModel.x) < 0.01f) &&
        (abs(adjPosModel.y) < 0.01f) &&
        (abs(adjPosModel.z) < 0.01f);
}

[maxvertexcount(3)]
void main_gs_adj(
    triangleadj VSOutput Input[6],
    uint primitiveID : SV_PrimitiveID,
    inout TriangleStream<GSOutput> Output)
{
    static const uint triIdx[3] = {0, 2, 4};
    static const uint adjIdx[3] = {1, 3, 5};

    // Calculate normals in view space
    float3 vNormals[3];
    float2 screenPos[3];
    float3 posViewSpace[3];
    float3 adjNormalsNDC[3];
    float3 adjNormalsVS[3];
    bool   isDiscontinuityEdge[3] = {false, false, false};
    float3 posNDC[6];
    float3 posView[6];

    [unroll] for(int v = 0; v < 6; v++)
    {
        posNDC[v] = (getNDCPos(Input[v].posClip)); // Convert to NDC
        posView[v] = Input[v].posView.xyz;
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
        
        vNormals[i]              = Input[idx].normalVS;
        screenPos[i]             = getScreenSpacePos(Input [idx].posClip, g_ViewportSize).xy;
        posViewSpace[i]          = Input[idx].posView.xyz;
        isDiscontinuityEdge[i]   = all(Input[adIdx].posWorld.xyz == Input[nextIndx].posWorld.xyz); // Check if the edge is a discontinuity edge
    }


    [unroll] for(int j = 0; j < 3; j++)
    {
        uint idx = triIdx[j];
        GSOutput OutputVertex;
		OutputVertex.posClip = Input[idx].posClip;
        OutputVertex.posView = Input[idx].posView;
		OutputVertex.normal  = Input[idx].normal; // Use normal from input

        OutputVertex.normalVS[0] = vNormals[0];
        OutputVertex.normalVS[1] = vNormals[1];
        OutputVertex.normalVS[2] = vNormals[2];
        
        OutputVertex.normalNDC[0] = vNormals[0];
        OutputVertex.normalNDC[1] = vNormals[1];
        OutputVertex.normalNDC[2] = vNormals[2];

        OutputVertex.posScreenSpace[0] = screenPos[0];
        OutputVertex.posScreenSpace[1] = screenPos[1];
        OutputVertex.posScreenSpace[2] = screenPos[2];

        OutputVertex.posViewSpace[0] = posViewSpace[0];
        OutputVertex.posViewSpace[1] = posViewSpace[1];
        OutputVertex.posViewSpace[2] = posViewSpace[2];

        OutputVertex.surfaceNormalNDC        = surfaceNormalNDC;
        OutputVertex.adjSurfaceNormalsNDC[0] = adjNormalsNDC[0];
        OutputVertex.adjSurfaceNormalsNDC[1] = adjNormalsNDC[1];
        OutputVertex.adjSurfaceNormalsNDC[2] = adjNormalsNDC[2];

        OutputVertex.surfaceNormalVS         = surfaceNormalVS;
        OutputVertex.adjSurfaceNormalsVS[0]  = adjNormalsVS[0];
        OutputVertex.adjSurfaceNormalsVS[1]  = adjNormalsVS[1];
        OutputVertex.adjSurfaceNormalsVS[2]  = adjNormalsVS[2];

        OutputVertex.isDiscontinuityEdge[0] = isDiscontinuityEdge[0];
        OutputVertex.isDiscontinuityEdge[1] = isDiscontinuityEdge[1];
        OutputVertex.isDiscontinuityEdge[2] = isDiscontinuityEdge[2];

        OutputVertex.primitiveID = primitiveID;
    	Output.Append(OutputVertex);
    }
}
*/

struct VSOutput
{
    float4 posClip : SV_Position;
    SceneVertex vtx;
};

struct GSOutput
{
    VSOutput Passthrough;
};


[maxvertexcount(3)]
void main_gs0(
    triangle VSOutput Input[3],
    inout TriangleStream<GSOutput> Output)
{
    GSOutput OutputVertex;

    OutputVertex.Passthrough = Input[0];
    Output.Append(OutputVertex);
    OutputVertex.Passthrough = Input[1];
    Output.Append(OutputVertex);
    OutputVertex.Passthrough = Input[2];
    Output.Append(OutputVertex);
}


