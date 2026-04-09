
bool detectSilhouetteEdgeNDC_GSADJ(float3 surfaceNormalNDC, float3 adjacentFaceNormalNDC)
{
    return surfaceNormalNDC.z * adjacentFaceNormalNDC.z <= 0.0f;
}

bool detectSilhouetteEdgeVS_GSADJ(float3 surfaceNormalVS, float3 adjacentFaceNormalVS, float3 viewVector, out float weight)
{
    float d0 = dot(surfaceNormalVS, viewVector);
    float d1 = dot(adjacentFaceNormalVS, viewVector);
    float d3 = dot(surfaceNormalVS, adjacentFaceNormalVS);
    
    bool silhouette = (d0 * d1 < 0.015f); // allow some tolerance for near-grazing angles
    bool grazing = (min(abs(d0), abs(d1)) < 0.05f);
    
    float edgeness = 1.0 - abs(d0);
    
    // How much do the two faces diverge relative to the view
    float normalDiff = 1.0 - dot(surfaceNormalVS, adjacentFaceNormalVS);
    
    // Combine: strong edge where face is nearly edge-on AND normals differ
    weight = edgeness * saturate(normalDiff * 10.0);
    
    // Also catch hard sign flips
    if (d0 * d1 < 0.0)
        weight = max(weight, saturate(abs(d0 - d1)));

    return silhouette || (d3 < 0.01f);
}  
 
bool detectSilhouetteEdgeNDC(int vtxID,float3 perVertexNormalsNDC[3], float3 surfaceNormalNDC, out float3 computedNormal, out bool backFace) 
{
    float3 n0 = normalize(perVertexNormalsNDC[ vtxID]);
    float3 n1 = normalize(perVertexNormalsNDC[(vtxID + 1) % 3]);
    float3 n2 = normalize(perVertexNormalsNDC[(vtxID + 2) % 3]);
    float3 nm = normalize(n0 + n1);

    float3 faceNormal1              =  normalize(surfaceNormalNDC);
    float3 faceNormal1_reflected    =  normalize(2.0f * nm * dot(faceNormal1, nm) - faceNormal1);
   
    backFace        = (faceNormal1.z > 0.0f);
    computedNormal  = backFace ? faceNormal1_reflected : faceNormal1;
    return faceNormal1.z * faceNormal1_reflected.z <= 0.0f;
}

bool detectSilhouetteEdgeVS(int vtxID, float3 perVertexNormalsVS[3], float3 viewVector, out float3 computedNormal, out bool backFace) 
{
    float3 n0 = normalize(perVertexNormalsVS[ vtxID]);
    float3 n1 = normalize(perVertexNormalsVS[(vtxID + 1) % 3]);
    float3 n2 = normalize(perVertexNormalsVS[(vtxID + 2) % 3]);
    float3 nm = normalize(n0 + n1);

    float3 n2_reflected = normalize(2.0f * nm * dot(n2, nm) - n2);
    float3 n3           = normalize(n0 + n1 - n2);
    float3 faceNormal1  = normalize(n0 + n1 + n2);
    float3 faceNormal2  = normalize(n0 + n1 + n2_reflected);
    //float3 faceNormal2  = normalize(n0 + n1 + n3);

    float d0 = dot(faceNormal1, viewVector);
    float d1 = dot(faceNormal2, viewVector);

   // check if triangle is back facing
    backFace = dot(faceNormal1, viewVector) < 0.0f;
    computedNormal = backFace ? faceNormal1 : faceNormal2;
    return d0 * d1 <= 0.0f;
}

bool detectSilhouetteEdgeVS2(int vtxID, float3 perVertexNormalsVS[3], float3 perVertexPosVS[3], float3 surfaceNormalVS, float3 viewVector, out float3 computedNormal, out bool backFace) 
{
    float3 p0   = perVertexPosVS[vtxID];
    float3 p1   = perVertexPosVS[(vtxID + 1) % 3];
    float3 p2   = perVertexPosVS[(vtxID + 2) % 3];
    
    float3 n0   = normalize(perVertexNormalsVS[vtxID]);
    float3 n1   = normalize(perVertexNormalsVS[(vtxID + 1) % 3]);
    float3 n2   = normalize(perVertexNormalsVS[(vtxID + 2) % 3]);

    float3 edgeVector = normalize(p1 - p0);

    float3 n0_perp    = normalize(n0 - dot(n0, edgeVector) * edgeVector);
    float3 n1_perp    = normalize(n1 - dot(n1, edgeVector) * edgeVector);
    
    float3 nm         = normalize(n0_perp + n1_perp);    
    //float3 nm       = normalize(n0 + n1);

    float3 faceNormal               = normalize(surfaceNormalVS);
    float3 approxNormal             = normalize(n0 + n1 + n2);
    float3 reflected_faceNormal     = normalize(2.0f * nm * dot(faceNormal, nm) - faceNormal);
    float3 extrapolated_normal      = normalize(2.0f * nm - faceNormal);

    backFace            = dot(faceNormal, viewVector) < 0.0f;
    computedNormal      = backFace ? reflected_faceNormal : faceNormal;
    float d0            = dot(faceNormal, viewVector);
    float d1            = dot(reflected_faceNormal, viewVector);
    
    return (d0 * d1 <= 0.0f);
}

bool detectSilhouetteEdgeVSConfidenceTest(int vtxID, float3 perVertexNormalsVS[3], float3 perVertexPosVS[3],
 float3 surfaceNormalVS, float3 viewVector, out float3 computedNormal, out bool backFace, out float confidence) 
{
    confidence = 1.0f; 

    float3 p0   = perVertexPosVS[vtxID];
    float3 p1   = perVertexPosVS[(vtxID + 1) % 3];
    
    float3 n0   = normalize(perVertexNormalsVS[vtxID]);
    float3 n1   = normalize(perVertexNormalsVS[(vtxID + 1) % 3]);
    float3 n2   = normalize(perVertexNormalsVS[(vtxID + 2) % 3]);

    float3 edgeVector = normalize(p1 - p0);
    float3 n0_perp    = normalize(n0 - dot(n0, edgeVector) * edgeVector);
    float3 n1_perp    = normalize(n1 - dot(n1, edgeVector) * edgeVector);
    
    float3 nm                   = normalize(n0_perp + n1_perp);    
    float3 faceNormal           = normalize(surfaceNormalVS);
    float3 reflected_faceNormal = normalize(2.0f * nm * dot(faceNormal, nm) - faceNormal);

    float3 reflected_faceNormal_n0 = normalize(2.0f * n0_perp * dot(faceNormal, n0_perp) - faceNormal);
    float3 reflected_faceNormal_n1 = normalize(2.0f * n1_perp * dot(faceNormal, n1_perp) - faceNormal);

    float d0 = dot(faceNormal,  viewVector);
    float d1 = dot(reflected_faceNormal_n0,     viewVector);
    float d2 = dot(reflected_faceNormal_n1,     viewVector);

    bool  t1 = (d0 * d1) <= 0.0f;
    bool  t2 = (d0 * d2) <= 0.0f;

    backFace            = (d0 < 0.0f);
    computedNormal      = backFace ? reflected_faceNormal : faceNormal;
    
    // //Either Silhouette edge or not
    if(t1 == t2)
    {
        confidence      = 1.0f; // No confidence calculation needed
        return t1;
    }
    else //may or may not be silhouette edge
    {
        if(t1 > 0.0f)
        {
            confidence = d1 > d2 ? (d1 / (d1 - d2)) : (d2 / (d2 - d1));
        
            return true;
        }
    }
    return  false;
} 
