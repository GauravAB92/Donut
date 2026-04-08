#define FXAA_PC 1
#define FXAA_HLSL_5 1
#define FXAA_QUALITY_PRESET 39
#define FXAA_GREEN_AS_LUMA 0

#include <donut/shaders/blit_cb.h>
#include <donut/shaders/FXAA3_11.hlsli>

Texture2D    input_color  : register(t0);
SamplerState linearSampler : register(s0);

struct FXAAConstants
{
    BlitConstants base;
    float2 inverseScreenSize;
};

cbuffer FXAAConstantsBuffer : register(b0)
{
    FXAAConstants fxaaConst;
};

float4 FXAA_PS(
    float4 svPosition : SV_Position,
    noperspective float2 uv         : UV) : SV_Target
{
    FxaaTex fxaaTex;
    fxaaTex.smpl = linearSampler;
    fxaaTex.tex  = input_color;
    //return float4(input_color.Sample(linearSampler, uv).aaa, 1);
    return FxaaPixelShader(
        uv,                         // pos        — center of pixel in UV space
        float4(0,0,0,0),            // fxaaConsolePosPos      — unused (PC)
        fxaaTex,                    // tex
        fxaaTex,                    // fxaaConsole360TexExpBiasNegOne — unused
        fxaaTex,                    // fxaaConsole360TexExpBiasNegTwo — unused
        fxaaConst.inverseScreenSize,          // fxaaQualityRcpFrame    — (1/w, 1/h)
        float4(0,0,0,0),            // fxaaConsoleRcpFrameOpt  — unused (PC)
        float4(0,0,0,0),            // fxaaConsoleRcpFrameOpt2 — unused (PC)
        float4(0,0,0,0),            // fxaaConsole360RcpFrameOpt2 — unused (PC)
        1.00f,                      // fxaaQualitySubpix       — 0.75 default
        0.125f,                     // fxaaQualityEdgeThreshold — 0.166 default
        0.0625f,                    // fxaaQualityEdgeThresholdMin — 0.0833 default
        0.0f,                       // fxaaConsoleEdgeSharpness — unused (PC)
        0.0f,                       // fxaaConsoleEdgeThreshold — unused (PC)
        0.0f,                       // fxaaConsoleEdgeThresholdMin — unused (PC)
        float4(0,0,0,0)             // fxaaConsole360ConstDir  — unused (PC)
    );
}