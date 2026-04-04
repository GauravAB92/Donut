
#define MAX_EDGES_PER_PIXEL 3

struct Bounds {
  float2 min;
  float2 max;
};

struct Ray {
  float2 o;
  float2 dir;
};

float computeXIntersection(float a, float b, float c, float y) {
  return -(b * y + c) / a;
}

float computeYIntersection(float a, float b, float c, float x) {
  return -(a * x + c) / b;
}

bool checkHorizontalBounds(float x, float boundLeft, float boundRight) {
  if ((x >= boundLeft) && (x <= boundRight)) {
    return true;
  }

  return false;
}

bool checkVerticalBounds(float y, float boundTop, float boundBottom) {
  if ((y >= boundTop) && (y <= boundBottom)) {
    return true;
  }

  return false;
}

float2x2 getInverseMatrix(float3 dx, float3 dy) {
  float det = dx.x * dy.y - dx.y * dy.x;
  if (abs(det) < 1e-6) {
    return float2x2(0, 0, 0, 0);
  }

  float2x2 mat = float2x2(dx.x, dy.x, dx.y, dy.y);

  float invDet = 1.0 / det;
  return float2x2(dy.y, -dy.x, -dx.y, dx.x) * invDet;
}

void findScreenSpaceEdges(float3 bc, out float2 triVertices[3])
{
  float2x2 invMatrix;

  // use hlsl invert
  // try fine derivatives
  invMatrix = getInverseMatrix(ddx(bc), ddy(bc));

  float2 baryVec0 = float2(1.0, 0.0) - bc.xy;
  float2 baryVec1 = float2(0.0, 1.0) - bc.xy;
  float2 baryVec2 = float2(0.0, 0.0) - bc.xy;

  float2 v0 = mul(invMatrix, baryVec0);
  float2 v1 = mul(invMatrix, baryVec1);
  float2 v2 = mul(invMatrix, baryVec2);

  triVertices[0] = v0;
  triVertices[1] = v1;
  triVertices[2] = v2;
}

