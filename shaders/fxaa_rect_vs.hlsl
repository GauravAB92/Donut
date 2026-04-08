#include <donut/shaders/blit_cb.h>

struct FXAAConstants
{
    BlitConstants base;
    float2 inverseScreenSize;
};

cbuffer FXAAConstantsBuffer : register(b0)
{
    FXAAConstants fxaaConst;
};

void main(
    in uint iVertex : SV_VertexID,
    out float4 o_posClip : SV_Position,
    noperspective out float2 o_uv : UV)
{
    uint u = iVertex & 1;
    uint v = (iVertex >> 1) & 1;

    float2 src_uv = float2(u, v) * fxaaConst.base.sourceSize + fxaaConst.base.sourceOrigin;
    float2 dst_uv = float2(u, v) * fxaaConst.base.targetSize + fxaaConst.base.targetOrigin;

    o_posClip = float4(dst_uv.x * 2 - 1, 1 - dst_uv.y * 2, 0, 1);
    o_uv = src_uv;
}