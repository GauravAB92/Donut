#ifndef ERAA_EXTENT_DATA_ROUTINES_HLSLI
#define ERAA_EXTENT_DATA_ROUTINES_HLSLI

#include <donut/shaders/eraa_shared_routines.hlsli>


// Computes the depth of a point on a plane defined by a point and a normal vector.
// Returns ndc z[0,1]
bool PlaneLinearDepthAtPixel(float3 origin, float3 direction, float3 planePoint, float3 planeNormal, float4x4 projectionMatrix, out float z)
{
    const float kEps = 1e-6f;
    z = 1.0f;
    float ln = dot(planeNormal, planeNormal);
   
    if (ln < kEps) return false;

    float3 n = planeNormal * rsqrt(ln); //normalize
    
    float denom = dot(n,direction);
    if(abs(denom) < kEps) return false;

    float t = dot(n, (planePoint - origin)) / denom;

    if( t <= 0.0f) return false;

    float3 pos = origin + t * direction;
    z = pos.z; // linear space
    return true;
}

float PlaneNDCDepthAtPixel(float3 origin, float3 direction, float3 planePoint, float3 planeNormal, float4x4 projectionMatrix)
{   
    float z = 1.0f; //default value of far plane

    const float kEps = 1e-8f;

    float ln = dot(planeNormal, planeNormal);
    if (ln < kEps) return z;

    float3 n = normalize(planeNormal); //normalize
    float denom = dot(n,direction);
    if(abs(denom) < kEps) return z;

    float t = dot(n, (planePoint - origin)) * (1.0f / denom);

    if( t <= 0.0f) return z;

    float3 pos = origin + t * direction;
    float4 clip = mul(projectionMatrix, float4(pos,1.0));

    if(clip.w <= 0.0f) return z; // point behind or on the eye

    float ndcZ = clip.z / clip.w;
    return saturate(ndcZ);
}

float PlaneNdcZ(float3 originVS,
                float3 dirVS,          // need not be unit
                float3 planePointVS,
                float3 planeNormalVS,  // need not be unit
                float4x4 proj)
{
    const float NaN     = asfloat(0x7FC00000);
    const float kLenEps = 1e-20f;   // reject degenerate vectors
    const float kAngEps = 1e-7f;    // near-parallel threshold
    const float kWEps   = 1e-12f;   // clip.w guard
    const float kHitEps = 1e-6f;    // allow tiny negative t to snap to 0

    float n2 = dot(planeNormalVS, planeNormalVS);
    float d2 = dot(dirVS, dirVS);
    if (n2 <= kLenEps || d2 <= kLenEps) return NaN;

    float3 n = planeNormalVS * rsqrt(n2);   // normalize in float
    float3 d = dirVS         * rsqrt(d2);

    float denom = dot(n, d);
    if (abs(denom) <= kAngEps) return NaN;  // ray ~ parallel to plane

    // t = (dot(n, P0) - dot(n, O)) / dot(n, d)
    float t = (dot(n, planePointVS) - dot(n, originVS)) / denom;

    if (t < -kHitEps) return NaN;           // intersection behind origin
    t = max(t, 0.0f);                       // snap tiny negatives

    float3 posVS = originVS + d * t;

    float4 clip = mul(proj, float4(posVS, 1.0f));
    if (clip.w <= kWEps) return NaN;        // behind/on the eye

    return clip.z / clip.w;                 // z_ndc (no saturate)
}

float sphIntersect( in float3 ro, in float3 rd, in float3 ce, float ra )
{
    float3 oc = ro - ce;
    float b = dot( oc, rd );
    float c = dot( oc, oc ) - ra*ra;
    float h = b*b - c;
    if( h<0.0 ) return float(-1.0); // no intersection
    h = sqrt( h );

    return float( -b-h);
}

float intersectFitSphere(float3 posVS, float3 triangleVerticesVS[3], float3 vertexNormals[3], float4x4 projectionMatrix)
{
    float  max_r = 0.0f;
    float3 c     = float3(0.0f, 0.0f, 0.0f);

    for(int i = 0; i < 3; ++i)
    {
        float3 n = normalize(vertexNormals[i]);
        float3 v2 = triangleVerticesVS[i] - triangleVerticesVS[(i + 1) % 3];
        float3 v3 = triangleVerticesVS[i] - triangleVerticesVS[(i + 2) % 3];

        float numerator     = dot(v3, v3) - dot(v2, v2);
        float denominator   = 2.0f * dot(n, v3 - v2);

        // Avoid division by zero
        if (abs(denominator) < 1e-6) continue;

        float t = numerator / denominator;
        float3 current_c = triangleVerticesVS[i] - t * n;
        float  r = abs(t);

        // Choose the sphere max, for smallest z ( closest extent value)
        if (r > max_r)
        {
            max_r   = r;
            c       = current_c;
        }
    }
    
    float3 rayDir   = normalize(posVS);
    float zVS       = sphIntersect(float3(0.0f, 0.0f, 0.0f), rayDir, c, max_r);

    return ToNDCPosition(float3(posVS.x, posVS.y, zVS), projectionMatrix).z; // Convert to NDC Z
}

float intersectFitSphere2(float3 posVS, float3 verts[3], float3 normals[3], float4x4 proj)
{
    float numerator   = 0.0f;
    float denominator = 0.0f;

    for (int j = 1; j < 3; ++j)
    {
        float3 dp = verts[j]   - verts[0];   // p_j - p_0
        float3 dn = normals[0] - normals[j]; // n_0 - n_j

        numerator   += dot(dp, dn);
        denominator += dot(dn, dn);
    }

    if (abs(denominator) < 1e-6f)
        return ToNDCPosition(posVS, proj).z; // degenerate: flat triangle, fall back

    float r = (numerator / denominator);

    // --- Compute center (average over all three vertices for robustness) ---
    float3 c = float3(0.0f, 0.0f, 0.0f);
    for (int i = 0; i < 3; ++i)
        c += verts[i] + r * normals[i];
    c /= 3.0f;

    // --- Intersect view ray with sphere, output conservative NDC depth ---
    float3 rayDir = normalize(posVS);
    float  t      = sphIntersect(float3(0.0f, 0.0f, 0.0f), rayDir, c, abs(r));

    if (t < 0.0f)
        return ToNDCPosition(posVS, proj).z; // ray missed sphere, fall back

    float3 hitVS = rayDir * t;
    return ToNDCPosition(hitVS, proj).z;
}


void evaluateExtentedDepth(
    float depth,
    out float  extentedDepthMin      = 0.0f,
    out float  extentedDepthMax      = 0.0f)
{
    float intersectionDepth = 1.0f;

    float2 c0 = float2(-0.5,-0.5);
    float2 c1 = float2( 0.5,-0.5);
    float2 c2 = float2( 0.5, 0.5);
    float2 c3 = float2(-0.5, 0.5);

    float zc = depth; // center depth
    float gx = ddx_fine(zc);
    float gy = ddy_fine(zc);
    float z0 = zc + gx*c0.x + gy*c0.y;
    float z1 = zc + gx*c1.x + gy*c1.y;
    float z2 = zc + gx*c2.x + gy*c2.y;
    float z3 = zc + gx*c3.x + gy*c3.y;
    extentedDepthMax         = min(min(z0,z1), min(z2,z3));
    extentedDepthMin         = max(max(z0,z1), max(z2,z3));
}


#endif // ERAA_EXTENT_DATA_ROUTINES_HLSLI

