bool intersectPixelBounds(Ray e, Bounds p, out float2 intersections[2],
                          out uint pixelEdgeIndex[2], out float pixelEdgeT[2]) 
                          {
  float2 invRayDir = 1.0 / e.dir;
  float tmin = 0.0, tmax = 0.0, tymin = 0.0, tymax = 0.0;
  uint numIntersections = 0;
  bool hFlipped = false, vFlipped = false;

  // Use sign[2] instead conditional
  if (invRayDir.x > 0.0) {
    tmin = (p.min.x - e.o.x) * invRayDir.x;
    tmax = (p.max.x - e.o.x) * invRayDir.x;
  } else {
    tmin = (p.max.x - e.o.x) * invRayDir.x;
    tmax = (p.min.x - e.o.x) * invRayDir.x;
    hFlipped = true;
  }

  if (invRayDir.y < 0.0) {
    tymin = ((p.min.y - e.o.y) * invRayDir.y);
    tymax = ((p.max.y - e.o.y) * invRayDir.y);
  } else {
    tymin = ((p.max.y - e.o.y) * invRayDir.y);
    tymax = ((p.min.y - e.o.y) * invRayDir.y);
    vFlipped = true;
  }

  // Valid intersection
  if ((tmin > tymax) || (tymin > tmax)) 
  {
    return false;
  }

  tmin = max(tmin, tymin);
  tmax = min(tmax, tymax);

  intersections[0] = e.o + e.dir * tmin;
  intersections[1] = e.o + e.dir * tmax;

  if (intersections[0].y == p.min.y) // Top Edge
  {
    pixelEdgeT[numIntersections] = intersections[numIntersections].x - p.min.x;
    pixelEdgeIndex[numIntersections++] = 0;
  } else if (intersections[0].x == p.max.x) // Right Edge
  {
    pixelEdgeT[numIntersections] = intersections[numIntersections].y - p.min.y;
    pixelEdgeIndex[numIntersections++] = 1;
  } else if (intersections[0].y == p.max.y) // Bottom Edge
  {
    pixelEdgeT[numIntersections] = intersections[numIntersections].x - p.max.x;
    pixelEdgeIndex[numIntersections++] = 2;
  } else if (intersections[0].x == p.min.x) // Left Edge
  {
    pixelEdgeT[numIntersections] = intersections[numIntersections].y - p.max.y;
    pixelEdgeIndex[numIntersections++] = 3;
  }

  if (numIntersections != 2) {
    if (intersections[1].y == p.min.y) // Top Edge
    {
      pixelEdgeT[numIntersections] =
          intersections[numIntersections].x - p.min.x;
      pixelEdgeIndex[numIntersections++] = 0;
    } else if (intersections[1].x == p.max.x) // Right Edge
    {
      pixelEdgeT[numIntersections] =
          intersections[numIntersections].y - p.min.y;
      pixelEdgeIndex[numIntersections++] = 1;
    } else if (intersections[1].y == p.max.y) // Bottom Edge
    {
      pixelEdgeT[numIntersections] =
          intersections[numIntersections].x - p.max.x;
      pixelEdgeIndex[numIntersections++] = 2;
    } else if (intersections[1].x == p.min.x) // Left Edge
    {
      pixelEdgeT[numIntersections] =
          intersections[numIntersections].y - p.max.y;
      pixelEdgeIndex[numIntersections++] = 3;
    }
  }

  if (hFlipped || vFlipped) {
    float pe = pixelEdgeT[0];
    pixelEdgeT[0] = pixelEdgeT[1];
    pixelEdgeT[1] = pe;

    uint pei = pixelEdgeIndex[0];
    pixelEdgeIndex[0] = pixelEdgeIndex[1];
    pixelEdgeIndex[1] = pei;
  }

  return (numIntersections == 2);
}

float intersectVerticalEdge(float2 e[2], float c) 
{
  float start =  e[0].x;
  float end   =  e[1].x;

  float denom = end - start;
  if (abs(denom) < 1e-8) {
    denom = 1e-8; // Avoid division by zero, treat as almost parallel
  }
  return (c - start) / denom;
}

float intersectHorizontalEdge(float2 e[2], float c) 
{
  float start = e[0].y;
  float end   = e[1].y;
  float denom = end - start;
  
  if (abs(denom) < 1e-8) {
      denom = 1e-8; // Avoid division by zero, treat as almost parallel
  }

  return (c - start) / denom;
}

// This assumes that the edge intersects pixels and is within the pixel
// side bounds
float intersectPixelCenterYaxis(float2 pixelCenter, float2 e[2]) 
{
  float dx = e[1].x - e[0].x;

  if(abs(dx) < 1e-4f)
  {
    dx = 1e-4f; // Avoid division by zero, treat as almost vertical
  }

  float t = (pixelCenter.x - e[0].x) / dx;
  return lerp(e[0].y, e[1].y, t);
}

float intersectPixelCenterXaxis(float2 pixelCenter, float2 e[2])
{
  float dy = e[1].y - e[0].y;
  if(abs(dy) < 1e-4f)
  {
    dy = 1e-4f; // Avoid division by zero, treat as almost horizontal
  }

  float t = (pixelCenter.y - e[0].y) / dy;
  return lerp(e[0].x, e[1].x, t);
}

