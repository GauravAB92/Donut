
#include <donut/shaders/eraa_shared_data.hlsli>

#define ALGORITHM_VERSION 1

struct EdgeResult 
{
    bool  hit;
    bool  falseEdge;
    float xi;   // intersection with y=0 (center horizontal), normalized: ±1 at vertical edges
    float yi;   // intersection with x=0 (center vertical),   normalized: ±1 at horizontal edges
    float A;    // coverage of D>=0 region inside the pixel (0..1), side containing the center

};

void buildDepthDeltas(
    float3 pixelPosScreen, 
    out float currDepths[9], 
    out float prevDepths[9], 
    out float depthDiffs[9], 
    out float currExtents[9],
    out float extentFramebuffer[9])
{
    uint width, height;
    u_eraaDepthRead.GetDimensions(width, height);
    int2 pixelPosInt = int2(pixelPosScreen.xy);
    
    float3 ddx_pos = ddx_fine(pixelPosScreen);
    float3 ddy_pos = ddy_fine(pixelPosScreen);
    
    [unroll]
    for(int i = 0; i < 9; ++i)
    {
        int2 samplePos = pixelPosInt + pixelIdOffsets[i];
        samplePos = clamp(samplePos, int2(0, 0), int2((int)width - 1, (int)height - 1));
        
        if(i == 4)
        {
            currDepths[i]   = pixelPosScreen.z;
            currExtents[i]  = u_eraaExtentRead[samplePos];
        }
        else
        {

            currDepths[i] = pixelPosScreen.z + 
                            ddx_pos.z * float(pixelIdOffsets[i].x) + 
                            ddy_pos.z * float(pixelIdOffsets[i].y);

            currExtents[i]  = currExtents[4] + 
                            abs(ddx_pos.z) * abs(float(pixelIdOffsets[i].x)) + 
                            abs(ddy_pos.z) * abs(float(pixelIdOffsets[i].y));
        }
        
        prevDepths[i]           = u_eraaDepthRead[samplePos];
        extentFramebuffer[i]    = u_eraaExtentRead[samplePos];
        depthDiffs[i]           = currDepths[i] - prevDepths[i];
    }
}

void inclusionTest(float2 trianglePos[3], float2 pixelPos, out bool pixelInTriangle[9])
{
    for(int i= 0; i < 9; ++i)
    {
        pixelInTriangle[i] =  pixelInsideTest(trianglePos, pixelPos + float2(pixelIdOffsets[i]));
    }
}

// Evaluate D(x,y) = Dc + gx*x + gy*y at (x,y) in pixel-center coords ([-0.5,0.5])
inline float evalD(float Dc, float gx, float gy, float2 p) 
{
    return Dc + gx * p.x + gy * p.y;
}

float CoverageFromCenterAxes(float X, float Y)
{
    X = saturate(X); Y = saturate(Y);
    float dx = X - 0.5;
    float m  = (0.5 - Y) / dx;      // assume not exactly vertical; see note below

    float yL = Y    - 0.5*m;
    float yR = Y    + 0.5*m;
    float xT = 0.5  + (1.0 - Y)/m;
    float xB = 0.5  - Y/m;

    bool hitL = (yL >= 0 && yL <= 1);
    bool hitR = (yR >= 0 && yR <= 1);
    bool hitT = (xT >= 0 && xT <= 1);
    bool hitB = (xB >= 0 && xB <= 1);
    
    float A = 0.0;

         if (hitL && hitT)     A = 0.5 * xT * (1 - yL);
    else if (hitL && hitB)     A = 1.0 - 0.5 * xB * yL;
    else if (hitR && hitT)     A = 0.5 * (1 - xT) * (1 - yR);
    else if (hitR && hitB)     A = 1.0 - 0.5 * (1 - xB) * yR;
    else if (hitL && hitR)     A = 1.0 - 0.5 * (yL + yR);   // left-right
    else if (hitT && hitB)     A = 0.5 * (xB + xT);         // top-bottom

    return saturate(A);
}

bool falseIntersection(float prevZ, float adjZ, float extPrev, bool failedDepthTest, out float eprime)
{
    eprime   =  CalculateEprime(prevZ, extPrev);
   // return false;
    return failedDepthTest ? (eprime <= adjZ) : (eprime >= adjZ); // Account for floating point precision issues
}

