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

#include "Structures.fxh"

#define FLT_MAX 3.402823466e+38f

// Using static definitions instead of constant buffer variables is 
// more efficient because the compiler is able to optimize the code 
// more aggressively

#ifndef NUM_EPIPOLAR_SLICES
#   define NUM_EPIPOLAR_SLICES 1024
#endif

#ifndef MAX_SAMPLES_IN_SLICE
#   define MAX_SAMPLES_IN_SLICE 512
#endif

#ifndef SCREEN_RESLOUTION
#   define SCREEN_RESLOUTION float2(1024,768)
#endif

#ifndef ACCEL_STRUCT
#   define ACCEL_STRUCT ACCEL_STRUCT_BV_TREE
#endif

#if ACCEL_STRUCT == ACCEL_STRUCT_BV_TREE
#   define MIN_MAX_DATA_FORMAT float4
#elif ACCEL_STRUCT == ACCEL_STRUCT_MIN_MAX_TREE
#   define MIN_MAX_DATA_FORMAT float2
#else
#   define MIN_MAX_DATA_FORMAT float2
#endif

#ifndef INSCTR_INTGL_EVAL_METHOD
#   define INSCTR_INTGL_EVAL_METHOD INSCTR_INTGL_EVAL_METHOD_MY_LUT
#endif

#if INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_MY_LUT
#   define INSCTR_LUT_FORMAT float3
#elif INSCTR_INTGL_EVAL_METHOD == INSCTR_INTGL_EVAL_METHOD_SRNN05
#   define INSCTR_LUT_FORMAT float
#endif
#ifndef INSCTR_LUT_FORMAT
#   define INSCTR_LUT_FORMAT float
#endif

cbuffer cbPostProcessingAttribs : register( b0 )
{
    SPostProcessingAttribs g_PPAttribs;
};

cbuffer cbParticipatingMediaScatteringParams : register( b1 )
{
    SParticipatingMediaScatteringParams g_MediaParams;
}

// Frame parameters
cbuffer cbCameraAttribs : register( b2 )
{
    SCameraAttribs g_CameraAttribs;
}

cbuffer cbLightParams : register( b3 )
{
    SLightAttribs g_LightAttribs;
}

cbuffer cbMiscDynamicParams : register( b4 )
{
    SMiscDynamicParams g_MiscParams;
}

Texture2D<float>  g_tex2DDepthBuffer            : register( t0 );
Texture2D<float>  g_tex2DCamSpaceZ              : register( t0 );
Texture2D<float4> g_tex2DSliceEndPoints         : register( t4 );
Texture2D<float2> g_tex2DCoordinates            : register( t1 );
Texture2D<float>  g_tex2DEpipolarCamSpaceZ      : register( t2 );
Texture2D<uint2>  g_tex2DInterpolationSource    : register( t7 );
Texture2D<float>  g_tex2DLightSpaceDepthMap     : register( t3 );
Texture2D<float4> g_tex2DSliceUVDirAndOrigin    : register( t2 );
Texture2D<MIN_MAX_DATA_FORMAT> g_tex2DMinMaxLightSpaceDepth  : register( t4 );
Texture2D<float4> g_tex2DStainedGlassColorDepth : register( t5 );
Texture2D<float3> g_tex2DInitialInsctrIrradiance: register( t6 );
Texture2D<float4> g_tex2DColorBuffer            : register( t1 );
Texture2D<float3> g_tex2DScatteredColor         : register( t3 );
Texture2D<float3> g_tex2DDownscaledInsctrRadiance: register( t2 );
Texture2D<INSCTR_LUT_FORMAT> g_tex2DPrecomputedPointLightInsctr: register( t6 );