bool intersectPixel(float2 ec[2], Bounds pixelCenter, out float pixelEdgeT[2],
                    out uint pixelEdgeIndex[2], out float2 intersections[2], out float4 intersectionSides) 
{

  intersectionSides = float4(0.0,0.0,0.0,0.0);

  Bounds e;
  e.min.x = min(ec[0].x, ec[1].x);
  e.min.y = min(ec[0].y, ec[1].y);
  e.max.x = max(ec[0].x, ec[1].x);
  e.max.y = max(ec[0].y, ec[1].y);

  Bounds p = pixelCenter;

  if (e.max.x < p.min.x || e.min.x > p.max.x || e.max.y < p.min.y || e.min.y > p.max.y)
  {
    return false;
  }

  int numIntersections = 0;
  float triangleEdgeT[2];

  // Top Edge
  if (ec[0].y != ec[1].y) // avoid divide by zero
  {
    float t = intersectHorizontalEdge(ec, p.min.y);
   // if (t >= 0.0 && t <= 1.0)
    {
      float2 intersectionPoint            = lerp(ec[0], ec[1], t);
      if (intersectionPoint.x >= p.min.x && intersectionPoint.x < p.max.x) 
      {
        triangleEdgeT[numIntersections]   = t;
        pixelEdgeT[numIntersections]      = intersectionPoint.x - p.min.x;
        pixelEdgeIndex[numIntersections]  = 0;
        intersections[numIntersections]   = intersectionPoint;
        numIntersections++;
        intersectionSides[0]              = 1.0;
      }
    }
  }

  // Right edge
  if (ec[0].x != ec[1].x) // avoid divide by zero
  {
    float t = intersectVerticalEdge(ec, p.max.x);
   // if(t >= 0.0 && t <= 1.0)
    {
      float2 intersectionPoint            = lerp(ec[0], ec[1], t);
      if (intersectionPoint.y >= p.min.y && intersectionPoint.y < p.max.y) 
      {
        triangleEdgeT[numIntersections]    = t;
        pixelEdgeT[numIntersections]       = intersectionPoint.y - p.min.y;
        pixelEdgeIndex[numIntersections]   = 1;
        intersections[numIntersections]    = intersectionPoint;
        numIntersections++;
        intersectionSides[1]               = 1.0;
      }
    }
  }

  // Bottom Edge
  if (ec[0].y != ec[1].y) // avoid divide by zero
  {
    float t = intersectHorizontalEdge(ec, p.max.y);
   // if (t >= 0.0 && t <= 1.0)
    {
      float2 intersectionPoint = lerp(ec[0], ec[1], t);
      if (intersectionPoint.x > p.min.x && intersectionPoint.x <= p.max.x) {
        triangleEdgeT[numIntersections] = t;
        pixelEdgeT[numIntersections] = p.max.x - intersectionPoint.x;
        pixelEdgeIndex[numIntersections] = 2;
        intersections[numIntersections] = intersectionPoint;
        numIntersections++;
        intersectionSides[2] = 1.0;
      }
    }
  }

  // Left edge
  if (ec[0].x != ec[1].x) {
    float t = intersectVerticalEdge(ec, p.min.x);
   // if (t >= 0.0 && t <= 1.0)
    {
      float2 intersectionPoint = lerp(ec[0], ec[1], t);
      if (intersectionPoint.y > p.min.y && intersectionPoint.y <= p.max.y) {
        triangleEdgeT[numIntersections] = t;
        pixelEdgeT[numIntersections] = p.max.y - intersectionPoint.y;
        pixelEdgeIndex[numIntersections] = 3;
        intersections[numIntersections] = intersectionPoint;
        numIntersections++;
        intersectionSides[3] = 1.0;
      }
    }
  }

  if (numIntersections == 2 && (triangleEdgeT[1] < triangleEdgeT[0])) {
    float te = triangleEdgeT[0];
    triangleEdgeT[0] = triangleEdgeT[1];
    triangleEdgeT[1] = te;

    float pe = pixelEdgeT[0];
    pixelEdgeT[0] = pixelEdgeT[1];
    pixelEdgeT[1] = pe;

    float pie = pixelEdgeIndex[0];
    pixelEdgeIndex[0] = pixelEdgeIndex[1];
    pixelEdgeIndex[1] = pie;

    float2 isec2 = intersections[0];
    intersections[0] = intersections[1];
    intersections[1] = isec2;
  }

  return ((numIntersections == 2) && (triangleEdgeT[1] != triangleEdgeT[0]));
}