void setEdgeInterceptsAndArea(float Dc, float Di, int index, bool offsetsOutside, out EdgeResult r)
{
    float denom         = (abs(Dc) + abs(Di)) ;
    float intercept     = (abs(Dc) / denom) ;

    r.xi = 2.0f; 
    r.yi = 2.0f;
    r.A = intercept > 0.5f ? intercept - 0.5f : 0.5f - intercept;
    
    intercept = offsetsOutside ? -intercept : intercept;

    if(index == 0)      //down +tive
    {
        r.yi = intercept;
    }
    else if(index == 3) //up   -tive
    {
        r.yi = -intercept;
    }
    else if(index == 1) //left
    {
        r.xi = -intercept;
    }
    else if(index == 4) //right
    {
        r.xi = intercept;   
    }
}
   
void setFalseOffsetChannels(float4 offsets, out float4 bLRUD)
{
    bLRUD = float4(0, 0, 0, 0);

    if (offsets.x > 0.0f) bLRUD.x = 1.0f; //Left
    if (offsets.y > 0.0f) bLRUD.y = 1.0f; //Right
    if (offsets.z > 0.0f) bLRUD.z = 1.0f; //Up
    if (offsets.w > 0.0f) bLRUD.w = 1.0f; //Down
}


bool buildIntersectionEdge(
    float2 pixelCenter,
    float currDepths        [9],
    float prevDepths        [9],
    float depthDiffs        [9],
    float prevExtents       [9],
    bool  pixelInTriangle   [9],
    float extent,
    float extent_prev,
    out float4 LRUDOffsets,
    out float3 xiyiA,
    out float eprime,
    out float4 oEdgeSegment
    )
{
    bool edgeFound          = false;
    float2 centerPixelPos   = pixelCenter; 
    float2 edgeSegment[2]   = {float2(0.0f, 0.0f), float2(0.0f, 0.0f)};
    LRUDOffsets             = float4(0.0, 0.0, 0.0, 0.0);
    eprime                  = 0.0f;
    float dcSign            = sign(depthDiffs[4]) >= 0.0f ? 1.0f : -1.0f;
    float dcMag             = abs(depthDiffs[4]); 

    // Quadrant definitions: [diagonal, horizontal, vertical]
    static const int quads[4][3] = {
        {2, 5, 1},  // Top Right
        {0, 3, 1},  // Top Left
        {6, 3, 7},  // Bottom Left
        {8, 5, 7}   // Bottom Right
    };

    // Horizontal and vertical screen space offsets to access neighbors
    static const int2 ssOffsets[4] = {
        int2( 1, -1),  // Right Top 
        int2(-1, -1),  // Left Top 
        int2(-1,  1),  // Left Bottom 
        int2( 1,  1)   // Right Bottom 
    };

    float tEps = 0.0f; 

    bool scaleOffsets = (dcMag < 1e-5f) ;
   
    [unroll]
    for(int i = 0; i < 4; i++)
    {
        float4 offsets      = float4(0.0, 0.0, 0.0, 0.0);
        float3 xiyiA_local  = float3(2.0f, 2.0f, 2.0f); // Initialize to invalid values

        int diag = quads[i][0];
        int horz = quads[i][1];
        int vert = quads[i][2];
        
        float diagSign = sign(depthDiffs[diag]) >= 0.0f ? 1.0f : -1.0f; // Treat zero as positive to avoid ambiguity
        float horzSign = sign(depthDiffs[horz]) >= 0.0f ? 1.0f : -1.0f;
        float vertSign = sign(depthDiffs[vert]) >= 0.0f ? 1.0f : -1.0f;
        bool validEdge = false;
        bool falseEdge = false;
        bool failedDepthTest = (dcSign < 0);
       
        float ep0       = 0.0f;
        float ep1       = 0.0f;

        // Diagonal cases
        if(dcSign == diagSign)
        {
            if(dcSign != horzSign) // Case 3 and 7
            {
                #if ALGORITHM_VERSION == 1
                    if((depthDiffs[4] >= 0.0f) && (pixelInTriangle[4] || pixelInTriangle[vert] || pixelInTriangle[horz] || pixelInTriangle[diag]))
                #else
                    if(pixelInTriangle[4] || pixelInTriangle[horz])
                #endif
                {
                    // Edge crosses right/left boundary and top/bottom of quad
                    float absDc     = abs(depthDiffs[4]);
                    float absHorz   = abs(depthDiffs[horz]);
                    float absDiag   = abs(depthDiffs[diag]);
                    float t0        = (absDc / (absDc + absHorz));
                    edgeSegment[0]  = lerp(centerPixelPos, centerPixelPos + float2(ssOffsets[i].x, 0), t0);
                    float t1        = absDc / (absDc + absDiag);
                    edgeSegment[1]  = lerp(centerPixelPos + float2(ssOffsets[i].x, ssOffsets[i].y), centerPixelPos + float2(ssOffsets[i].x, 0), t1);
                    float depthFB   = prevDepths[4];
                    float extentFB  = prevExtents[4];
                    float currD     = currDepths[horz];
                    falseEdge       = falseEdge  || falseIntersection(depthFB, currD, extentFB, failedDepthTest, ep0);
                    depthFB         = prevDepths[horz];
                    extentFB        = prevExtents[horz];
                    currD           = currDepths[4];
                    falseEdge       = falseEdge  && falseIntersection(depthFB, currD, extentFB, failedDepthTest, ep1);
                    eprime          = max(ep0, ep1);
                    validEdge       = true;
                }
            }
            else if(dcSign != vertSign) // Case 4 and 8
            {
                #if ALGORITHM_VERSION == 1
                    if((depthDiffs[4] >= 0.0f && (pixelInTriangle[4])) || (depthDiffs[vert] >= 0.0f && pixelInTriangle[vert]) ) 
                #else
                    if(pixelInTriangle[4] ||  pixelInTriangle[vert])
                #endif
                {
                    // Edge crosses top/bottom boundary and right/left of quad
                    float absDc     = abs(depthDiffs[4]);
                    float absVert   = abs(depthDiffs[vert]);
                    float t0        = (absDc / (absDc + absVert));
                    edgeSegment[0]  = lerp(centerPixelPos, centerPixelPos + float2(0, ssOffsets[i].y), t0);
                    
                    if(pixelInTriangle[4] ||  pixelInTriangle[diag])
                    {
                        float absDiag   = abs(depthDiffs[diag]);
                        float t1        = (absDiag / (absDiag + absVert));
                        edgeSegment[1]  = lerp(centerPixelPos + float2(ssOffsets[i].x, ssOffsets[i].y), centerPixelPos + float2(0, ssOffsets[i].y), t1);
                        float depthFB   = prevDepths[4];
                        float extentFB  = prevExtents[4];
                        float currD     = currDepths[vert];
                        falseEdge       = falseEdge  || falseIntersection(depthFB, currD, extentFB, failedDepthTest, ep0);
                        depthFB         = prevDepths[vert];
                        extentFB        = prevExtents[vert];
                        currD           = currDepths[4];
                        falseEdge       = falseEdge  && falseIntersection(depthFB, currD, extentFB, !failedDepthTest, ep1);
                        eprime          = max(ep0, ep1);
                        validEdge       = true;
                    }

                }
            }
        }
        else // Adjacent cases
        {
            if((dcSign != horzSign) && (dcSign == vertSign)) // Vertical edge
            {
                #if ALGORITHM_VERSION == 1
                    if(( pixelInTriangle[4] && depthDiffs[4] >= 0.0f) || (depthDiffs[vert] >= 0.0f && pixelInTriangle[vert]))
                #else
                    if(pixelInTriangle[4] || pixelInTriangle[horz])
                #endif
                {
                    float absDc         = abs(depthDiffs[4]);
                    float absHorz       = abs(depthDiffs[horz]);
                    float t0            = (absDc / (absDc + absHorz));
                    edgeSegment[0]      = lerp(centerPixelPos, centerPixelPos + float2(ssOffsets[i].x, 0), t0);
                    
                    if(pixelInTriangle[vert] || pixelInTriangle[diag])
                    {
                        float absVert   = abs(depthDiffs[vert]);
                        float absDiag   = abs(depthDiffs[diag]);
                        float t1        = (absVert / (absVert + absDiag));
                        edgeSegment[1]  = lerp(centerPixelPos + float2(0, ssOffsets[i].y), centerPixelPos + float2(ssOffsets[i].x, ssOffsets[i].y), t1);
                        float depthFB   = prevDepths[4];
                        float extentFB  = prevExtents[4];
                        float currD     = currDepths[horz];
                        falseEdge       = falseEdge  || falseIntersection(depthFB, currD, extentFB, failedDepthTest, ep0);
                        depthFB         = prevDepths[horz];
                        extentFB        = prevExtents[horz];
                        currD           = currDepths[4];
                        falseEdge       = falseEdge  && falseIntersection(depthFB, currD, extentFB, !failedDepthTest, ep1);
                        eprime          = max(ep0, ep1);
                        validEdge       = true;
                    }
                }
            }
            else if ((dcSign != vertSign) && (dcSign == horzSign)) // Horizontal edge
            {
                #if ALGORITHM_VERSION == 1
                    if((pixelInTriangle[4] && depthDiffs[4] >= 0.0f) || (pixelInTriangle[vert] && depthDiffs[vert] >= 0.0f))
                #else
                    if(pixelInTriangle[4] || pixelInTriangle[vert])
                #endif
                {
                    float absDc             = abs(depthDiffs[4]);
                    float absVert           = abs(depthDiffs[vert]);
                    if(absDc + absVert == 0.0f) { continue;}
                    float t0                = (absDc / (absDc + absVert));
                    edgeSegment[0]          = lerp(centerPixelPos, centerPixelPos + float2(0, ssOffsets[i].y),  t0);

                    {
                        float absHorz       = abs(depthDiffs[horz]);
                        float absDiag       = abs(depthDiffs[diag]);
                        if(absHorz + absDiag == 0.0f) { continue;}
                        float t1            = (absHorz / (absHorz + absDiag));
                        edgeSegment[1]      = lerp(centerPixelPos + float2(ssOffsets[i].x, 0), centerPixelPos + float2(ssOffsets[i].x, ssOffsets[i].y), t1);
                        float depthFB       = prevDepths[4];
                        float extentFB      = prevExtents[4];
                        float currD         = currDepths[vert];
                        falseEdge           = falseEdge  || falseIntersection(depthFB, currD, extentFB, failedDepthTest, ep0);
                        depthFB             = prevDepths[vert];
                        extentFB            = prevExtents[vert];
                        currD               = currDepths[4];
                        falseEdge           = falseEdge  && falseIntersection(depthFB, currD, extentFB, !failedDepthTest, ep1);
                        eprime              = max(ep0, ep1);
                        validEdge           = true;
                    }
                }
            }
        }

        float2 triangleCoords[3] = { 
            float2(0.0f, 0.0f), 
            float2(0.0f, 0.0f), 
            float2(0.0f, 0.0f),
        };
 
        #if 1
            if(validEdge && (!falseEdge) && intersectEdgeWithPixel(float4(centerPixelPos, 0.0, 0.0), triangleCoords, edgeSegment, float3(0.0f,0.0f,0.0f), false, false,  offsets, xiyiA_local))
            {
                offsets         = scaleOffsets ? offsets * abs(depthDiffs[4]) : offsets;
                edgeFound       = true;
                LRUDOffsets     = max(offsets,LRUDOffsets);
                xiyiA.x         = xiyiA_local.x ; 
                xiyiA.y         = xiyiA_local.y ; 
                xiyiA.z         = xiyiA_local.z ;
                oEdgeSegment.xy = edgeSegment[0].xy;
                oEdgeSegment.zw = edgeSegment[1].xy; 
            }
        #else
            if(validEdge && (!falseEdge) && intersectEdgeWithPixel(float4(centerPixelPos, 0.0, 0.0),triangleCoords, edgeSegment,float3(0.0f,0.0f,0.0f), false, false,  offsets, xiyiA_local))
            {
                edgeFound   = true;
                LRUDOffsets = max(offsets,LRUDOffsets);
                xiyiA       = max(xiyiA,xiyiA_local);
            }
        #endif
        
        validEdge = false;
        falseEdge = false;
        edgeSegment[0] = float2(0.0f, 0.0f);
        edgeSegment[1] = float2(0.0f, 0.0f);
        xiyiA_local = float3(2.0f, 2.0f, 2.0f);
        offsets = float4(0.0, 0.0, 0.0, 0.0);
    }

    return edgeFound;
}