float3 ApplyPhaseFunction(in float3 f3InsctrIntegral, in float cosTheta)
{
    //    sun
    //      \
    //       \
    //    ----\------eye
    //         \theta 
    //          \
    //    
    
    // Compute Rayleigh scattering Phase Function
    // According to formula for the Rayleigh Scattering phase function presented in the 
    // "Rendering Outdoor Light Scattering in Real Time" by Hoffman and Preetham (see p.36 and p.51), 
    // BethaR(Theta) is calculated as follows:
    // 3/(16PI) * BethaR * (1+cos^2(theta))
    // g_MediaParams.f4AngularRayleighBeta == (3*PI/16) * g_MediaParams.f4TotalRayleighBeta, hence:
    float3 RayleighScatteringPhaseFunc = g_MediaParams.f4AngularRayleighBeta.rgb * (1.0 + cosTheta*cosTheta);

    // Compute Henyey-Greenstein approximation of the Mie scattering Phase Function
    // According to formula for the Mie Scattering phase function presented in the 
    // "Rendering Outdoor Light Scattering in Real Time" by Hoffman and Preetham 
    // (see p.38 and p.51),  BethaR(Theta) is calculated as follows:
    // 1/(4PI) * BethaM * (1-g^2)/(1+g^2-2g*cos(theta))^(3/2)
    // const float4 g_MediaParams.f4HG_g = float4(1 - g*g, 1 + g*g, -2*g, 1);
    float HGTemp = rsqrt( dot(g_MediaParams.f4HG_g.yz, float2(1.f, cosTheta)) );//rsqrt( g_MediaParams.f4HG_g.y + g_MediaParams.f4HG_g.z*cosTheta);
    // g_MediaParams.f4AngularMieBeta is calculated according to formula presented in "A practical Analytic 
    // Model for Daylight" by Preetham & Hoffman (see p.23)
    float3 fMieScatteringPhaseFunc_HGApprox = g_MediaParams.f4AngularMieBeta.rgb * g_MediaParams.f4HG_g.x * (HGTemp*HGTemp*HGTemp);

    float3 f3InscatteredLight = f3InsctrIntegral * 
                               (RayleighScatteringPhaseFunc + fMieScatteringPhaseFunc_HGApprox);

    f3InscatteredLight.rgb *= g_LightAttribs.f4LightColorAndIntensity.w;  
    
    return f3InscatteredLight;
}

float3 ProjSpaceXYZToWorldSpace(in float3 f3PosPS)
{
    // We need to compute depth before applying view-proj inverse matrix
    float fDepth = g_CameraAttribs.mProj[2][2] + g_CameraAttribs.mProj[3][2] / f3PosPS.z;
    float4 ReconstructedPosWS = mul( float4(f3PosPS.xy,fDepth,1), g_CameraAttribs.mViewProjInv );
    ReconstructedPosWS /= ReconstructedPosWS.w;
    return ReconstructedPosWS.xyz;
}

float2 RayConeIntersect(in float3 f3ConeApex, in float3 f3ConeAxis, in float fCosAngle, in float3 f3RayStart, in float3 f3RayDir)
{
    f3RayStart -= f3ConeApex;
    float a = dot(f3RayDir, f3ConeAxis);
    float b = dot(f3RayDir, f3RayDir);
    float c = dot(f3RayStart, f3ConeAxis);
    float d = dot(f3RayStart, f3RayDir);
    float e = dot(f3RayStart, f3RayStart);
    fCosAngle *= fCosAngle;
    float A = a*a - b*fCosAngle;
    float B = 2 * ( c*a - d*fCosAngle );
    float C = c*c - e*fCosAngle;
    float D = B*B - 4*A*C;
    if( D > 0 )
    {
        D = sqrt(D);
        float2 t = (-B + sign(A)*float2(-D,+D)) / (2*A);
        bool2 b2IsCorrect = c + a * t > 0;
        t = t * b2IsCorrect + !b2IsCorrect * (-FLT_MAX);
        return t;
    }
    else
        return -FLT_MAX;
}

bool PlanePlaneIntersect(float3 f3N1, float3 f3P1, float3 f3N2, float3 f3P2,
                         out float3 f3LineOrigin, out float3 f3LineDir)
{
    // http://paulbourke.net/geometry/planeplane/
    float fd1 = dot(f3N1, f3P1);
    float fd2 = dot(f3N2, f3P2);
    float fN1N1 = dot(f3N1, f3N1);
    float fN2N2 = dot(f3N2, f3N2);
    float fN1N2 = dot(f3N1, f3N2);

    float fDet = fN1N1 * fN2N2 - fN1N2*fN1N2;
    if( abs(fDet) < 1e-6 )
        return false;

    float fc1 = (fd1 * fN2N2 - fd2 * fN1N2) / fDet;
    float fc2 = (fd2 * fN1N1 - fd1 * fN1N2) / fDet;

    f3LineOrigin = fc1 * f3N1 + fc2 * f3N2;
    f3LineDir = normalize(cross(f3N1, f3N2));
    
    return true;
}