float4 calculateERAAOffsets(float xi, float yi, float A, bool isConservativelyGenerated)
{

  float coverage     = (A > 0.5) ? (1.0 - A) : A; //Keep the smallest area as coverage
  
  float  kEps    = 0.0f;
  float  kEps2   = 0.0f;
  float  xe      = 0.0;     
  float  ye      = 0.0;
  float4 bLRUD   = float4(0, 0, 0, 0);

  // Potential =D and U offsets
  if( abs(yi) < 1.0)
  {
    ye  = 1.0 - abs(yi);
    bLRUD.z = (yi > 0.0f) ? 0.0f : 1.0f; //Up
    bLRUD.w = (1.0f - bLRUD.z );        //DOWN
  }

  // Determine R and L offsets possibilities
  if(  abs(xi) < 1.0)
  {
    xe  = 1.0 - abs(xi);
    bLRUD.x = (xi >= 0.0f) ? 0.0f : 1.0f; //Left
    bLRUD.y = (1.0f - bLRUD.x);          //Right
  }
  
  // Calculate the offsets
  float  s            =  (xe + ye); //avoid divide by zero
  float  hori_ratio   =   yi / xi;
  float  vert_ratio   =   xi / yi;
  float  vOffset      =  (ye / s) * coverage;
  float  hOffset      =  (xe / s) * coverage;
  float  alpha        = 0.0f;
  float4 vhOffsets    = float4(hOffset, hOffset, vOffset, vOffset); //vertical and horizontal offsets
  float4 LRUD_primes  = float4(0, 0, 0, 0);                         //L' R' U' D'
  
  LRUD_primes         = bLRUD * vhOffsets;
  //Since D' + R' - D'R' = A - D'R'
  //We need D = alpha * D' and R = alpha * R' and so on inorder to get D + R - DR = A
  
  float inv_s = rcp(s);
  float Q     = xe * ye * inv_s * inv_s;
  float t     = saturate(1 - 4 * coverage * Q);
  float sq_t  = sqrt(t);

  alpha       = 2.0f / (1 + sq_t);  // TODO: use precomputed table and read value given xi and yi as input

  float4 finalOffset =  LRUD_primes * alpha;
 
  return finalOffset; //L' * alpha,  R' * alpha,  U' * alpha,  D' * alpha
}

float4 calculateERAAOffsetsOptimized(float xi, float yi, float A)
{
  float axi = abs(xi);
  float ayi = abs(yi);
  float  xe = max(0.0f,1.0f - axi);
  float  ye = max(0.0f,1.0f - ayi);
  float   s = xe + ye;

  if( s <= 0.0f)
  {
    return float4(0, 0, 0, 0); //No offsets
  }

  float inv_s = rcp(s);
  float h     = (xe * inv_s) * A;
  float v     = (ye * inv_s) * A;

  //generate masks to identify the offsets

  float mL = (xi < 0.0f) * (xe > 0.0f);
  float mR = (xi > 0.0f) * (xe > 0.0f);
  float mU = (yi < 0.0f) * (ye > 0.0f);
  float mD = (yi > 0.0f) * (ye > 0.0f);


  //Evaluate alpha
  float Q  = (xe * ye) * inv_s * inv_s;
  float sq_t  = sqrt(saturate(1 - 4 * A * Q));
  float alpha = rcp(0.5 * (1 + sq_t));

  return float4(mL * h, mR * h, mU * v, mD * v) * alpha; //L' * alpha,  R' * alpha,  U' * alpha,  D' * alpha
}

