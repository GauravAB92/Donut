//Defines

// Set the HLSL version:
#ifndef SMAA_HLSL_4_1
#define SMAA_HLSL_4
#endif

cbuffer SMAAConstants : register(b0) {
    float4 subsampleIndices;
    float4 rtMetrics;        // float4(1/w, 1/h, w, h)
};

#define SMAA_RT_METRICS rtMetrics   // Override before include

#define SMAA_PRESET_HIGH
#define SMAA_REPROJECTION 1


#include <donut/shaders/SMAA.hlsli>

// Set pixel shader version accordingly:
#if SMAA_HLSL_4_1
#define PS_VERSION ps_4_1
#else
#define PS_VERSION ps_4_0
#endif

//Probably won't be using predication...


Texture2D colorTex      : register(t0);
Texture2D colorTexGamma : register(t0);

Texture2D edgesTex      : register(t0);
Texture2D blendTex      : register(t1);

Texture2D areaTex       : register(t1);
Texture2D searchTex     : register(t2);

Texture2D currentColor  : register(t0);
Texture2D previousColor : register(t1);
Texture2D rw_motionVectors : register(t2);

//Wrappers for Vertex Shaders

void EdgeDetectionVS(
    uint id              : SV_VertexID,     // auto-generated, no IA needed
    out float4 svPosition : SV_POSITION,
    out float2 texcoord   : TEXCOORD0,
    out float4 offset[3]  : TEXCOORD1)
{

    texcoord   = float2((id << 1) & 2, id & 2);
    svPosition = float4(texcoord * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    SMAAEdgeDetectionVS(texcoord, offset);
}

void WeightsCalcVS(
    uint id               : SV_VertexID,
    out float4 svPosition : SV_POSITION,
    out float2 texcoord   : TEXCOORD0,    
    out float2 pixcoord   : TEXCOORD1,
    out float4 offset[3]  : TEXCOORD2)
{
    texcoord   = float2((id << 1) & 2, id & 2);
    svPosition = float4(texcoord * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);

    SMAABlendingWeightCalculationVS(texcoord, pixcoord, offset);
}

void NeighborBlendVS(
    uint id               : SV_VertexID,
    out float4 svPosition : SV_POSITION,
    out float2 texcoord   : TEXCOORD0,   
    out float4 offset     : TEXCOORD1)
{
    texcoord   = float2((id << 1) & 2, id & 2);
    svPosition = float4(texcoord * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);

    SMAANeighborhoodBlendingVS(texcoord, offset);
}

void TemporalResolveVS(
    uint id               : SV_VertexID,
    out float4 svPosition : SV_POSITION,
    out float2 texcoord   : TEXCOORD0
)
{
    texcoord   = float2((id << 1) & 2, id & 2);
    svPosition = float4(texcoord * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
}

//Wrappers for pixel shaders

float2 EdgeDetectionPS(float4 position : SV_POSITION,
    float2 texcoord : TEXCOORD0,
    float4 offset[3] : TEXCOORD1) : SV_TARGET
{
    return SMAAColorEdgeDetectionPS(texcoord, offset, colorTexGamma);
}

float4 WeightsCalcPS(float4 position : SV_Position,
    float2 texcoord : TEXCOORD0,
    float2 pixcoord : TEXCOORD1,
    float4 offset[3] : TEXCOORD2) : SV_TARGET
{
    return SMAABlendingWeightCalculationPS(texcoord, pixcoord, offset, edgesTex, areaTex, searchTex, subsampleIndices);
}

float4 NeighborBlendPS(float4 position : SV_Position,
    float2 texcoord : TEXCOORD0,
    float4 offset : TEXCOORD1) : SV_TARGET
{
    #if SMAA_REPROJECTION
    return SMAANeighborhoodBlendingPS(texcoord, offset, colorTex, blendTex, rw_motionVectors);
    #else
    return SMAANeighborhoodBlendingPS(texcoord, offset, colorTex, blendTex);
    #endif
}

float4 TemporalResolvePS(
    float4 svPosition : SV_POSITION,
    float2 texcoord : TEXCOORD0
) : SV_Target
{
    //return SMAASamplePoint(previousColor, texcoord);
    #if SMAA_REPROJECTION
    return SMAAResolvePS(texcoord, currentColor, previousColor, rw_motionVectors);
    #else
    return SMAAResolvePS(texcoord, currentColor, previousColor);
#endif
}