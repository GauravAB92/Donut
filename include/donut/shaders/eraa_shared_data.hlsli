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

static const float colorScale = 2.5f;
static const float kEps = 1e-22f;

static const int2 pixelIdOffsets[9] = {
   int2(-1, -1), int2(0, -1), int2(1, -1),
   int2(-1, 0) , int2(0,  0), int2(1, 0),
   int2(-1, 1) , int2(0, 1) , int2(1, 1)
};


static const int adjPixelOffsetId[4] = {0,1,3,4}; //Down, Left, Up, Right

struct GSOutput
{
	float4 posScreen   						        : SV_Position; 		    // Screen space position
	float4 posView   						        : POSITION;             // View space position
	float3 normal    						        : NORMAL;        		// Vertex normal
    uint primitiveID                                : SV_PrimitiveID;
    nointerpolation float3 normalVS[3]              : NORMAL4;              // Vertex normals in view space
    nointerpolation float3 normalNDC[3]             : NORMAL14;             // Vertex normals in NDC
    nointerpolation float2 posScreenSpace[3]        : TEXCOORD3;            // Screen space positions of the triangle vertices
	nointerpolation float3 posViewSpace[3]          : COLOR0;               // View space positions of the triangle vertices
    nointerpolation float3 surfaceNormalNDC         : COLOR10;              // Surface normal in NDC
    nointerpolation float3 adjSurfaceNormalsNDC[3]  : COLOR14;              // Adjacent triangle normals in NDC
    nointerpolation float3 surfaceNormalVS          : COLOR24;
    nointerpolation float3 adjSurfaceNormalsVS[3]   : COLOR28;              // Edge opposite normal in view space
    nointerpolation bool   isDiscontinuityEdge[3]   : POSITION15;
};

ConstantBuffer<ConstantBufferEntry> CB : register(b0);

Texture2D<float>    t_preDepthTexture                       : register(t1);
RWTexture2D<float4> u_eraaOffsets                           : register(u1);
RWTexture2D<float>  u_eraaExtentRead                        : register(u2); 
RWTexture2D<float>  u_eraaExtentWrite                       : register(u3); 
RWTexture2D<float>  u_eraaDepthMask                         : register(u4); 
RWTexture2D<float>  u_eraaDepthWrite                        : register(u5);
RWTexture2D<float>  t_eraaDepthRead                         : register(u6);
RWTexture2D<float4> u_eraaEdgeTypeInfoData                  : register(u7);  
RWStructuredBuffer <EdgeDebugData> u_eraaEdgeDebugData      : register(u8);


float CalculateEprime(float d_fb, float ext_d_fb)
{
    float delta_fb  = abs(d_fb - ext_d_fb);
    float e_prime   = ext_d_fb - delta_fb;
    return e_prime;
}

#endif // ERAA_SHARED_DATA_HLSLI
