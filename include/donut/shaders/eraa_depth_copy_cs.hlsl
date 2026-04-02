
RWTexture2D<float>    u_ERAADepthReadTexture            : register(u1);   //is read in render pass
RWTexture2D<float>    u_ERAADepthWriteTexture           : register(u2);   //is written in render pass
RWTexture2D<float>    u_ERAAExtentReadTexture           : register(u3);   //mask to avoid conservative depths
RWTexture2D<float>    u_ERAAExtentWriteTexture          : register(u4);   //is written in render pass

[numthreads(16, 16, 1)]
void main_cs(
    in int2 i_groupIdx  : SV_GroupID,
    in int2 i_threadIdx : SV_GroupThreadID,
    in int2 i_globalIdx : SV_DispatchThreadID
)
{
   uint2 p = i_globalIdx;

    //Compare extent bit to depth texture and prune offsets from eraa metadata
    uint width, height;
    u_ERAADepthWriteTexture.GetDimensions(width, height);
    uint2 depthTextureDims = uint2(width, height);

    if( p.x >= depthTextureDims.x || p.y >= depthTextureDims.y )
    {
        return; // Skip processing if out of bounds
    }
 
    u_ERAADepthReadTexture[p] = u_ERAADepthWriteTexture.Load(int3(p.x, p.y, 0)); // Copy depth value from the depth texture

    u_ERAAExtentReadTexture[p] = u_ERAAExtentWriteTexture.Load(int3(p.x, p.y, 0)); // Copy extent value if valid, otherwise set to 0

}
 