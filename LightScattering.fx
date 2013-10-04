//--------------------------------------------------------------------------------------
// Copyright 2013 Intel Corporation
// All Rights Reserved
//
// Permission is granted to use, copy, distribute and prepare derivative works of this
// software for any purpose and without fee, provided, that the above copyright notice
// and this statement appear in all copies.  Intel makes no representations about the
// suitability of this software for any purpose.  THIS SOFTWARE IS PROVIDED "AS IS."
// INTEL SPECIFICALLY DISCLAIMS ALL WARRANTIES, EXPRESS OR IMPLIED, AND ALL LIABILITY,
// INCLUDING CONSEQUENTIAL AND OTHER INDIRECT DAMAGES, FOR THE USE OF THIS SOFTWARE,
// INCLUDING LIABILITY FOR INFRINGEMENT OF ANY PROPRIETARY RIGHTS, AND INCLUDING THE
// WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.  Intel does not
// assume any responsibility for any errors which may appear in this software nor any
// responsibility to update it.
//--------------------------------------------------------------------------------------

#include "Common.fxh"

#ifndef STAINED_GLASS
#   define STAINED_GLASS 1
#endif

#ifndef OPTIMIZE_SAMPLE_LOCATIONS
#   define OPTIMIZE_SAMPLE_LOCATIONS 1
#endif

#ifndef LIGHT_TYPE
#   define LIGHT_TYPE LIGHT_TYPE_POINT
#endif

#ifndef ANISOTROPIC_PHASE_FUNCTION
#   define ANISOTROPIC_PHASE_FUNCTION 1
#endif

#define SHADOW_MAP_DEPTH_BIAS 1e-4

//--------------------------------------------------------------------------------------
// Texture samplers
//--------------------------------------------------------------------------------------

SamplerState samLinearClamp : register( s0 )
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = Clamp;
    AddressV = Clamp;
};

SamplerState samLinearBorder0 : register( s1 )
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = Border;
    AddressV = Border;
    BorderColor = float4(0.0, 0.0, 0.0, 0.0);
};

SamplerState samLinearUClampVWrap : register( s2 )
{
    Filter = MIN_MAG_MIP_LINEAR;
    AddressU = CLAMP;
    AddressV = WRAP;
};

SamplerComparisonState samComparison : register( s3 )
{
    Filter = COMPARISON_MIN_MAG_LINEAR_MIP_POINT;
    AddressU = Border;
    AddressV = Border;
    ComparisonFunc = GREATER;
    BorderColor = float4(0.0, 0.0, 0.0, 0.0);
};

//--------------------------------------------------------------------------------------
// Depth stencil states
//--------------------------------------------------------------------------------------

// Depth stencil state disabling depth test
DepthStencilState DSS_NoDepthTest
{
    DepthEnable = false;
    DepthWriteMask = ZERO;
};

DepthStencilState DSS_NoDepthTestIncrStencil
{
    DepthEnable = false;
    DepthWriteMask = ZERO;
    STENCILENABLE = true;
    FRONTFACESTENCILFUNC = ALWAYS;
    BACKFACESTENCILFUNC = ALWAYS;
    FRONTFACESTENCILPASS = INCR;
    BACKFACESTENCILPASS = INCR;
};

DepthStencilState DSS_NoDepth_StEqual_IncrStencil
{
    DepthEnable = false;
    DepthWriteMask = ZERO;
    STENCILENABLE = true;
    FRONTFACESTENCILFUNC = EQUAL;
    BACKFACESTENCILFUNC = EQUAL;
    FRONTFACESTENCILPASS = INCR;
    BACKFACESTENCILPASS = INCR;
    FRONTFACESTENCILFAIL = KEEP;
    BACKFACESTENCILFAIL = KEEP;
};


//--------------------------------------------------------------------------------------
// Rasterizer states
//--------------------------------------------------------------------------------------

// Rasterizer state for solid fill mode with no culling
RasterizerState RS_SolidFill_NoCull
{
    FILLMODE = Solid;
    CullMode = NONE;
};


// Blend state disabling blending
BlendState NoBlending
{
    BlendEnable[0] = FALSE;
    BlendEnable[1] = FALSE;
    BlendEnable[2] = FALSE;
};

float2 ProjToUV(in float2 f2ProjSpaceXY)
{
    return float2(0.5, 0.5) + float2(0.5, -0.5) * f2ProjSpaceXY;
}

float2 UVToProj(in float2 f2UV)
{
    return float2(-1.0, 1.0) + float2(2.0, -2.0) * f2UV;
}

float GetCamSpaceZ(in float2 ScreenSpaceUV)
{
    return g_tex2DCamSpaceZ.SampleLevel(samLinearClamp, ScreenSpaceUV, 0);
}

float3 ToneMap(in float3 f3Color)
{
    float fExposure = g_PPAttribs.m_fExposure;
    return 1.0 - exp(-fExposure * f3Color);
}

float3 ProjSpaceXYToWorldSpace(in float2 f2PosPS)
{
    // We can sample camera space z texture using bilinear filtering
    float fCamSpaceZ = g_tex2DCamSpaceZ.SampleLevel(samLinearClamp, ProjToUV(f2PosPS), 0);
    return ProjSpaceXYZToWorldSpace(float3(f2PosPS, fCamSpaceZ));
}

float4 WorldSpaceToShadowMapUV(in float3 f3PosWS)
{
    float4 f4LightProjSpacePos = mul( float4(f3PosWS, 1), g_LightAttribs.mWorldToLightProjSpace );
    f4LightProjSpacePos.xyz /= f4LightProjSpacePos.w;
    float4 f4UVAndDepthInLightSpace;
    f4UVAndDepthInLightSpace.xy = ProjToUV( f4LightProjSpacePos.xy );
    // Applying depth bias results in light leaking through the opaque objects when looking directly
    // at the light source
    f4UVAndDepthInLightSpace.z = f4LightProjSpacePos.z;// * g_DepthBiasMultiplier;
    f4UVAndDepthInLightSpace.w = 1/f4LightProjSpacePos.w;
    return f4UVAndDepthInLightSpace;
}

struct SScreenSizeQuadVSOutput
{
    float4 m_f4Pos : SV_Position;
    float2 m_f2PosPS : PosPS; // Position in projection space [-1,1]x[-1,1]
};

SScreenSizeQuadVSOutput GenerateScreenSizeQuadVS(in uint VertexId : SV_VertexID)
{
    float4 MinMaxUV = float4(-1, -1, 1, 1);
    
    SScreenSizeQuadVSOutput Verts[4] = 
    {
        {float4(MinMaxUV.xy, 1.0, 1.0), MinMaxUV.xy}, 
        {float4(MinMaxUV.xw, 1.0, 1.0), MinMaxUV.xw},
        {float4(MinMaxUV.zy, 1.0, 1.0), MinMaxUV.zy},
        {float4(MinMaxUV.zw, 1.0, 1.0), MinMaxUV.zw}
    };

    return Verts[VertexId];
}

float ReconstructCameraSpaceZPS(SScreenSizeQuadVSOutput In) : SV_Target
{
    float fDepth = g_tex2DDepthBuffer.Load( uint3(In.m_f4Pos.xy,0) );
    float fCamSpaceZ = g_CameraAttribs.mProj[3][2]/(fDepth - g_CameraAttribs.mProj[2][2]);
    return fCamSpaceZ;
};

