
Texture2D<float4>   t_Src           : register(t0);
Texture2D<float4> u_eraaOffsets     : register(t1);

void main_ps(
	in float4   pos   : SV_Position,
	in float2   uv    : UV,
	out float4 o_rgba : SV_Target)
{

    int2 inputPixelPosition = int2(pos.xy);
    int2 inputTextureSize;
    t_Src.GetDimensions(inputTextureSize.x, inputTextureSize.y);
    inputPixelPosition = clamp(inputPixelPosition, int2(0, 0), inputTextureSize - 1);
    float4 data             = u_eraaOffsets[inputPixelPosition];

#if ERAA_SHOW_DETECTED_EDGES
    o_rgba = data;
#else
    // Get dimensions of the textures
    uint width, height;
    t_Src.GetDimensions(width, height);
    int2 textureSize = int2(width, height);

    float3 centerValue   = t_Src[inputPixelPosition].rgb;
    
    float L = data.x;
    float R = data.y;
    float U = data.z;
    float D = data.w;

    //Pre-calculate neighboring positions with boundary checks
    int2 offsets[8]     = {
        int2(-1, -1), int2(0, -1), int2(1, -1), // Top-left, top, top-right
        int2(-1,  0), int2(1,  0), // Left, right
        int2(-1,  1), int2(0,  1), int2(1,  1)  // Bottom-left, bottom, bottom-right
    };

    // Read neighbor values from the texture
    float3 neighbors[8];
    [unroll]for (int i = 0; i < 8; i++)
    {
        int2 neighborPos = clamp(inputPixelPosition + offsets[i], int2(0, 0), textureSize - 1);
        neighbors[i]     = t_Src[neighborPos].rgb;
    }    

    // Precompute weights
    float w1LR          = 1.0f - L - R;
    float w1UD          = 1.0f - U - D;
    
    float wUL           = U     *   L;
    float wUR           = U     *   R;
    float wU            = U     *   w1LR;

    float wCL           = L     *   w1UD;
    float wC            = w1UD  *   w1LR;
    float wCR           = R     *   w1UD;
 
    float wDL           = D     *   L;
    float wD            = D     *   w1LR;
    float wDR           = D     *   R;

     // Compute the blended value
    float3 blendedValue =        wUL  * neighbors[0] +
                                 wU   * neighbors[1] +
                                 wUR  * neighbors[2] +
                                 wCL  * neighbors[3] +
                                 wCR  * neighbors[4] +
                                 wDL  * neighbors[5] +
                                 wD   * neighbors[6] +
                                 wDR  * neighbors[7] +
                                 wC   * centerValue; 

    o_rgba = float4(blendedValue, 1.0);
#endif

}
