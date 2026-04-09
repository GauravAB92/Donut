#ifndef ERAA_SHARED_DATA_HLSLI
#define ERAA_SHARED_DATA_HLSLI

//Shared data between Pixel Shader and its include files

enum class EdgeType : uint
{
    Edge_None = 0,
    Edge_Silhouette,
    Edge_Discontinuity,
    Edge_Intersection,
    count
};

RWTexture2D<float4> u_eraaReadOffsets                       : register(u1);
RWTexture2D<float>  u_eraaDepthRead                         : register(u2);
RWTexture2D<float>  u_eraaDepthWrite                        : register(u3);
RWTexture2D<float>  u_eraaExtentRead                        : register(u4);

RasterizerOrderedTexture2D<float>  u_eraaExtentWrite        : register(u5); 
RasterizerOrderedTexture2D<float4> u_eraaWriteOffsets       : register(u6); 

RWTexture2D<uint>  u_eraaExtentL                        : register(u7); 
RWTexture2D<uint>  u_eraaExtentR                        : register(u8); 
RWTexture2D<uint>  u_eraaExtentU                        : register(u9); 
RWTexture2D<uint>  u_eraaExtentD                        : register(u10); 


static const float colorScale = 2.5f;
static const float kEps = 1e-22f;

static const int2 pixelIdOffsets[9] = {
   int2(-1, -1), int2(0, -1), int2(1, -1),
   int2(-1, 0) , int2(0,  0), int2(1, 0),
   int2(-1, 1) , int2(0, 1) , int2(1, 1)
};

static const int adjPixelOffsetId[4] = {0,1,3,4}; //Down, Left, Up, Right

float CalculateEprime(float d_fb, float ext_d_fb)
{
    float delta_fb  = abs(d_fb - ext_d_fb);
    float e_prime   = ext_d_fb - delta_fb;
    return e_prime;
}

#endif // ERAA_SHARED_DATA_HLSLI