// returns LRUD
float4 evaluateERAAMetaData(float2  pixelPos,
                            float2  triangleCoords[3],
                            float2  intersectedEdge[2],
                            float4  intersectedSides, 
                            float   A, 
                            float3  barycentricCoords,
                            bool    isConservativelyGenerated,
                            bool    explicitEdge,
                            out float o_dx,
                            out float o_dy)
 {

  float xi = 2.0f;
  float yi = 2.0f;

  xi = (intersectPixelCenterXaxis(pixelPos, intersectedEdge) - pixelPos.x);   
  yi = (intersectPixelCenterYaxis(pixelPos, intersectedEdge) - pixelPos.y);    

  o_dx = xi;
  o_dy = yi;  

  return calculateERAAOffsets(xi, yi , A , isConservativelyGenerated);
}

bool intersectEdgeWithPixel(
    float4 i_position,
    float2 triangleCoords[3],
    float2 edgeVertices[2],
    float3 barycentricCoords,
    bool   isConservativelyGenerated,
    bool   explicitEdge,
    out float4 color,
    out float3 xiyiA
    )
{
    // This function is used to evaluate the silhouette edges
    float4 intersectedSide     					          =  float4(0.0, 0.0, 0.0, 0.0);
    float2 intersections[2]    					          = {float2(0.0, 0.0), float2(0.0, 0.0)};
    float2 pixelPos               				        = i_position.xy;
    float2 baseOffset                             = pixelPos; 
    float pixelEdgeT[2]                           = {0.0, 0.0};
    float numIntersecs                            =  0.0;
    float edgeCoverage                            =  0.0;
    uint pixelEdgeIndex[2] 						            = {0, 0};
    bool intersecting                             = false;
  
    Bounds pixelBounds;
    pixelBounds.min = baseOffset + float2(-0.5, -0.5);
    pixelBounds.max = baseOffset + float2( 0.5,  0.5);

    edgeCoverage = 0.0;

    float2 P1       =  edgeVertices[0];
    float2 P2       =  edgeVertices[1];


    float2 ec[2]    = {P1, P2};
    float2 isecs[2] = {float2(0.0, 0.0), float2(0.0, 0.0)};     

    bool only_adjacent = false;
    color = float4(0.0, 0.0, 0.0, 0.0);
    
    float3 localXiYiA = float3(2.0, 2.0, 1.0);

    if(intersectPixel(ec, pixelBounds, pixelEdgeT, pixelEdgeIndex, isecs, intersectedSide))
    {
        uint c = (pixelEdgeIndex[1] - pixelEdgeIndex[0] + 4) % 4;

        switch (c) 
        {
            case 0:
                break;
            case 1:
                edgeCoverage  = 1.0f - (((1.0f - pixelEdgeT[0]) * pixelEdgeT[1]) * 0.5f);
                only_adjacent = true;
                break;
            case 2:
                edgeCoverage  = ((pixelEdgeT[0] + (1.0f - pixelEdgeT[1])) * 0.5f);
                break;
            case 3:
                only_adjacent = true;
                edgeCoverage  = ((pixelEdgeT[0] * (1.0f - pixelEdgeT[1]))) * 0.5f;
            break;
        }

        intersections[0] = isecs[0];
        intersections[1] = isecs[1];

        float xi                  =   0.0;
        float yi                  =   0.0;
        float2 outputIntersectedEdge[2];
        float2 intersectedEdge[2] = {intersections[0], intersections[1]};
        float  A                  = (edgeCoverage > 0.5) ? (1.0 - edgeCoverage) : edgeCoverage;  
        float4 resultOffsets      = evaluateERAAMetaData
                                            ( baseOffset,
                                              triangleCoords,
                                              intersectedEdge,
                                              intersectedSide ,
                                              edgeCoverage,
                                              barycentricCoords,
                                              isConservativelyGenerated,
                                              explicitEdge,
                                              xi,
                                              yi);

        outputIntersectedEdge   = intersectedEdge;
        color                   = resultOffsets;
        intersecting            = true;
        localXiYiA              = float3(xi, yi, A);
     }

    xiyiA = localXiYiA;
  
  return intersecting;
}