technique11 ReconstructCameraSpaceZ
{
    pass
    {
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        SetDepthStencilState( DSS_NoDepthTest, 0 );

        SetVertexShader( CompileShader(vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader(ps_5_0, ReconstructCameraSpaceZPS() ) );
    }
}

const float4 GetOutermostScreenPixelCoords()
{
    // The outermost visible screen pixels centers do not lie exactly on the boundary (+1 or -1), but are biased by
    // 0.5 screen pixel size inwards
    //
    //                                        2.0
    //    |<---------------------------------------------------------------------->|
    //
    //       2.0/Res
    //    |<--------->|
    //    |     X     |      X     |     X     |    ...    |     X     |     X     |
    //   -1     |                                                            |    +1
    //          |                                                            |
    //          |                                                            |
    //      -1 + 1.0/Res                                                  +1 - 1.0/Res
    //
    // Using shader macro is much more efficient than using constant buffer variable
    // because the compiler is able to optimize the code more aggressively
    // return float4(-1,-1,1,1) + float4(1, 1, -1, -1)/g_PPAttribs.m_f2ScreenResolution.xyxy;
    return float4(-1,-1,1,1) + float4(1, 1, -1, -1) / SCREEN_RESLOUTION.xyxy;
}

// This function computes entry point of the epipolar line given its exit point
//                  
//    g_LightAttribs.f4LightScreenPos
//       *
//        \
//         \  f2EntryPoint
//        __\/___
//       |   \   |
//       |    \  |
//       |_____\_|
//           | |
//           | f2ExitPoint
//           |
//        Exit boundary
float2 GetEpipolarLineEntryPoint(float2 f2ExitPoint)
{
    float2 f2EntryPoint;

    //if( all( abs(g_LightAttribs.f4LightScreenPos.xy) < 1 ) )
    if( g_LightAttribs.bIsLightOnScreen )
    {
        // If light source is inside the screen, its location is entry point for each epipolar line
        f2EntryPoint = g_LightAttribs.f4LightScreenPos.xy;
    }
    else
    {
        // If light source is outside the screen, we need to compute intersection of the ray with
        // the screen boundaries
        
        // Compute direction from the light source to the exit point
        // Note that exit point must be located on shrinked screen boundary
        float2 f2RayDir = f2ExitPoint.xy - g_LightAttribs.f4LightScreenPos.xy;
        float fDistToExitBoundary = length(f2RayDir);
        f2RayDir /= fDistToExitBoundary;
        // Compute signed distances along the ray from the light position to all four boundaries
        // The distances are computed as follows using vector instructions:
        // float fDistToLeftBoundary   = abs(f2RayDir.x) > 1e-5 ? (-1 - g_LightAttribs.f4LightScreenPos.x) / f2RayDir.x : -FLT_MAX;
        // float fDistToBottomBoundary = abs(f2RayDir.y) > 1e-5 ? (-1 - g_LightAttribs.f4LightScreenPos.y) / f2RayDir.y : -FLT_MAX;
        // float fDistToRightBoundary  = abs(f2RayDir.x) > 1e-5 ? ( 1 - g_LightAttribs.f4LightScreenPos.x) / f2RayDir.x : -FLT_MAX;
        // float fDistToTopBoundary    = abs(f2RayDir.y) > 1e-5 ? ( 1 - g_LightAttribs.f4LightScreenPos.y) / f2RayDir.y : -FLT_MAX;
        
        // Note that in fact the outermost visible screen pixels do not lie exactly on the boundary (+1 or -1), but are biased by
        // 0.5 screen pixel size inwards. Using these adjusted boundaries improves precision and results in
        // smaller number of pixels which require inscattering correction
        float4 f4Boundaries = GetOutermostScreenPixelCoords();
        bool4 b4IsCorrectIntersectionFlag = abs(f2RayDir.xyxy) > 1e-5;
        float4 f4DistToBoundaries = (f4Boundaries - g_LightAttribs.f4LightScreenPos.xyxy) / (f2RayDir.xyxy + !b4IsCorrectIntersectionFlag);
        // Addition of !b4IsCorrectIntersectionFlag is required to prevent divison by zero
        // Note that such incorrect lanes will be masked out anyway

        // We now need to find first intersection BEFORE the intersection with the exit boundary
        // This means that we need to find maximum intersection distance which is less than fDistToBoundary
        // We thus need to skip all boundaries, distance to which is greater than the distance to exit boundary
        // Using -FLT_MAX as the distance to these boundaries will result in skipping them:
        b4IsCorrectIntersectionFlag = b4IsCorrectIntersectionFlag && ( f4DistToBoundaries < (fDistToExitBoundary - 1e-4) );
        f4DistToBoundaries = b4IsCorrectIntersectionFlag * f4DistToBoundaries + 
                            !b4IsCorrectIntersectionFlag * float4(-FLT_MAX, -FLT_MAX, -FLT_MAX, -FLT_MAX);

        float fFirstIntersecDist = 0;
        fFirstIntersecDist = max(fFirstIntersecDist, f4DistToBoundaries.x);
        fFirstIntersecDist = max(fFirstIntersecDist, f4DistToBoundaries.y);
        fFirstIntersecDist = max(fFirstIntersecDist, f4DistToBoundaries.z);
        fFirstIntersecDist = max(fFirstIntersecDist, f4DistToBoundaries.w);
        
        // The code above is equivalent to the following lines:
        // fFirstIntersecDist = fDistToLeftBoundary   < fDistToBoundary-1e-4 ? max(fFirstIntersecDist, fDistToLeftBoundary)   : fFirstIntersecDist;
        // fFirstIntersecDist = fDistToBottomBoundary < fDistToBoundary-1e-4 ? max(fFirstIntersecDist, fDistToBottomBoundary) : fFirstIntersecDist;
        // fFirstIntersecDist = fDistToRightBoundary  < fDistToBoundary-1e-4 ? max(fFirstIntersecDist, fDistToRightBoundary)  : fFirstIntersecDist;
        // fFirstIntersecDist = fDistToTopBoundary    < fDistToBoundary-1e-4 ? max(fFirstIntersecDist, fDistToTopBoundary)    : fFirstIntersecDist;

        // Now we can compute entry point:
        f2EntryPoint = g_LightAttribs.f4LightScreenPos.xy + f2RayDir * fFirstIntersecDist;

        // For invalid rays, coordinates are outside [-1,1]x[-1,1] area
        // and such rays will be discarded
        //
        //       g_LightAttribs.f4LightScreenPos
        //             *
        //              \|
        //               \-f2EntryPoint
        //               |\
        //               | \  f2ExitPoint 
        //               |__\/___
        //               |       |
        //               |       |
        //               |_______|
        //
    }

    return f2EntryPoint;
}

float4 GenerateSliceEndpointsPS(SScreenSizeQuadVSOutput In) : SV_Target
{
    float2 f2UV = ProjToUV(In.m_f2PosPS);

    // Note that due to the rasterization rules, UV coordinates are biased by 0.5 texel size.
    //
    //      0.5     1.5     2.5     3.5
    //   |   X   |   X   |   X   |   X   |     ....       
    //   0       1       2       3       4   f2UV * TexDim
    //   X - locations where rasterization happens
    //
    // We need to remove this offset. Also clamp to [0,1] to fix fp32 precision issues
    float fEpipolarSlice = saturate(f2UV.x - 0.5f / (float)NUM_EPIPOLAR_SLICES);

    // fEpipolarSlice now lies in the range [0, 1 - 1/NUM_EPIPOLAR_SLICES]
    // 0 defines location in exacatly left top corner, 1 - 1/NUM_EPIPOLAR_SLICES defines
    // position on the top boundary next to the top left corner
    uint uiBoundary = clamp(floor( fEpipolarSlice * 4 ), 0, 3);
    float fPosOnBoundary = frac( fEpipolarSlice * 4 );

    //             <------
    //   +1   0,1___________0.75
    //          |     3     |
    //        | |           | A
    //        | |0         2| |
    //        V |           | |
    //   -1     |_____1_____|
    //       0.25  ------>  0.5
    //
    //         -1          +1
    //

    //                                   Left             Bottom           Right              Top   
    float4 f4BoundaryXPos = float4(               0, fPosOnBoundary,                1, 1-fPosOnBoundary);
    float4 f4BoundaryYPos = float4( 1-fPosOnBoundary,              0,  fPosOnBoundary,                1);
    bool4 b4BoundaryFlags = bool4( uiBoundary.xxxx == uint4(0,1,2,3) );
    // Select the right coordinates for the boundary
    float2 f2ExitPointPosOnBnd = float2( dot(f4BoundaryXPos, b4BoundaryFlags), dot(f4BoundaryYPos, b4BoundaryFlags) );
    // Note that in fact the outermost visible screen pixels do not lie exactly on the boundary (+1 or -1), but are biased by
    // 0.5 screen pixel size inwards. Using these adjusted boundaries improves precision and results in
    // samller number of pixels which require inscattering correction
    float4 f4OutermostScreenPixelCoords = GetOutermostScreenPixelCoords();// xyzw = (left, bottom, right, top)
    float2 f2ExitPoint = lerp(f4OutermostScreenPixelCoords.xy, f4OutermostScreenPixelCoords.zw, f2ExitPointPosOnBnd);
    // GetEpipolarLineEntryPoint() gets exit point on SHRINKED boundary
    float2 f2EntryPoint = GetEpipolarLineEntryPoint(f2ExitPoint);

#if OPTIMIZE_SAMPLE_LOCATIONS
    // If epipolar slice is not invisible, advance its exit point if necessary
    // Recall that all correct entry points are completely inside the [-1,1]x[-1,1] area
    if( all(abs(f2EntryPoint) < 1) )
    {
        // Compute length of the epipolar line in screen pixels:
        float fEpipolarSliceScreenLen = length( (f2ExitPoint - f2EntryPoint) * SCREEN_RESLOUTION.xy / 2 );
        // If epipolar line is too short, update epipolar line exit point to provide 1:1 texel to screen pixel correspondence:
        f2ExitPoint = f2EntryPoint + (f2ExitPoint - f2EntryPoint) * max((float)MAX_SAMPLES_IN_SLICE / fEpipolarSliceScreenLen, 1);
    }
#endif

    return float4(f2EntryPoint, f2ExitPoint);
}


void GenerateCoordinateTexturePS(SScreenSizeQuadVSOutput In, 
                                 out float2 f2XY : SV_Target0,
                                 out float fCamSpaceZ : SV_Target1)

{
    float4 f4SliceEndPoints = g_tex2DSliceEndPoints.Load( int3(In.m_f4Pos.y,0,0) );
    
    // If slice entry point is outside [-1,1]x[-1,1] area, the slice is completely invisible
    // and we can skip it from further processing.
    // Note that slice exit point can lie outside the screen, if sample locations are optimized
    // Recall that all correct entry points are completely inside the [-1,1]x[-1,1] area
    if( any(abs(f4SliceEndPoints.xy) > 1) )
    {
        // Discard invalid slices
        // Such slices will not be marked in the stencil and as a result will always be skipped
        discard;
    }

    float2 f2UV = ProjToUV(In.m_f2PosPS);

    // Note that due to the rasterization rules, UV coordinates are biased by 0.5 texel size.
    //
    //      0.5     1.5     2.5     3.5
    //   |   X   |   X   |   X   |   X   |     ....       
    //   0       1       2       3       4   f2UV * f2TexDim
    //   X - locations where rasterization happens
    //
    // We need remove this offset:
    float fSamplePosOnEpipolarLine = f2UV.x - 0.5f / (float)MAX_SAMPLES_IN_SLICE;
    // fSamplePosOnEpipolarLine is now in the range [0, 1 - 1/MAX_SAMPLES_IN_SLICE]
    // We need to rescale it to be in [0, 1]
    fSamplePosOnEpipolarLine *= (float)MAX_SAMPLES_IN_SLICE / ((float)MAX_SAMPLES_IN_SLICE-1.f);
    fSamplePosOnEpipolarLine = saturate(fSamplePosOnEpipolarLine);

    // Compute interpolated position between entry and exit points:
    f2XY = lerp(f4SliceEndPoints.xy, f4SliceEndPoints.zw, fSamplePosOnEpipolarLine);
    // All correct entry points are completely inside the [-1,1]x[-1,1] area
    if( any(abs(f2XY) > 1) )
    {
        // Discard pixels that fall behind the screen
        // This can happen if slice exit point was optimized
        discard;
    }

    // Compute camera space z for current location
    fCamSpaceZ = GetCamSpaceZ( ProjToUV(f2XY) );
};


technique11 GenerateCoordinateTexture
{
    pass
    {
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        // Increase stencil value for all valid rays
        SetDepthStencilState( DSS_NoDepthTestIncrStencil, 0 );

        SetVertexShader( CompileShader(vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader(ps_5_0, GenerateCoordinateTexturePS() ) );
    }
}

static const float4 g_f4IncorrectSliceUVDirAndStart = float4(-10000, -10000, 0, 0);
float4 RenderSliceUVDirInShadowMapTexturePS(SScreenSizeQuadVSOutput In) : SV_Target
{
    uint uiSliceInd = In.m_f4Pos.x;
    // Load epipolar slice endpoints
    float4 f4SliceEndpoints = g_tex2DSliceEndPoints.Load(  uint3(uiSliceInd,0,0) );
    // All correct entry points are completely inside the [-1,1]x[-1,1] area
    if( any( abs(f4SliceEndpoints.xy) > 1 ) )
        return g_f4IncorrectSliceUVDirAndStart;

    // Reconstruct slice exit point position in world space
    float3 f3SliceExitWS = ProjSpaceXYToWorldSpace(f4SliceEndpoints.zw);
    float3 f3DirToSliceExitFromCamera = normalize(f3SliceExitWS - g_CameraAttribs.f4CameraPos.xyz);
    // Compute epipolar slice normal. If light source is outside the screen, the vectors could be collinear
    float3 f3SliceNormal = cross(f3DirToSliceExitFromCamera, g_LightAttribs.f4DirOnLight.xyz);
    if( length(f3SliceNormal) < 1e-5 )
        return g_f4IncorrectSliceUVDirAndStart;
    f3SliceNormal = normalize(f3SliceNormal);

    // Intersect epipolar slice plane with the light projection plane.
    float3 f3IntersecOrig, f3IntersecDir;

#if LIGHT_TYPE == LIGHT_TYPE_POINT || LIGHT_TYPE == LIGHT_TYPE_SPOT
    // We can use any plane parallel to the light furstum near clipping plane. The exact distance from the plane
    // to light source does not matter since the projection will always be the same:
    float3 f3LightProjPlaneCenter = g_LightAttribs.f4LightWorldPos.xyz + g_LightAttribs.f4SpotLightAxisAndCosAngle.xyz;
#endif
    
    if( !PlanePlaneIntersect( 
#if LIGHT_TYPE == LIGHT_TYPE_DIRECTIONAL
                             // In case light is directional, the matrix is not perspective, so location
                             // of the light projection plane in space as well as camera position do not matter at all
                             f3SliceNormal, 0,
                             -g_LightAttribs.f4DirOnLight.xyz, 0,
#elif LIGHT_TYPE == LIGHT_TYPE_POINT || LIGHT_TYPE == LIGHT_TYPE_SPOT
                             f3SliceNormal, g_CameraAttribs.f4CameraPos.xyz,
                             g_LightAttribs.f4SpotLightAxisAndCosAngle.xyz, f3LightProjPlaneCenter,
#endif
                             f3IntersecOrig, f3IntersecDir ) )
    {
        // There is no correct intersection between planes in barelly possible case which
        // requires that:
        // 1. DirOnLight is exacatly parallel to light projection plane
        // 2. The slice is parallel to light projection plane
        return g_f4IncorrectSliceUVDirAndStart;
    }
    // Important: ray direction f3IntersecDir is computed as a cross product of 
    // slice normal and light direction (or spot light axis). As a result, the ray
    // direction is always correct for valid slices. 

    // Now project the line onto the light space UV coordinates. 
    // Get two points on the line:
    float4 f4P0 = float4( f3IntersecOrig, 1 );
    float4 f4P1 = float4( f3IntersecOrig + f3IntersecDir * max(1, length(f3IntersecOrig)), 1 );
    // Transform the points into the shadow map UV:
    f4P0 = mul( f4P0, g_LightAttribs.mWorldToLightProjSpace); 
    f4P0 /= f4P0.w;
    f4P1 = mul( f4P1, g_LightAttribs.mWorldToLightProjSpace); 
    f4P1 /= f4P1.w;
    // Note that division by w is not really necessary because both points lie in the plane 
    // parallel to light projection and thus have the same w value.
    float2 f2SliceDir = ProjToUV(f4P1.xy) - ProjToUV(f4P0.xy);
    
    // The following method also works:
    // Since we need direction only, we can use any origin. The most convinient is
    // f3LightProjPlaneCenter which projects into (0.5,0.5):
    //float4 f4SliceUVDir = mul( float4(f3LightProjPlaneCenter + f3IntersecDir, 1), g_LightAttribs.mWorldToLightProjSpace);
    //f4SliceUVDir /= f4SliceUVDir.w;
    //float2 f2SliceDir = ProjToUV(f4SliceUVDir.xy) - 0.5;

    f2SliceDir /= max(abs(f2SliceDir.x), abs(f2SliceDir.y));

    float2 f2SliceOriginUV = g_LightAttribs.f4CameraUVAndDepthInShadowMap.xy;
    
#if LIGHT_TYPE == LIGHT_TYPE_POINT || LIGHT_TYPE == LIGHT_TYPE_SPOT
    bool bIsCamInsideCone = dot( -g_LightAttribs.f4DirOnLight.xyz, g_LightAttribs.f4SpotLightAxisAndCosAngle.xyz) > g_LightAttribs.f4SpotLightAxisAndCosAngle.w;
    if( !bIsCamInsideCone )
    {
        // If camera is outside the cone, all the rays in slice hit the same cone side, which means that they
        // all start from projection of this rib onto the shadow map

        // Intesect the ray with the light cone:
        float2 f2ConeIsecs = 
            RayConeIntersect(g_LightAttribs.f4LightWorldPos.xyz, g_LightAttribs.f4SpotLightAxisAndCosAngle.xyz, g_LightAttribs.f4SpotLightAxisAndCosAngle.w,
                             f3IntersecOrig, f3IntersecDir);
        
        if( any(f2ConeIsecs == -FLT_MAX) )
            return g_f4IncorrectSliceUVDirAndStart;
        // Now select the first intersection with the cone along the ray
        float4 f4RayConeIsec = float4( f3IntersecOrig + min(f2ConeIsecs.x, f2ConeIsecs.y) * f3IntersecDir, 1 );
        // Project this intersection:
        f4RayConeIsec = mul( f4RayConeIsec, g_LightAttribs.mWorldToLightProjSpace);
        f4RayConeIsec /= f4RayConeIsec.w;

        f2SliceOriginUV = ProjToUV(f4RayConeIsec.xy);
    }
#endif

    return float4(f2SliceDir, f2SliceOriginUV);
}

technique11 RenderSliceUVDirInShadowMapTexture
{
    pass p0
    {
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        // Only interpolation samples will not be discarded and increase the stencil value
        SetDepthStencilState( DSS_NoDepthTest, 0 );

        SetVertexShader( CompileShader(vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader(ps_5_0, RenderSliceUVDirInShadowMapTexturePS() ) );
    }
}

// Note that min/max shadow map does not contain finest resolution level
// The first level it contains corresponds to step == 2
MIN_MAX_DATA_FORMAT InitializeMinMaxShadowMapPS(SScreenSizeQuadVSOutput In) : SV_Target
{
    uint uiSliceInd = In.m_f4Pos.y;
    // Load slice direction in shadow map
    float4 f4SliceUVDirAndOrigin = g_tex2DSliceUVDirAndOrigin.Load( uint3(uiSliceInd,0,0) );
    // Calculate current sample position on the ray
    float2 f2CurrUV = f4SliceUVDirAndOrigin.zw + f4SliceUVDirAndOrigin.xy * floor(In.m_f4Pos.x) * 2.f * g_PPAttribs.m_f2ShadowMapTexelSize;
    
    // Gather 8 depths which will be used for PCF filtering for this sample and its immediate neighbor 
    // along the epipolar slice
    // Note that if the sample is located outside the shadow map, Gather() will return 0 as 
    // specified by the samLinearBorder0. As a result volumes outside the shadow map will always be lit
    float4 f4Depths = g_tex2DLightSpaceDepthMap.Gather(samLinearBorder0, f2CurrUV);
    // Shift UV to the next sample along the epipolar slice:
    f2CurrUV += f4SliceUVDirAndOrigin.xy * g_PPAttribs.m_f2ShadowMapTexelSize;
    float4 f4NeighbDepths = g_tex2DLightSpaceDepthMap.Gather(samLinearBorder0, f2CurrUV);

#if ACCEL_STRUCT == ACCEL_STRUCT_MIN_MAX_TREE
    
    float4 f4MinDepth = min(f4Depths, f4NeighbDepths);
    f4MinDepth.xy = min(f4MinDepth.xy, f4MinDepth.zw);
    f4MinDepth.x = min(f4MinDepth.x, f4MinDepth.y);

    float4 f4MaxDepth = max(f4Depths, f4NeighbDepths);
    f4MaxDepth.xy = max(f4MaxDepth.xy, f4MaxDepth.zw);
    f4MaxDepth.x = max(f4MaxDepth.x, f4MaxDepth.y);

    return float2(f4MinDepth.x, f4MaxDepth.x);

#elif ACCEL_STRUCT == ACCEL_STRUCT_BV_TREE
    
    // Calculate min/max depths for current and next sampling locations
    float2 f2MinDepth = min(f4Depths.xy, f4Depths.zw);
    float fMinDepth = min(f2MinDepth.x, f2MinDepth.y);
    float2 f2MaxDepth = max(f4Depths.xy, f4Depths.zw);
    float fMaxDepth = max(f2MaxDepth.x, f2MaxDepth.y);
    float2 f2NeighbMinDepth = min(f4NeighbDepths.xy, f4NeighbDepths.zw);
    float fNeighbMinDepth = min(f2NeighbMinDepth.x, f2NeighbMinDepth.y);
    float2 f2NeighbMaxDepth = max(f4NeighbDepths.xy, f4NeighbDepths.zw);
    float fNeighbMaxDepth = max(f2NeighbMaxDepth.x, f2NeighbMaxDepth.y);

    return float4( fMinDepth, fMaxDepth, fNeighbMinDepth, fNeighbMaxDepth );

#endif
}

// 1D min max mip map is arranged as follows:
//
//    g_MiscParams.ui4SrcDstMinMaxLevelOffset.x
//     |
//     |      g_MiscParams.ui4SrcDstMinMaxLevelOffset.z
//     |_______|____ __
//     |       |    |  |
//     |       |    |  |
//     |       |    |  |
//     |       |    |  |
//     |_______|____|__|
//     |<----->|<-->|
//         |     |
//         |    uiMinMaxShadowMapResolution/
//      uiMinMaxShadowMapResolution/2
//                         
MIN_MAX_DATA_FORMAT ComputeMinMaxShadowMapLevelPS(SScreenSizeQuadVSOutput In) : SV_Target
{
    uint2 uiDstSampleInd = uint2(In.m_f4Pos.xy);
    uint2 uiSrcSample0Ind = uint2(g_MiscParams.ui4SrcDstMinMaxLevelOffset.x + (uiDstSampleInd.x - g_MiscParams.ui4SrcDstMinMaxLevelOffset.z)*2, uiDstSampleInd.y);
    uint2 uiSrcSample1Ind = uiSrcSample0Ind + uint2(1,0);
    MIN_MAX_DATA_FORMAT fnMinMaxDepth0 = g_tex2DMinMaxLightSpaceDepth.Load( uint3(uiSrcSample0Ind,0) );
    MIN_MAX_DATA_FORMAT fnMinMaxDepth1 = g_tex2DMinMaxLightSpaceDepth.Load( uint3(uiSrcSample1Ind,0) );
#if ACCEL_STRUCT == ACCEL_STRUCT_MIN_MAX_TREE
    float2 f2MinMaxDepth;
    f2MinMaxDepth.x = min(fnMinMaxDepth0.x, fnMinMaxDepth1.x);
    f2MinMaxDepth.y = max(fnMinMaxDepth0.y, fnMinMaxDepth1.y);
    return f2MinMaxDepth;
#elif ACCEL_STRUCT == ACCEL_STRUCT_BV_TREE

    float4 f4MinMaxDepth;
    //
    //                fnMinMaxDepth0.z        fnMinMaxDepth1.z
    //                      *                       *
    //                                 *
    //           *              fnMinMaxDepth1.x
    //  fnMinMaxDepth0.x
    // Start by drawing line from the first to the last points:
    f4MinMaxDepth.x = fnMinMaxDepth0.x;
    f4MinMaxDepth.z = fnMinMaxDepth1.z;
    // Check if second and first points are above the line and update its ends if required 
    float fDelta = lerp(f4MinMaxDepth.x, f4MinMaxDepth.z, 1.f/3.f) - fnMinMaxDepth0.z;
    f4MinMaxDepth.x -= 3.f/2.f * max(fDelta, 0);
    fDelta = lerp(f4MinMaxDepth.x, f4MinMaxDepth.z, 2.f/3.f) - fnMinMaxDepth1.x;
    f4MinMaxDepth.z -= 3.f/2.f * max(fDelta, 0);

    //
    //                fnMinMaxDepth0.w        fnMinMaxDepth1.w
    //                      *                       *
    //                                 *
    //           *              fnMinMaxDepth1.y
    //  fnMinMaxDepth0.y  
    f4MinMaxDepth.y = fnMinMaxDepth0.y;
    f4MinMaxDepth.w = fnMinMaxDepth1.w;
    fDelta = fnMinMaxDepth0.w - lerp(f4MinMaxDepth.y, f4MinMaxDepth.w, 1.f/3.f);
    f4MinMaxDepth.y += 3.f/2.f * max(fDelta, 0);
    fDelta = fnMinMaxDepth1.y - lerp(f4MinMaxDepth.y, f4MinMaxDepth.w, 2.f/3.f);
    f4MinMaxDepth.w += 3.f/2.f * max(fDelta, 0);
    
    // Check if the horizontal bounding box is better
    float2 f2MaxDepth = max(fnMinMaxDepth0.yw, fnMinMaxDepth1.yw);
    float fMaxDepth = max(f2MaxDepth.x, f2MaxDepth.y);

    float2 f2MinDepth = min(fnMinMaxDepth0.xz, fnMinMaxDepth1.xz);
    float fMinDepth = min(f2MinDepth.x, f2MinDepth.y);

    float fThreshold = (fMaxDepth-fMinDepth) * 0.01;
    if( any(f4MinMaxDepth.yw > fMaxDepth + fThreshold) )
        f4MinMaxDepth.yw = fMaxDepth;

    if( any(f4MinMaxDepth.xz < fMinDepth - fThreshold) )
        f4MinMaxDepth.xz = fMinDepth;

    return f4MinMaxDepth;
#endif
}

technique11 BuildMinMaxMipMap
{
    pass PInitializeMinMaxShadowMap
    {
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        // Only interpolation samples will not be discarded and increase the stencil value
        SetDepthStencilState( DSS_NoDepthTest, 0 );

        SetVertexShader( CompileShader(vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader(ps_5_0, InitializeMinMaxShadowMapPS() ) );
    }

    pass PComputeMinMaxShadowMapLevel
    {
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        // Only interpolation samples will not be discarded and increase the stencil value
        SetDepthStencilState( DSS_NoDepthTest, 0 );

        SetVertexShader( CompileShader(vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader(ps_5_0, ComputeMinMaxShadowMapLevelPS() ) );
    }
}


void MarkRayMarchingSamplesInStencilPS(SScreenSizeQuadVSOutput In)
{
    uint2 ui2InterpolationSources = g_tex2DInterpolationSource.Load( uint3(In.m_f4Pos.xy,0) );
    // Ray marching samples are interpolated from themselves, so it is easy to detect them:
    if( ui2InterpolationSources.x != ui2InterpolationSources.y )
          discard;
}

technique11 MarkRayMarchingSamplesInStencil
{
    pass
    {
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        // Only interpolation samples will not be discarded and increase the stencil value
        SetDepthStencilState( DSS_NoDepth_StEqual_IncrStencil, 1 );

        SetVertexShader( CompileShader(vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader(ps_5_0, MarkRayMarchingSamplesInStencilPS() ) );
    }
}

float3 InterpolateIrradiancePS(SScreenSizeQuadVSOutput In) : SV_Target
{
    uint uiSampleInd = In.m_f4Pos.x;
    uint uiSliceInd = In.m_f4Pos.y;
    // Get interpolation sources
    uint2 ui2InterpolationSources = g_tex2DInterpolationSource.Load( uint3(uiSampleInd, uiSliceInd, 0) );
    float fInterpolationPos = float(uiSampleInd - ui2InterpolationSources.x) / float( max(ui2InterpolationSources.y - ui2InterpolationSources.x,1) );

    float3 f3Src0 = g_tex2DInitialInsctrIrradiance.Load( uint3(ui2InterpolationSources.x, uiSliceInd, 0) );
    float3 f3Src1 = g_tex2DInitialInsctrIrradiance.Load( uint3(ui2InterpolationSources.y, uiSliceInd, 0));

    // Ray marching samples are interpolated from themselves
    return lerp(f3Src0, f3Src1, fInterpolationPos);
}

technique11 InterpolateIrradiance
{
    pass
    {
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        SetDepthStencilState( DSS_NoDepthTest, 0 );

        SetVertexShader( CompileShader(vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader(ps_5_0, InterpolateIrradiancePS() ) );
    }
}


float3 PerformBilateralInterpolation(in float2 f2BilinearWeights,
                                     in float2 f2LeftBottomSrcTexelUV,
                                     in float4 f4SrcLocationsCamSpaceZ,
                                     in float  fFilteringLocationCamSpaceZ,
                                     in Texture2D<float3> tex2DSrcTexture,
                                     in float2 f2SrcTexDim,
                                     in SamplerState Sampler)
{
    // Initialize bilateral weights with bilinear:
    float4 f4BilateralWeights = 
        //Offset:       (x=0,y=1)            (x=1,y=1)             (x=1,y=0)               (x=0,y=0)
        float4(1 - f2BilinearWeights.x, f2BilinearWeights.x,   f2BilinearWeights.x, 1 - f2BilinearWeights.x) * 
        float4(    f2BilinearWeights.y, f2BilinearWeights.y, 1-f2BilinearWeights.y, 1 - f2BilinearWeights.y);

    // Compute depth weights in a way that if the difference is less than the threshold, the weight is 1 and
    // the weights fade out to 0 as the difference becomes larger than the threshold:
    float4 f4DepthWeights = saturate( g_PPAttribs.m_fRefinementThreshold / max( abs(fFilteringLocationCamSpaceZ-f4SrcLocationsCamSpaceZ), g_PPAttribs.m_fRefinementThreshold ) );
    // Note that if the sample is located outside the [-1,1]x[-1,1] area, the sample is invalid and fCurrCamSpaceZ == fInvalidCoordinate
    // Depth weight computed for such sample will be zero
    f4DepthWeights = pow(f4DepthWeights, 4);
    // Multiply bilinear weights with the depth weights:
    f4BilateralWeights *= f4DepthWeights;
    // Compute summ weight
    float fTotalWeight = dot(f4BilateralWeights, float4(1,1,1,1));
    
    float3 f3ScatteredLight = 0;
    [branch]
    if( g_PPAttribs.m_bCorrectScatteringAtDepthBreaks && fTotalWeight < 1e-2 )
    {
        // Discarded pixels will keep 0 value in stencil and will be later
        // processed to correct scattering
        discard;
    }
    else
    {
        // Normalize weights
        f4BilateralWeights /= fTotalWeight;

        // We now need to compute the following weighted summ:
        //f3ScatteredLight = 
        //    f4BilateralWeights.x * tex2DSrcTexture.SampleLevel(samPoint, f2ScatteredColorIJ, 0, int2(0,1)) +
        //    f4BilateralWeights.y * tex2DSrcTexture.SampleLevel(samPoint, f2ScatteredColorIJ, 0, int2(1,1)) +
        //    f4BilateralWeights.z * tex2DSrcTexture.SampleLevel(samPoint, f2ScatteredColorIJ, 0, int2(1,0)) +
        //    f4BilateralWeights.w * tex2DSrcTexture.SampleLevel(samPoint, f2ScatteredColorIJ, 0, int2(0,0));

        // We will use hardware to perform bilinear filtering and get these values using just two bilinear fetches:

        // Offset:                  (x=1,y=0)                (x=1,y=0)               (x=0,y=0)
        float fRow0UOffset = f4BilateralWeights.z / max(f4BilateralWeights.z + f4BilateralWeights.w, 0.001);
        fRow0UOffset /= f2SrcTexDim.x;
        float3 f3Row0WeightedCol = 
            (f4BilateralWeights.z + f4BilateralWeights.w) * 
                tex2DSrcTexture.SampleLevel(Sampler, f2LeftBottomSrcTexelUV + float2(fRow0UOffset, 0), 0, int2(0,0));

        // Offset:                  (x=1,y=1)                 (x=0,y=1)              (x=1,y=1)
        float fRow1UOffset = f4BilateralWeights.y / max(f4BilateralWeights.x + f4BilateralWeights.y, 0.001);
        fRow1UOffset /= f2SrcTexDim.x;
        float3 f3Row1WeightedCol = 
            (f4BilateralWeights.x + f4BilateralWeights.y) * 
                tex2DSrcTexture.SampleLevel(Sampler, f2LeftBottomSrcTexelUV + float2(fRow1UOffset, 0 ), 0, int2(0,1));
        
        f3ScatteredLight = f3Row0WeightedCol + f3Row1WeightedCol;
    }

    return f3ScatteredLight;
}


float3 UnwarpEpipolarInsctrImage( SScreenSizeQuadVSOutput In, in float fCamSpaceZ )
{
    // Compute direction of the ray going from the light through the pixel
    float2 f2RayDir = normalize( In.m_f2PosPS - g_LightAttribs.f4LightScreenPos.xy );

    // Find, which boundary the ray intersects. For this, we will 
    // find which two of four half spaces the f2RayDir belongs to
    // Each of four half spaces is produced by the line connecting one of four
    // screen corners and the current pixel:
    //    ________________        _______'________           ________________           
    //   |'            . '|      |      '         |         |                |          
    //   | '       . '    |      |     '          |      .  |                |          
    //   |  '  . '        |      |    '           |        '|.        hs1    |          
    //   |   *.           |      |   *     hs0    |         |  '*.           |          
    //   |  '   ' .       |      |  '             |         |      ' .       |          
    //   | '        ' .   |      | '              |         |          ' .   |          
    //   |'____________ '_|      |'_______________|         | ____________ '_.          
    //                           '                                             '
    //                           ________________  .        '________________  
    //                           |             . '|         |'               | 
    //                           |   hs2   . '    |         | '              | 
    //                           |     . '        |         |  '             | 
    //                           | . *            |         |   *            | 
    //                         . '                |         |    '           | 
    //                           |                |         | hs3 '          | 
    //                           |________________|         |______'_________| 
    //                                                              '
    // The equations for the half spaces are the following:
    //bool hs0 = (In.m_f2PosPS.x - (-1)) * f2RayDir.y < f2RayDir.x * (In.m_f2PosPS.y - (-1));
    //bool hs1 = (In.m_f2PosPS.x -  (1)) * f2RayDir.y < f2RayDir.x * (In.m_f2PosPS.y - (-1));
    //bool hs2 = (In.m_f2PosPS.x -  (1)) * f2RayDir.y < f2RayDir.x * (In.m_f2PosPS.y -  (1));
    //bool hs3 = (In.m_f2PosPS.x - (-1)) * f2RayDir.y < f2RayDir.x * (In.m_f2PosPS.y -  (1));
    // Note that in fact the outermost visible screen pixels do not lie exactly on the boundary (+1 or -1), but are biased by
    // 0.5 screen pixel size inwards. Using these adjusted boundaries improves precision and results in
    // smaller number of pixels which require inscattering correction
    float4 f4Boundaries = GetOutermostScreenPixelCoords();//left, bottom, right, top
    float4 f4HalfSpaceEquationTerms = (In.m_f2PosPS.xxyy - f4Boundaries.xzyw/*float4(-1,1,-1,1)*/) * f2RayDir.yyxx;
    bool4 b4HalfSpaceFlags = f4HalfSpaceEquationTerms.xyyx < f4HalfSpaceEquationTerms.zzww;

    // Now compute mask indicating which of four sectors the f2RayDir belongs to and consiquently
    // which border the ray intersects:
    //    ________________ 
    //   |'            . '|         0 : hs3 && !hs0
    //   | '   3   . '    |         1 : hs0 && !hs1
    //   |  '  . '        |         2 : hs1 && !hs2
    //   |0  *.       2   |         3 : hs2 && !hs3
    //   |  '   ' .       |
    //   | '   1    ' .   |
    //   |'____________ '_|
    //
    bool4 b4SectorFlags = b4HalfSpaceFlags.wxyz && !b4HalfSpaceFlags.xyzw;
    // Note that b4SectorFlags now contains true (1) for the exit boundary and false (0) for 3 other

    // Compute distances to boundaries according to following lines:
    //float fDistToLeftBoundary   = abs(f2RayDir.x) > 1e-5 ? ( -1 - g_LightAttribs.f4LightScreenPos.x) / f2RayDir.x : -FLT_MAX;
    //float fDistToBottomBoundary = abs(f2RayDir.y) > 1e-5 ? ( -1 - g_LightAttribs.f4LightScreenPos.y) / f2RayDir.y : -FLT_MAX;
    //float fDistToRightBoundary  = abs(f2RayDir.x) > 1e-5 ? (  1 - g_LightAttribs.f4LightScreenPos.x) / f2RayDir.x : -FLT_MAX;
    //float fDistToTopBoundary    = abs(f2RayDir.y) > 1e-5 ? (  1 - g_LightAttribs.f4LightScreenPos.y) / f2RayDir.y : -FLT_MAX;
    float4 f4DistToBoundaries = ( f4Boundaries - g_LightAttribs.f4LightScreenPos.xyxy ) / (f2RayDir.xyxy + float4( abs(f2RayDir.xyxy)<1e-6 ) );
    // Select distance to the exit boundary:
    float fDistToExitBoundary = dot( b4SectorFlags, f4DistToBoundaries );
    // Compute exit point on the boundary:
    float2 f2ExitPoint = g_LightAttribs.f4LightScreenPos.xy + f2RayDir * fDistToExitBoundary;

    // Compute epipolar slice for each boundary:
    //if( LeftBoundary )
    //    fEpipolarSlice = 0.0  - (LeftBoudaryIntersecPoint.y   -   1 )/2 /4;
    //else if( BottomBoundary )
    //    fEpipolarSlice = 0.25 + (BottomBoudaryIntersecPoint.x - (-1))/2 /4;
    //else if( RightBoundary )
    //    fEpipolarSlice = 0.5  + (RightBoudaryIntersecPoint.y  - (-1))/2 /4;
    //else if( TopBoundary )
    //    fEpipolarSlice = 0.75 - (TopBoudaryIntersecPoint.x      - 1 )/2 /4;
    float4 f4EpipolarSlice = float4(0, 0.25, 0.5, 0.75) + 
        saturate( (f2ExitPoint.yxyx - f4Boundaries.wxyz)*float4(-1, +1, +1, -1) / (f4Boundaries.wzwz - f4Boundaries.yxyx) ) / 4.0;
    // Select the right value:
    float fEpipolarSlice = dot(b4SectorFlags, f4EpipolarSlice);

    // Load epipolar endpoints. Note that slice 0 is stored in the first
    // texel which has U coordinate shifted by 0.5 texel size
    // (search for "fEpipolarSlice = saturate(f2UV.x - 0.5f / (float)NUM_EPIPOLAR_SLICES)"):
    fEpipolarSlice = saturate(fEpipolarSlice + 0.5f/(float)NUM_EPIPOLAR_SLICES);
    // Note also that this offset dramatically reduces the number of samples, for which correction pass is
    // required (the correction pass becomes more than 2x times faster!!!)
    float4 f4SliceEndpoints = g_tex2DSliceEndPoints.SampleLevel( samLinearClamp, float2(fEpipolarSlice, 0.5), 0 );
    f2ExitPoint = f4SliceEndpoints.zw;
    float2 f2EntryPoint = f4SliceEndpoints.xy;


    float2 f2EpipolarSliceDir = f2ExitPoint - f2EntryPoint;
    float fEpipolarSliceLen = length(f2EpipolarSliceDir);
    f2EpipolarSliceDir /= max(fEpipolarSliceLen, 1e-6);

    // Project current pixel onto the epipolar slice
    float fSamplePosOnEpipolarLine = dot((In.m_f2PosPS - f2EntryPoint.xy), f2EpipolarSliceDir) / fEpipolarSliceLen;
    // Rescale the sample position
    // Note that the first sample on slice is exactly the f2EntryPoint.xy, while the last sample is exactly the f2ExitPoint
    // (search for "fSamplePosOnEpipolarLine *= (float)MAX_SAMPLES_IN_SLICE / ((float)MAX_SAMPLES_IN_SLICE-1.f)")
    // As usual, we also need to add offset by 0.5 texel size
    float fScatteredColorU = fSamplePosOnEpipolarLine * ((float)MAX_SAMPLES_IN_SLICE-1) / (float)MAX_SAMPLES_IN_SLICE + 0.5f/(float)MAX_SAMPLES_IN_SLICE;

    // We need to manually perform bilateral filtering of the scattered radiance texture to
    // eliminate artifacts at depth discontinuities
    float2 f2ScatteredColorUV = float2(fScatteredColorU, fEpipolarSlice);
    float2 f2ScatteredColorTexDim;
    g_tex2DScatteredColor.GetDimensions(f2ScatteredColorTexDim.x, f2ScatteredColorTexDim.y);
    // Offset by 0.5 is essential, because texel centers have UV coordinates that are offset by half the texel size
    float2 f2ScatteredColorUVScaled = f2ScatteredColorUV.xy * f2ScatteredColorTexDim.xy - float2(0.5, 0.5);
    float2 f2ScatteredColorIJ = floor(f2ScatteredColorUVScaled);
    // Get bilinear filtering weights
    float2 f2BilinearWeights = f2ScatteredColorUVScaled - f2ScatteredColorIJ;
    // Get texture coordinates of the left bottom source texel. Again, offset by 0.5 is essential
    // to align with texel center
    f2ScatteredColorIJ = (f2ScatteredColorIJ + float2(0.5, 0.5)) / f2ScatteredColorTexDim.xy;
    
    // Gather 4 camera space z values
    // Note that we need to bias f2ScatteredColorIJ by 0.5 texel size to get the required values
    //   _______ _______
    //  |       |       |
    //  |       |       |
    //  |_______X_______|  X gather location
    //  |       |       |
    //  |   *   |       |  * f2ScatteredColorIJ
    //  |_______|_______|
    //  |<----->|
    //     1/f2ScatteredColorTexDim.x
    float4 f4SrcLocationsCamSpaceZ = g_tex2DEpipolarCamSpaceZ.Gather(samLinearClamp, f2ScatteredColorIJ + float2(0.5, 0.5) / f2ScatteredColorTexDim.xy);
    // The values in f4SrcLocationsCamSpaceZ are arranged as follows:
    // f4SrcLocationsCamSpaceZ.x == g_tex2DEpipolarCamSpaceZ.SampleLevel(samPointClamp, f2ScatteredColorIJ, 0, int2(0,1))
    // f4SrcLocationsCamSpaceZ.y == g_tex2DEpipolarCamSpaceZ.SampleLevel(samPointClamp, f2ScatteredColorIJ, 0, int2(1,1))
    // f4SrcLocationsCamSpaceZ.z == g_tex2DEpipolarCamSpaceZ.SampleLevel(samPointClamp, f2ScatteredColorIJ, 0, int2(1,0))
    // f4SrcLocationsCamSpaceZ.w == g_tex2DEpipolarCamSpaceZ.SampleLevel(samPointClamp, f2ScatteredColorIJ, 0, int2(0,0))

    return PerformBilateralInterpolation(f2BilinearWeights, f2ScatteredColorIJ, f4SrcLocationsCamSpaceZ, fCamSpaceZ, g_tex2DScatteredColor, f2ScatteredColorTexDim, samLinearClamp /* Do not use wrap mode for epipolar slice! */);
}

float3 GetExtinction(float in_Dist)
{
    float3 vExtinction;
    // Use analytical expression for extinction (see "Rendering Outdoor Light Scattering in Real Time" by 
    // Hoffman and Preetham, p.27 and p.51) 
    vExtinction = exp( -(g_MediaParams.f4TotalRayleighBeta.rgb +  g_MediaParams.f4TotalMieBeta.rgb) * in_Dist );
    return vExtinction;
}

float3 GetAttenuatedBackgroundColor(SScreenSizeQuadVSOutput In, in float fDistToCamera )
{
    float3 f3BackgroundColor = 0;
    [branch]
    if( !g_PPAttribs.m_bShowLightingOnly )
    {
        f3BackgroundColor = g_tex2DColorBuffer.Load(int3(In.m_f4Pos.xy,0)).rgb;
        float3 f3Extinction = GetExtinction(fDistToCamera);
        f3BackgroundColor *= f3Extinction.rgb;
    }
    return f3BackgroundColor;
}

float3 GetAttenuatedBackgroundColor(SScreenSizeQuadVSOutput In)
{
    float3 f3WorldSpacePos = ProjSpaceXYToWorldSpace(In.m_f2PosPS.xy);
    float fDistToCamera = length(f3WorldSpacePos - g_CameraAttribs.f4CameraPos.xyz);
    return GetAttenuatedBackgroundColor(In, fDistToCamera);
}

float3 ApplyInscatteredRadiancePS(SScreenSizeQuadVSOutput In) : SV_Target
{
    float fCamSpaceZ = GetCamSpaceZ( ProjToUV(In.m_f2PosPS) );
    float3 f3InsctrIntegral = UnwarpEpipolarInsctrImage(In, fCamSpaceZ);

    float3 f3ReconstructedPosWS = ProjSpaceXYZToWorldSpace(float3(In.m_f2PosPS.xy, fCamSpaceZ));
    float3 f3EyeVector = f3ReconstructedPosWS.xyz - g_CameraAttribs.f4CameraPos.xyz;
    float fDistToCamera = length(f3EyeVector);
#if LIGHT_TYPE == LIGHT_TYPE_DIRECTIONAL
    f3EyeVector /= fDistToCamera;
    float3 f3InsctrColor = ApplyPhaseFunction(f3InsctrIntegral, dot(f3EyeVector, g_LightAttribs.f4DirOnLight.xyz));
#else
    float3 f3InsctrColor = f3InsctrIntegral;
#endif

    float3 f3BackgroundColor = GetAttenuatedBackgroundColor(In, fDistToCamera);
    return ToneMap(f3BackgroundColor + f3InsctrColor);
}

float3 UnwarpEpipolarInsctrImagePS( SScreenSizeQuadVSOutput In ) : SV_Target
{
    // Get camera space z of the current screen pixel
    float fCamSpaceZ = GetCamSpaceZ( ProjToUV(In.m_f2PosPS) );
    return UnwarpEpipolarInsctrImage( In, fCamSpaceZ );
}

technique11 ApplyInscatteredRadiance
{
    pass PAttenuateBackgroundAndApplyInsctr
    {
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        SetDepthStencilState( DSS_NoDepthTestIncrStencil, 0 );

        SetVertexShader( CompileShader(vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader(ps_5_0, UnwarpEpipolarInsctrImagePS() ) );
    }

    pass PUnwarpInsctr
    {
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        SetDepthStencilState( DSS_NoDepthTestIncrStencil, 0 );

        SetVertexShader( CompileShader(vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader(ps_5_0, ApplyInscatteredRadiancePS() ) );
    }
}

float3 UpscaleInscatteredRadiancePS(SScreenSizeQuadVSOutput In) : SV_Target
{
    float2 f2UV = ProjToUV(In.m_f2PosPS);

    // We need to manually perform bilateral filtering of the downscaled scattered radiance texture to
    // eliminate artifacts at depth discontinuities
    float2 f2DownscaledInsctrTexDim;
    g_tex2DDownscaledInsctrRadiance.GetDimensions(f2DownscaledInsctrTexDim.x, f2DownscaledInsctrTexDim.y);
    // Offset by 0.5 is essential, because texel centers have UV coordinates that are offset by half the texel size
    float2 f2UVScaled = f2UV.xy * f2DownscaledInsctrTexDim.xy - float2(0.5, 0.5);
    float2 f2LeftBottomSrcTexelUV = floor(f2UVScaled);
    // Get bilinear filtering weights
    float2 f2BilinearWeights = f2UVScaled - f2LeftBottomSrcTexelUV;
    // Get texture coordinates of the left bottom source texel. Again, offset by 0.5 is essential
    // to align with texel center
    f2LeftBottomSrcTexelUV = (f2LeftBottomSrcTexelUV + float2(0.5, 0.5)) / f2DownscaledInsctrTexDim.xy;

    // Load camera space Z values corresponding to locations of the source texels in g_tex2DDownscaledInsctrRadiance texture
    // We must arrange the data in the same manner as Gather() does:
    float4 f4SrcLocationsCamSpaceZ;
    f4SrcLocationsCamSpaceZ.x = GetCamSpaceZ( f2LeftBottomSrcTexelUV + float2(0,1) / f2DownscaledInsctrTexDim.xy );
    f4SrcLocationsCamSpaceZ.y = GetCamSpaceZ( f2LeftBottomSrcTexelUV + float2(1,1) / f2DownscaledInsctrTexDim.xy );
    f4SrcLocationsCamSpaceZ.z = GetCamSpaceZ( f2LeftBottomSrcTexelUV + float2(1,0) / f2DownscaledInsctrTexDim.xy );
    f4SrcLocationsCamSpaceZ.w = GetCamSpaceZ( f2LeftBottomSrcTexelUV + float2(0,0) / f2DownscaledInsctrTexDim.xy );

    // Get camera space z of the current screen pixel
    float fCamSpaceZ = GetCamSpaceZ( f2UV );

    float3 f3InsctrIntegral = PerformBilateralInterpolation(f2BilinearWeights, f2LeftBottomSrcTexelUV, f4SrcLocationsCamSpaceZ, fCamSpaceZ, g_tex2DDownscaledInsctrRadiance, f2DownscaledInsctrTexDim, samLinearClamp);
    
    float3 f3ReconstructedPosWS = ProjSpaceXYZToWorldSpace( float3(In.m_f2PosPS.xy,fCamSpaceZ) );
    float3 f3EyeVector = f3ReconstructedPosWS.xyz - g_CameraAttribs.f4CameraPos.xyz;
    float fDistToCamera = length(f3EyeVector);

#if LIGHT_TYPE == LIGHT_TYPE_DIRECTIONAL
    f3EyeVector /= fDistToCamera;
    float3 f3ScatteredLight = ApplyPhaseFunction(f3InsctrIntegral, dot(f3EyeVector, g_LightAttribs.f4DirOnLight.xyz));
#else
    float3 f3ScatteredLight = f3InsctrIntegral;
#endif

    float3 f3BackgroundColor = GetAttenuatedBackgroundColor(In, fDistToCamera);

    return ToneMap(f3BackgroundColor + f3ScatteredLight);
}

technique11 UpscaleInscatteredRadiance
{
    pass
    {
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        SetDepthStencilState( DSS_NoDepthTestIncrStencil, 0 );

        SetVertexShader( CompileShader(vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader(ps_5_0, UpscaleInscatteredRadiancePS() ) );
    }
}


struct PassThroughVS_Output
{
    uint uiVertexID : VERTEX_ID;
};

PassThroughVS_Output PassThroughVS(uint VertexID : SV_VertexID)
{
    PassThroughVS_Output Out = {VertexID};
    return Out;
}



struct SRenderSamplePositionsGS_Output
{
    float4 f4PosPS : SV_Position;
    float3 f3Color : COLOR;
    float2 f2PosXY : XY;
    float4 f4QuadCenterAndSize : QUAD_CENTER_SIZE;
};
[maxvertexcount(4)]
void RenderSamplePositionsGS(point PassThroughVS_Output In[1], 
                             inout TriangleStream<SRenderSamplePositionsGS_Output> triStream )
{
    uint2 CoordTexDim;
    g_tex2DCoordinates.GetDimensions(CoordTexDim.x, CoordTexDim.y);
    uint2 TexelIJ = uint2( In[0].uiVertexID%CoordTexDim.x, In[0].uiVertexID/CoordTexDim.x );
    float2 f2QuadCenterPos = g_tex2DCoordinates.Load(int3(TexelIJ,0));

    uint2 ui2InterpolationSources = g_tex2DInterpolationSource.Load( uint3(TexelIJ,0) );
    bool bIsInterpolation = ui2InterpolationSources.x != ui2InterpolationSources.y;

    float2 f2QuadSize = (bIsInterpolation ? 1.f : 4.f) / SCREEN_RESLOUTION.xy;
    float4 MinMaxUV = float4(f2QuadCenterPos.x-f2QuadSize.x, f2QuadCenterPos.y - f2QuadSize.y, f2QuadCenterPos.x+f2QuadSize.x, f2QuadCenterPos.y + f2QuadSize.y);
    
    float3 f3Color = bIsInterpolation ? float3(0.5,0,0) : float3(1,0,0);
    float4 Verts[4] = 
    {
        float4(MinMaxUV.xy, 1.0, 1.0), 
        float4(MinMaxUV.xw, 1.0, 1.0),
        float4(MinMaxUV.zy, 1.0, 1.0),
        float4(MinMaxUV.zw, 1.0, 1.0)
    };

    for(int i=0; i<4; i++)
    {
        SRenderSamplePositionsGS_Output Out;
        Out.f4PosPS = Verts[i];
        Out.f2PosXY = Out.f4PosPS.xy;
        Out.f3Color = f3Color;
        Out.f4QuadCenterAndSize = float4(f2QuadCenterPos, f2QuadSize);
        triStream.Append( Out );
    }
}

float4 RenderSampleLocationsPS(SRenderSamplePositionsGS_Output In) : SV_Target
{
    return float4(In.f3Color, 1 - pow( length( (In.f2PosXY - In.f4QuadCenterAndSize.xy) / In.f4QuadCenterAndSize.zw),4) );
}

BlendState OverBS
{
    BlendEnable[0] = TRUE;
    RenderTargetWriteMask[0] = 0x0F;
    BlendOp = ADD;
    SrcBlend = SRC_ALPHA;
    DestBlend = INV_SRC_ALPHA;
    SrcBlendAlpha = ZERO;
    DestBlendAlpha = INV_SRC_ALPHA;
};

technique11 RenderSampleLocations
{
    pass
    {
        SetBlendState( OverBS, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        SetDepthStencilState( DSS_NoDepthTest, 0 );

        SetVertexShader( CompileShader(vs_5_0, PassThroughVS() ) );
        SetGeometryShader( CompileShader(gs_4_0, RenderSamplePositionsGS() ) );
        SetPixelShader( CompileShader(ps_5_0, RenderSampleLocationsPS() ) );
    }
}

float GetPrecomputedPtLghtSrcTexU(in float3 f3Pos, in float3 f3EyeDir, in float3 f3ClosestPointToLight)
{
    return (dot(f3Pos - f3ClosestPointToLight, f3EyeDir) + g_PPAttribs.m_fMaxTracingDistance) / (2*g_PPAttribs.m_fMaxTracingDistance);
};

void TruncateEyeRayToLightCone(in float3 f3EyeVector, 
                               inout float3 f3RayStartPos, 
                               inout float3 f3RayEndPos, 
                               inout float fTraceLength, 
                               out float fStartDistance,
                               bool bIsCamInsideCone)
{
    // Intersect view ray with the light cone
    float2 f2ConeIsecs = 
        RayConeIntersect(g_LightAttribs.f4LightWorldPos.xyz, g_LightAttribs.f4SpotLightAxisAndCosAngle.xyz, g_LightAttribs.f4SpotLightAxisAndCosAngle.w,
                         g_CameraAttribs.f4CameraPos.xyz, f3EyeVector);
    
    if( bIsCamInsideCone  )
    {
        f3RayStartPos = g_CameraAttribs.f4CameraPos.xyz;
        fStartDistance = 0;
        if( f2ConeIsecs.x > 0 )
        {
            // 
            //   '.       *     .' 
            //     '.      \  .'   
            //       '.     \'  x > 0
            //         '. .' \
            //           '    \ 
            //         '   '   \y = -FLT_MAX 
            //       '       ' 
            fTraceLength = min(f2ConeIsecs.x, fTraceLength);
        }
        else if( f2ConeIsecs.y > 0 )
        {
            // 
            //                '.             .' 
            //    x = -FLT_MAX  '.---*---->.' y > 0
            //                    '.     .'
            //                      '. .'  
            //                        '
            fTraceLength = min(f2ConeIsecs.y, fTraceLength);
        }
        f3RayEndPos = g_CameraAttribs.f4CameraPos.xyz + fTraceLength * f3EyeVector;
    }
    else if( all(f2ConeIsecs > 0) )
    {
        // 
        //          '.             .' 
        //    *-------'.-------->.' y > 0
        //          x>0 '.     .'
        //                '. .'  
        //                  '
        fTraceLength = min(f2ConeIsecs.y,fTraceLength);
        f3RayEndPos   = g_CameraAttribs.f4CameraPos.xyz + fTraceLength * f3EyeVector;
        f3RayStartPos = g_CameraAttribs.f4CameraPos.xyz + f2ConeIsecs.x * f3EyeVector;
        fStartDistance = f2ConeIsecs.x;
        fTraceLength -= f2ConeIsecs.x;
    }
    else if( f2ConeIsecs.y > 0 )
    {
        // 
        //   '.       \     .'                '.         |   .' 
        //     '.      \  .'                    '.       | .'   
        //       '.     \'  y > 0                 '.     |'  y > 0
        //         '. .' \                          '. .'| 
        //           '    *                           '  |   
        //         '   '   \x = -FLT_MAX            '   '|   x = -FLT_MAX 
        //       '       '                        '      |' 
        //                                               *
        //
        f3RayEndPos   = g_CameraAttribs.f4CameraPos.xyz + fTraceLength * f3EyeVector;
        f3RayStartPos = g_CameraAttribs.f4CameraPos.xyz + f2ConeIsecs.y * f3EyeVector;
        fStartDistance = f2ConeIsecs.y;
        fTraceLength -= f2ConeIsecs.y;
    }
    else
    {
        fTraceLength = 0;
        fStartDistance = 0;
        f3RayStartPos = g_CameraAttribs.f4CameraPos.xyz;
        f3RayEndPos   = g_CameraAttribs.f4CameraPos.xyz;
    }
    fTraceLength = max(fTraceLength,0);
}

#if INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_SRNN05

const float2 GetSRNN05LUTParamLimits()
{
    // The first argument of the lookup table is the distance from the point light source to the view ray, multiplied by the scattering coefficient
    // The second argument is the weird angle which is in the range from 0 t Pi/2, as tan(Pi/2) = +inf
    return float2(
        g_PPAttribs.m_fMaxTracingDistance * 2 * max(max(g_MediaParams.f4SummTotalBeta.r, g_MediaParams.f4SummTotalBeta.g), g_MediaParams.f4SummTotalBeta.b),
        PI/2 );
}
float3 GetInsctrIntegral_SRNN05( in float3 f3A1, in float3 f3Tsv, in float fCosGamma, in float fSinGamma, in float fDistFromCamera)
{
    // f3A1 depends only on the location of the camera and the light source
    // f3Tsv = fDistToLight * g_MediaParams.f4SummTotalBeta.rgb
    float3 f3Tvp = fDistFromCamera * g_MediaParams.f4SummTotalBeta.rgb;
    float3 f3Ksi = PI/4.f + 0.5f * atan( (f3Tvp - f3Tsv * fCosGamma) / (f3Tsv * fSinGamma) );
    float2 f2SRNN05LUTParamLimits = GetSRNN05LUTParamLimits();
    // float fGamma = acos(fCosGamma);
    // F(A1, Gamma/2) defines constant offset and thus is not required
    return float3(
                g_tex2DPrecomputedPointLightInsctr.SampleLevel(samLinearClamp, float2(f3A1.x, f3Ksi.x)/f2SRNN05LUTParamLimits, 0).x /*- 
                g_tex2DPrecomputedPointLightInsctr.SampleLevel(samLinearClamp, float2(f3A1.x, fGamma/2)/f2SRNN05LUTParamLimits, 0).x*/,

                g_tex2DPrecomputedPointLightInsctr.SampleLevel(samLinearClamp, float2(f3A1.y, f3Ksi.y)/f2SRNN05LUTParamLimits, 0).x /*- 
                g_tex2DPrecomputedPointLightInsctr.SampleLevel(samLinearClamp, float2(f3A1.y, fGamma/2)/f2SRNN05LUTParamLimits, 0).x*/,

                g_tex2DPrecomputedPointLightInsctr.SampleLevel(samLinearClamp, float2(f3A1.z, f3Ksi.z)/f2SRNN05LUTParamLimits, 0).x /*- 
                g_tex2DPrecomputedPointLightInsctr.SampleLevel(samLinearClamp, float2(f3A1.z, fGamma/2)/f2SRNN05LUTParamLimits, 0).x */);
}
#endif

float3 EvaluatePhaseFunction(float fCosTheta);

// This function calculates inscattered light integral over the ray from the camera to 
// the specified world space position using ray marching
float3 CalculateInscattering( in float2 f2RayMarchingSampleLocation,
                              in uniform const bool bApplyPhaseFunction = false,
                              in uniform const bool bUse1DMinMaxMipMap = false,
                              uint uiEpipolarSliceInd = 0 )
{
    float3 f3ReconstructedPos = ProjSpaceXYToWorldSpace(f2RayMarchingSampleLocation);

    float3 f3RayStartPos = g_CameraAttribs.f4CameraPos.xyz;
    float3 f3RayEndPos = f3ReconstructedPos;
    float3 f3EyeVector = f3RayEndPos.xyz - f3RayStartPos;
    float fTraceLength = length(f3EyeVector);
    f3EyeVector /= fTraceLength;
        
#if LIGHT_TYPE == LIGHT_TYPE_DIRECTIONAL
    // Update end position
    fTraceLength = min(fTraceLength, g_PPAttribs.m_fMaxTracingDistance);
    f3RayEndPos = g_CameraAttribs.f4CameraPos.xyz + fTraceLength * f3EyeVector;
#elif LIGHT_TYPE == LIGHT_TYPE_POINT || LIGHT_TYPE == LIGHT_TYPE_SPOT

    //                       Light
    //                        *                   -
    //                     .' |\                  |
    //                   .'   | \                 | fClosestDistToLight
    //                 .'     |  \                |
    //               .'       |   \               |
    //          Cam *--------------*--------->    -
    //              |<--------|     \
    //                  \
    //                  fStartDistFromProjection

    float fDistToLight = length( g_LightAttribs.f4LightWorldPos.xyz - g_CameraAttribs.f4CameraPos.xyz );
    float fCosLV = dot(g_LightAttribs.f4DirOnLight.xyz, f3EyeVector);
    float fDistToClosestToLightPoint = fDistToLight * fCosLV;
    float fClosestDistToLight = fDistToLight * sqrt(1 - fCosLV*fCosLV);
    float fV = fClosestDistToLight / g_PPAttribs.m_fMaxTracingDistance;
    
    float3 f3ClosestPointToLight = g_CameraAttribs.f4CameraPos.xyz + f3EyeVector * fDistToClosestToLightPoint;

    float3 f3CameraInsctrIntegral = 0;
    float3 f3RayTerminationInsctrIntegral = 0;
#if INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_MY_LUT

    float fCameraU = GetPrecomputedPtLghtSrcTexU(g_CameraAttribs.f4CameraPos.xyz, f3EyeVector, f3ClosestPointToLight);
    float fReconstrPointU = GetPrecomputedPtLghtSrcTexU(f3ReconstructedPos, f3EyeVector, f3ClosestPointToLight);

    f3CameraInsctrIntegral = g_tex2DPrecomputedPointLightInsctr.SampleLevel(samLinearClamp, float2(fCameraU, fV), 0);
    f3RayTerminationInsctrIntegral = exp(-fTraceLength*g_MediaParams.f4SummTotalBeta.rgb) * g_tex2DPrecomputedPointLightInsctr.SampleLevel(samLinearClamp, float2(fReconstrPointU, fV), 0);

#elif INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_SRNN05

    float3 f3Tsv = fDistToLight * g_MediaParams.f4SummTotalBeta.rgb;
    float fSinGamma = max(sqrt( 1 - fCosLV*fCosLV ), 1e-6);
    float3 f3A0 = g_MediaParams.f4SummTotalBeta.rgb * g_MediaParams.f4SummTotalBeta.rgb * 
                  //g_LightAttribs.f4LightColorAndIntensity.rgb * g_LightAttribs.f4LightColorAndIntensity.w *
                  exp(-f3Tsv * fCosLV) / 
                  (2.0*PI * f3Tsv * fSinGamma);
    float3 f3A1 = f3Tsv * fSinGamma;
    
    f3CameraInsctrIntegral = -f3A0 * GetInsctrIntegral_SRNN05( f3A1, f3Tsv, fCosLV, fSinGamma, 0);
    f3RayTerminationInsctrIntegral = -f3A0 * GetInsctrIntegral_SRNN05( f3A1, f3Tsv, fCosLV, fSinGamma, fTraceLength);

#endif

    float3 f3FullyLitInsctrIntegral = (f3CameraInsctrIntegral - f3RayTerminationInsctrIntegral) * 
                                    g_LightAttribs.f4LightColorAndIntensity.rgb * g_LightAttribs.f4LightColorAndIntensity.w;
    
    bool bIsCamInsideCone = dot( -g_LightAttribs.f4DirOnLight.xyz, g_LightAttribs.f4SpotLightAxisAndCosAngle.xyz) > g_LightAttribs.f4SpotLightAxisAndCosAngle.w;

    // Eye rays directed at exactly the light source requires special handling
    if( fCosLV > 1 - 1e-6 )
    {
#if INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_ANALYTIC
        f3FullyLitInsctrIntegral = 1e+8;
#endif
        float IsInLight = bIsCamInsideCone ? 
                            g_tex2DLightSpaceDepthMap.SampleCmpLevelZero( samComparison, g_LightAttribs.f4CameraUVAndDepthInShadowMap.xy, g_LightAttribs.f4CameraUVAndDepthInShadowMap.z ).x : 
                            1;
        // This term is required to eliminate bright point visible through scene geometry
        // when the camera is outside the light cone
        float fIsLightVisible = bIsCamInsideCone || (fDistToLight < fTraceLength);
        return f3FullyLitInsctrIntegral * IsInLight * fIsLightVisible;
    }

    float fStartDistance;
    TruncateEyeRayToLightCone(f3EyeVector, f3RayStartPos, f3RayEndPos, fTraceLength, fStartDistance, bIsCamInsideCone);

#endif
    
    // If tracing distance is very short, we can fall into an inifinte loop due to
    // 0 length step and crash the driver. Return from function in this case
    if( fTraceLength < g_PPAttribs.m_fMaxTracingDistance * 0.0001)
    {
#   if LIGHT_TYPE == LIGHT_TYPE_POINT
        return f3FullyLitInsctrIntegral;
#   else
        return float3(0,0,0);
#   endif
    }

    // We trace the ray not in the world space, but in the light projection space

#if LIGHT_TYPE == LIGHT_TYPE_DIRECTIONAL
    // Get start and end positions of the ray in the light projection space
    float4 f4StartUVAndDepthInLightSpace = float4(g_LightAttribs.f4CameraUVAndDepthInShadowMap.xyz,1);
#elif LIGHT_TYPE == LIGHT_TYPE_POINT || LIGHT_TYPE == LIGHT_TYPE_SPOT
    float4 f4StartUVAndDepthInLightSpace = WorldSpaceToShadowMapUV(f3RayStartPos);
#endif

    //f4StartUVAndDepthInLightSpace.z -= SHADOW_MAP_DEPTH_BIAS;
    // Compute shadow map UV coordiantes of the ray end point and its depth in the light space
    float4 f4EndUVAndDepthInLightSpace = WorldSpaceToShadowMapUV(f3RayEndPos);
    //f4EndUVAndDepthInLightSpace.z -= SHADOW_MAP_DEPTH_BIAS;

    // Calculate normalized trace direction in the light projection space and its length
    float3 f3ShadowMapTraceDir = f4EndUVAndDepthInLightSpace.xyz - f4StartUVAndDepthInLightSpace.xyz;
    // If the ray is directed exactly at the light source, trace length will be zero
    // Clamp to a very small positive value to avoid division by zero
    // Also assure that trace len is not longer than maximum meaningful length
    float fTraceLenInShadowMapUVSpace = clamp( length( f3ShadowMapTraceDir.xy ), 1e-6, sqrt(2.f) );
    f3ShadowMapTraceDir /= fTraceLenInShadowMapUVSpace;
    
    float fShadowMapUVStepLen = 0;
    float2 f2SliceOriginUV = 0;
    if( bUse1DMinMaxMipMap )
    {
        // Get UV direction for this slice
        float4 f4SliceUVDirAndOrigin = g_tex2DSliceUVDirAndOrigin.Load( uint3(uiEpipolarSliceInd,0,0) );
        if( all(f4SliceUVDirAndOrigin == g_f4IncorrectSliceUVDirAndStart) )
        {
#   if LIGHT_TYPE == LIGHT_TYPE_POINT
           return f3FullyLitInsctrIntegral;
#   else
            return float3(0,0,0);
#   endif
        }

        // Scale with the shadow map texel size
        fShadowMapUVStepLen = length(f4SliceUVDirAndOrigin.xy * g_PPAttribs.m_f2ShadowMapTexelSize);
        f2SliceOriginUV = f4SliceUVDirAndOrigin.zw;
    }
    else
    {
        //Calculate length of the trace step in light projection space
        fShadowMapUVStepLen = g_PPAttribs.m_f2ShadowMapTexelSize.x / max( abs(f3ShadowMapTraceDir.x), abs(f3ShadowMapTraceDir.y) );
        // Take into account maximum number of steps specified by the g_MiscParams.fMaxStepsAlongRay
        fShadowMapUVStepLen = max(fTraceLenInShadowMapUVSpace/g_MiscParams.fMaxStepsAlongRay, fShadowMapUVStepLen);
    }
    
    // Calcualte ray step length in world space
    float fRayStepLengthWS = fTraceLength * (fShadowMapUVStepLen / fTraceLenInShadowMapUVSpace);
    // Assure that step length is not 0 so that we will not fall into an infinite loop and
    // will not crash the driver
    //fRayStepLengthWS = max(fRayStepLengthWS, g_PPAttribs.m_fMaxTracingDistance * 1e-5);

    // Scale trace direction in light projection space to calculate the final step
    float3 f3ShadowMapUVAndDepthStep = f3ShadowMapTraceDir * fShadowMapUVStepLen;

    float3 f3InScatteringIntegral = 0;
    float3 f3PrevInsctrIntegralValue = 1; // exp( -0 * g_MediaParams.f4SummTotalBeta.rgb );
    // March the ray
    float fTotalMarchedDistance = 0;
    float fTotalMarchedDistInUVSpace = 0;
    float3 f3CurrShadowMapUVAndDepthInLightSpace = f4StartUVAndDepthInLightSpace.xyz;

    // The following variables are used only if 1D min map optimization is enabled
    uint uiMinLevel = 0;//max( log2( (fTraceLenInShadowMapUVSpace/fShadowMapUVStepLen) / g_MiscParams.fMaxStepsAlongRay), 0 );
    uint uiCurrSamplePos = 0;

    // For spot light, the slice start UV is either location of camera in light proj space
    // or intersection of the slice with the cone rib. No adjustment is required in either case
//#if LIGHT_TYPE == LIGHT_TYPE_SPOT
//    uiCurrSamplePos = length(f4StartUVAndDepthInLightSpace.xy - f2SliceOriginUV.xy) / fShadowMapUVStepLen;
//#endif

#if LIGHT_TYPE == LIGHT_TYPE_POINT || LIGHT_TYPE == LIGHT_TYPE_SPOT
   
#   if INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_MY_LUT
        float fInsctrTexStartU = GetPrecomputedPtLghtSrcTexU(f3RayStartPos, f3EyeVector, f3ClosestPointToLight);
        float fInsctrTexEndU = GetPrecomputedPtLghtSrcTexU(f3RayEndPos, f3EyeVector, f3ClosestPointToLight);
        f3PrevInsctrIntegralValue = exp(-fStartDistance*g_MediaParams.f4SummTotalBeta.rgb) * g_tex2DPrecomputedPointLightInsctr.SampleLevel(samLinearClamp, float2(fInsctrTexStartU, fV), 0);
#   elif INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_SRNN05
        f3PrevInsctrIntegralValue = -f3A0 * GetInsctrIntegral_SRNN05( f3A1, f3Tsv, fCosLV, fSinGamma, fStartDistance);
#   endif

#   if LIGHT_TYPE == LIGHT_TYPE_POINT && (INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_MY_LUT || INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_SRNN05)
        // Add inscattering contribution outside the light cone
        f3InScatteringIntegral = 
                    ( f3CameraInsctrIntegral - 
                      f3PrevInsctrIntegralValue +
#       if INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_MY_LUT
                      exp(-(fStartDistance+fTraceLength)*g_MediaParams.f4SummTotalBeta.rgb) * g_tex2DPrecomputedPointLightInsctr.SampleLevel(samLinearClamp, float2(fInsctrTexEndU, fV), 0)
#       else
                      - f3A0 * GetInsctrIntegral_SRNN05( f3A1, f3Tsv, fCosLV, fSinGamma, fStartDistance+fTraceLength) 
#       endif
                      - f3RayTerminationInsctrIntegral ) * g_LightAttribs.f4LightColorAndIntensity.rgb;
#   endif
#endif

    uint uiCurrTreeLevel = 0;
    // Note that min/max shadow map does not contain finest resolution level
    // The first level it contains corresponds to step == 2
    int iLevelDataOffset = -int(g_PPAttribs.m_uiMinMaxShadowMapResolution);
    float fStep = 1.f;
    float fMaxShadowMapStep = g_PPAttribs.m_uiMaxShadowMapStep;

#if (LIGHT_TYPE == LIGHT_TYPE_POINT || LIGHT_TYPE == LIGHT_TYPE_SPOT) && INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_ANALYTIC
    float fPrevDistFromCamera = fStartDistance;
#endif

    [loop]
    while( fTotalMarchedDistInUVSpace < fTraceLenInShadowMapUVSpace )
    {
        // Clamp depth to a very small positive value to not let the shadow rays get clipped at the
        // shadow map far clipping plane
        float fCurrDepthInLightSpace = max(f3CurrShadowMapUVAndDepthInLightSpace.z, 1e-7);
        float IsInLight = 0;

#if ACCEL_STRUCT > ACCEL_STRUCT_NONE
        if( bUse1DMinMaxMipMap )
        {

            // If the step is smaller than the maximum allowed and the sample
            // is located at the appropriate position, advance to the next coarser level
            if( fStep < fMaxShadowMapStep && ((uiCurrSamplePos & ((2<<uiCurrTreeLevel)-1)) == 0) )
            {
                iLevelDataOffset += g_PPAttribs.m_uiMinMaxShadowMapResolution >> uiCurrTreeLevel;
                uiCurrTreeLevel++;
                fStep *= 2.f;
            }

            while(uiCurrTreeLevel > uiMinLevel)
            {
                // Compute light space depths at the ends of the current ray section

                // What we need here is actually depth which is divided by the camera view space z
                // Thus depth can be correctly interpolated in screen space:
                // http://www.comp.nus.edu.sg/~lowkl/publications/lowk_persp_interp_techrep.pdf
                // A subtle moment here is that we need to be sure that we can skip fStep samples 
                // starting from 0 up to fStep-1. We do not need to do any checks against the sample fStep away:
                //
                //     --------------->
                //
                //          *
                //               *         *
                //     *              *     
                //     0    1    2    3
                //
                //     |------------------>|
                //           fStep = 4
                float fNextLightSpaceDepth = f3CurrShadowMapUVAndDepthInLightSpace.z + f3ShadowMapUVAndDepthStep.z * (fStep-1);
                float2 f2StartEndDepthOnRaySection = float2(f3CurrShadowMapUVAndDepthInLightSpace.z, fNextLightSpaceDepth);
                f2StartEndDepthOnRaySection = max(f2StartEndDepthOnRaySection, 1e-7);

                // Load 1D min/max depths
                MIN_MAX_DATA_FORMAT fnCurrMinMaxDepth = g_tex2DMinMaxLightSpaceDepth.Load( uint3( (uiCurrSamplePos>>uiCurrTreeLevel) + iLevelDataOffset, uiEpipolarSliceInd, 0) );
                
#   if ACCEL_STRUCT == ACCEL_STRUCT_BV_TREE
                float4 f4CurrMinMaxDepth = fnCurrMinMaxDepth;
#   elif ACCEL_STRUCT == ACCEL_STRUCT_MIN_MAX_TREE
                float4 f4CurrMinMaxDepth = fnCurrMinMaxDepth.xyxy;
#   endif

#   if !STAINED_GLASS
                IsInLight = all( f2StartEndDepthOnRaySection >= f4CurrMinMaxDepth.yw );
#   endif
                bool bIsInShadow = all( f2StartEndDepthOnRaySection < f4CurrMinMaxDepth.xz );

                if( IsInLight || bIsInShadow )
                    // If the ray section is fully lit or shadow, we can break the loop
                    break;
                // If the ray section is neither fully lit, nor shadowed, we have to go to the finer level
                uiCurrTreeLevel--;
                iLevelDataOffset -= g_PPAttribs.m_uiMinMaxShadowMapResolution >> uiCurrTreeLevel;
                fStep /= 2.f;
            };

            // If we are at the finest level, sample the shadow map with PCF
            [branch]
            if( uiCurrTreeLevel <= uiMinLevel )
            {
                IsInLight = g_tex2DLightSpaceDepthMap.SampleCmpLevelZero( samComparison, f3CurrShadowMapUVAndDepthInLightSpace.xy, fCurrDepthInLightSpace  ).x;
            }
        }
        else
#endif
        {
            IsInLight = g_tex2DLightSpaceDepthMap.SampleCmpLevelZero( samComparison, f3CurrShadowMapUVAndDepthInLightSpace.xy, fCurrDepthInLightSpace ).x;
        }

        float3 LightColorInCurrPoint;
        LightColorInCurrPoint = g_LightAttribs.f4LightColorAndIntensity.rgb;

#if STAINED_GLASS
        float4 SGWColor = g_tex2DStainedGlassColorDepth.SampleLevel( samLinearClamp, f3CurrShadowMapUVAndDepthInLightSpace.xy, 0).rgba;
        LightColorInCurrPoint.rgb *= ((SGWColor.a < fCurrDepthInLightSpace) ? float3(1,1,1) : SGWColor.rgb*3);
#endif

        f3CurrShadowMapUVAndDepthInLightSpace += f3ShadowMapUVAndDepthStep * fStep;
        fTotalMarchedDistInUVSpace += fShadowMapUVStepLen * fStep;
        uiCurrSamplePos += 1 << uiCurrTreeLevel; // int -> float conversions are slow

#if LIGHT_TYPE == LIGHT_TYPE_DIRECTIONAL
        fTotalMarchedDistance += fRayStepLengthWS * fStep;
        float fIntegrationDist = min(fTotalMarchedDistance, fTraceLength);
        // Calculate inscattering integral from the camera to the current point analytically:
        float3 f3CurrInscatteringIntegralValue = exp( -fIntegrationDist * g_MediaParams.f4SummTotalBeta.rgb );
#elif LIGHT_TYPE == LIGHT_TYPE_SPOT || LIGHT_TYPE == LIGHT_TYPE_POINT
        // http://www.comp.nus.edu.sg/~lowkl/publications/lowk_persp_interp_techrep.pdf
        // An attribute A itself cannot be correctly interpolated in screen space
        // However, A/z where z is the camera view space coordinate, does interpolate correctly
        // 1/z also interpolates correctly, thus to properly interpolate A it is necessary to
        // do the following: lerp( A/z ) / lerp ( 1/z )
        // Note that since eye ray directed at exactly the light source is handled separately,
        // camera space z can never become zero
        float fRelativePos = saturate(fTotalMarchedDistInUVSpace / fTraceLenInShadowMapUVSpace);
        float fCurrW = lerp(f4StartUVAndDepthInLightSpace.w, f4EndUVAndDepthInLightSpace.w, fRelativePos);
        float fDistFromCamera = lerp(fStartDistance * f4StartUVAndDepthInLightSpace.w, (fStartDistance+fTraceLength) * f4EndUVAndDepthInLightSpace.w, fRelativePos) / fCurrW;
        float3 f3CurrInscatteringIntegralValue = 0;
#   if INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_MY_LUT
            float fCurrU = lerp(fInsctrTexStartU * f4StartUVAndDepthInLightSpace.w, fInsctrTexEndU * f4EndUVAndDepthInLightSpace.w, fRelativePos) / fCurrW;
            f3CurrInscatteringIntegralValue = exp(-fDistFromCamera*g_MediaParams.f4SummTotalBeta.rgb) * g_tex2DPrecomputedPointLightInsctr.SampleLevel(samLinearClamp, float2(fCurrU, fV), 0);
#   elif INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_SRNN05
            f3CurrInscatteringIntegralValue = -f3A0 * GetInsctrIntegral_SRNN05( f3A1, f3Tsv, fCosLV, fSinGamma, fDistFromCamera);
#   elif INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_ANALYTIC
            float3 f3DirFromLight = g_CameraAttribs.f4CameraPos.xyz  + fDistFromCamera * f3EyeVector - g_LightAttribs.f4LightWorldPos.xyz;
            float fDistFromLightSqr = max(dot(f3DirFromLight, f3DirFromLight), 1e-10);
            float fDistFromLight = sqrt(fDistFromLightSqr);
            f3DirFromLight /= fDistFromLight;
            float fCosTheta = dot(-f3EyeVector, f3DirFromLight);
            float3 f3Extinction = exp(-(fDistFromCamera+fDistFromLight)*g_MediaParams.f4SummTotalBeta.rgb);
            f3CurrInscatteringIntegralValue = 0;
            f3PrevInsctrIntegralValue = f3Extinction * EvaluatePhaseFunction(fCosTheta) * (fDistFromCamera - fPrevDistFromCamera) / fDistFromLightSqr;
            fPrevDistFromCamera = fDistFromCamera;
#   endif

#endif

        float3 dScatteredLight;
        // dScatteredLight contains correct scattering light value with respect to extinction
        dScatteredLight.rgb = (f3PrevInsctrIntegralValue.rgb - f3CurrInscatteringIntegralValue.rgb) * IsInLight;
        dScatteredLight.rgb *= LightColorInCurrPoint;
        f3InScatteringIntegral.rgb += dScatteredLight.rgb;

        f3PrevInsctrIntegralValue.rgb = f3CurrInscatteringIntegralValue.rgb;
    }

#if LIGHT_TYPE == LIGHT_TYPE_DIRECTIONAL
    f3InScatteringIntegral = f3InScatteringIntegral / g_MediaParams.f4SummTotalBeta.rgb;
#else
    f3InScatteringIntegral *= g_LightAttribs.f4LightColorAndIntensity.w;
#endif

#if LIGHT_TYPE == LIGHT_TYPE_DIRECTIONAL
    if( bApplyPhaseFunction )
        return ApplyPhaseFunction(f3InScatteringIntegral, dot(f3EyeVector, g_LightAttribs.f4DirOnLight.xyz));
    else
#endif
        return f3InScatteringIntegral;
}

float3 RayMarchMinMaxOptPS(SScreenSizeQuadVSOutput In) : SV_TARGET
{
    uint2 ui2SamplePosSliceInd = uint2(In.m_f4Pos.xy);
    float2 f2SampleLocation = g_tex2DCoordinates.Load( uint3(ui2SamplePosSliceInd, 0) );

    [branch]
    if( any(abs(f2SampleLocation) > 1+1e-3) )
        return 0;

    return CalculateInscattering(f2SampleLocation, 
                                 false, // Do not apply phase function
                                 true,  // Use min/max optimization
                                 ui2SamplePosSliceInd.y);
}

float3 RayMarchPS(SScreenSizeQuadVSOutput In) : SV_TARGET
{
    float2 f2SampleLocation = g_tex2DCoordinates.Load( uint3(In.m_f4Pos.xy, 0) );

    [branch]
    if( any(abs(f2SampleLocation) > 1+1e-3) )
        return 0;

    return CalculateInscattering(f2SampleLocation, 
                                 false, // Do not apply phase function
                                 false, // Do not use min/max optimization
                                 0 // Ignored
                                 );
}

technique10 DoRayMarch
{
    pass P0
    {
        // Skip all samples which are not marked in the stencil as ray marching
        SetDepthStencilState( DSS_NoDepth_StEqual_IncrStencil, 2 );
        SetRasterizerState( RS_SolidFill_NoCull );
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );

        SetVertexShader( CompileShader( vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader(NULL);
        SetPixelShader( CompileShader( ps_5_0, RayMarchPS() ) );
    }

    pass P1
    {
        // Skip all samples which are not marked in the stencil as ray marching
        SetDepthStencilState( DSS_NoDepth_StEqual_IncrStencil, 2 );
        SetRasterizerState( RS_SolidFill_NoCull );
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );

        SetVertexShader( CompileShader( vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader(NULL);
        SetPixelShader( CompileShader( ps_5_0, RayMarchMinMaxOptPS() ) );
    }
}

float3 FixInscatteredRadiancePS(SScreenSizeQuadVSOutput In) : SV_Target
{
    if( g_PPAttribs.m_bShowDepthBreaks )
        return float3(0,0,1e+3);

    return CalculateInscattering(In.m_f2PosPS.xy, 
                                 false, // Do not apply phase function
                                 false, // We cannot use min/max optimization at depth breaks
                                 0 // Ignored
                                 );
}

float3 FixAndApplyInscatteredRadiancePS(SScreenSizeQuadVSOutput In) : SV_Target
{
    if( g_PPAttribs.m_bShowDepthBreaks )
        return float3(0,1,0);

    float3 f3BackgroundColor = GetAttenuatedBackgroundColor(In);
    
    float3 f3InsctrColor = 
        CalculateInscattering(In.m_f2PosPS.xy, 
                              true, // Apply phase function
                              false, // We cannot use min/max optimization at depth breaks
                              0 // Ignored
                              );

    return ToneMap(f3BackgroundColor + f3InsctrColor.rgb);
}

technique11 FixInscatteredRadiance
{
    pass PAttenuateBackground
    {
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        SetDepthStencilState( DSS_NoDepth_StEqual_IncrStencil, 0 );

        SetVertexShader( CompileShader(vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader(ps_5_0, FixInscatteredRadiancePS() ) );
    }

    pass PRenderScatteringOnly
    {
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        SetDepthStencilState( DSS_NoDepth_StEqual_IncrStencil, 0 );

        SetVertexShader( CompileShader(vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader(ps_5_0, FixAndApplyInscatteredRadiancePS() ) );
    }
}

float3 EvaluatePhaseFunction(float fCosTheta)
{
#if ANISOTROPIC_PHASE_FUNCTION
    float3 f3RlghInsctr =  g_MediaParams.f4AngularRayleighBeta.rgb * (1.0 + fCosTheta*fCosTheta);
    float HGTemp = rsqrt( dot(g_MediaParams.f4HG_g.yz, float2(1.f, fCosTheta)) );
    float3 f3MieInsctr = g_MediaParams.f4AngularMieBeta.rgb * g_MediaParams.f4HG_g.x * (HGTemp*HGTemp*HGTemp);
#else
    float3 f3RlghInsctr = g_MediaParams.f4TotalRayleighBeta.rgb / (4.0*PI);
    float3 f3MieInsctr = g_MediaParams.f4TotalMieBeta.rgb / (4.0*PI);
#endif

    return f3RlghInsctr + f3MieInsctr;
}


INSCTR_LUT_FORMAT PrecomputePointLightInsctrPS(SScreenSizeQuadVSOutput In) : SV_Target
{
#if INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_MY_LUT

    float fMaxTracingDistance = g_PPAttribs.m_fMaxTracingDistance;
    //                       Light
    //                        *                   -
    //                     .' |\                  |
    //                   .'   | \                 | fClosestDistToLight
    //                 .'     |  \                |
    //               .'       |   \               |
    //          Cam *--------------*--------->    -
    //              |<--------|     \
    //                  \
    //                  fStartDistFromProjection
    //
    float2 f2UV = ProjToUV(In.m_f2PosPS.xy);
    float fStartDistFromProjection = In.m_f2PosPS.x * fMaxTracingDistance;
    float fClosestDistToLight = f2UV.y * fMaxTracingDistance;

    float3 f3InsctrRadinance = 0;
    
    // There is a very important property: pre-computed scattering must be monotonical with respect
    // to u coordinate. However, if we simply subdivide the tracing distance onto the equal number of steps
    // as in the following code, we cannot guarantee this
    // 
    // float fStepWorldLen = length(f2StartPos-f2EndPos) / fNumSteps;
    // for( float fRelativePos=0; fRelativePos < 1; fRelativePos += 1.f/fNumSteps )
    // {
    //      float2 f2CurrPos = lerp(f2StartPos, f2EndPos, fRelativePos);    
    //      ...
    //
    // To assure that the scattering is monotonically increasing, we must go through
    // exactly the same taps for all pre-computations. The simple method to achieve this
    // is to make the world step the same as the difference between two neighboring texels:
    // The step can also be integral part of it, but not greater! So /2 will work, but *2 won't!
    float fStepWorldLen = ddx(fStartDistFromProjection);
    for(float fDistFromProj = fStartDistFromProjection; fDistFromProj < fMaxTracingDistance; fDistFromProj += fStepWorldLen)
    {
        float2 f2CurrPos = float2(fDistFromProj, -fClosestDistToLight);
        float fDistToLightSqr = dot(f2CurrPos, f2CurrPos);
        float fDistToLight = sqrt(fDistToLightSqr);
        float fDistToCam = f2CurrPos.x - fStartDistFromProjection;
        float3 f3Extinction = exp( -(fDistToCam + fDistToLight) * g_MediaParams.f4SummTotalBeta.rgb );
        float2 f2LightDir = normalize(f2CurrPos);
        float fCosTheta = -f2LightDir.x;

        float3 f3dLInsctr = f3Extinction * EvaluatePhaseFunction(fCosTheta) * fStepWorldLen / max(fDistToLightSqr,fMaxTracingDistance*fMaxTracingDistance*1e-8);
        f3InsctrRadinance += f3dLInsctr;
    }
    return f3InsctrRadinance;

#elif INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_SRNN05
    
    float fPrecomputedFuncValue = 0;
    float2 f2UV = ProjToUV(In.m_f2PosPS.xy);
    f2UV *= GetSRNN05LUTParamLimits();
    float fKsiStep = ddy(f2UV.y);
    for(float fKsi = 0; fKsi < f2UV.y; fKsi += fKsiStep)
    {
        fPrecomputedFuncValue += exp( -f2UV.x * tan(fKsi) );
    }

    fPrecomputedFuncValue *= fKsiStep;
    return fPrecomputedFuncValue;

#endif

}


technique11 PrecomputePointLightInsctrTech
{
    pass PAttenuateBackground
    {
        SetBlendState( NoBlending, float4( 0.0f, 0.0f, 0.0f, 0.0f ), 0xFFFFFFFF );
        SetRasterizerState( RS_SolidFill_NoCull );
        SetDepthStencilState( DSS_NoDepthTest, 0 );

        SetVertexShader( CompileShader(vs_5_0, GenerateScreenSizeQuadVS() ) );
        SetGeometryShader( NULL );
        SetPixelShader( CompileShader(ps_5_0, PrecomputePointLightInsctrPS() ) );
    }
}
