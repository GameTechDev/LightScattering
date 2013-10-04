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

#ifndef _STRCUTURES_FXH_
#define _STRCUTURES_FXH_

#define PI 3.1415928f

#ifdef __cplusplus

#   define float2 D3DXVECTOR2
#   define float3 D3DXVECTOR3
#   define float4 D3DXVECTOR4
#   define uint UINT

#else

#   define BOOL bool // Do not use bool, because sizeof(bool)==1 !

#endif

#ifdef __cplusplus
#   define CHECK_STRUCT_ALIGNMENT(s) static_assert( sizeof(s) % 16 == 0, "sizeof("#s") is not multiple of 16" );
#else
#   define CHECK_STRUCT_ALIGNMENT(s)
#endif

struct SLightAttribs
{
    float4 f4DirOnLight;
    float4 f4LightColorAndIntensity;
    float4 f4AmbientLight;
    float4 f4CameraUVAndDepthInShadowMap;
    float4 f4LightScreenPos;
    float4 f4LightWorldPos;                // For point and spot lights only
    float4 f4SpotLightAxisAndCosAngle;     // For spot light only

    BOOL bIsLightOnScreen;
    float3 f3Dummy;

#ifdef __cplusplus
    D3DXMATRIX mLightViewT;
    D3DXMATRIX mLightProjT;
    D3DXMATRIX mWorldToLightProjSpaceT;
    D3DXMATRIX mCameraProjToLightProjSpaceT;
#else
    matrix mLightView;
    matrix mLightProj;
    matrix mWorldToLightProjSpace;
    matrix mCameraProjToLightProjSpace;
#endif
};
CHECK_STRUCT_ALIGNMENT(SLightAttribs);

struct SCameraAttribs
{
    float4 f4CameraPos;            ///< Camera world position
#ifdef __cplusplus
    D3DXMATRIX mViewT;
    D3DXMATRIX mProjT;
    D3DXMATRIX mViewProjInvT;
#else
    matrix mView;
    matrix mProj;
    matrix mViewProjInv;
#endif
};
CHECK_STRUCT_ALIGNMENT(SCameraAttribs);

#define ACCEL_STRUCT_NONE 0
#define ACCEL_STRUCT_MIN_MAX_TREE 1
#define ACCEL_STRUCT_BV_TREE 2

#define LIGHT_TYPE_DIRECTIONAL 0
#define LIGHT_TYPE_SPOT 1
#define LIGHT_TYPE_POINT 2


#define INSCTR_INTGL_EVAL_METHOD_MY_LUT 0
#define INSCTR_INTGL_EVAL_METHOD_SRNN05 1
#define INSCTR_INTGL_EVAL_METHOD_ANALYTIC 2

#define LIGHT_SCTR_TECHNIQUE_EPIPOLAR_SAMPLING 0
#define LIGHT_SCTR_TECHNIQUE_BRUTE_FORCE 1

struct SPostProcessingAttribs
{
    uint m_uiNumEpipolarSlices;
    uint m_uiMaxSamplesInSlice;
    uint m_uiInitialSampleStepInSlice;
    uint m_uiEpipoleSamplingDensityFactor;

    float m_fRefinementThreshold;
    float m_fDownscaleFactor;
    // do not use bool, because sizeof(bool)==1 and as a result bool variables
    // will be incorrectly mapped on GPU constant buffer
    BOOL m_bShowSampling; 
    BOOL m_bCorrectScatteringAtDepthBreaks; 

    BOOL m_bShowDepthBreaks; 
    BOOL m_bStainedGlass;
    BOOL m_bShowLightingOnly;
    BOOL m_bOptimizeSampleLocations;

    uint m_uiAccelStruct;
    float m_fDistanceScaler;
    float m_fMaxTracingDistance;
    uint m_uiMaxShadowMapStep;

    float2 m_f2ShadowMapTexelSize;
    uint m_uiShadowMapResolution;
    uint m_uiMinMaxShadowMapResolution;

    uint m_uiLightType;
    float m_fExposure;
    uint m_uiInsctrIntglEvalMethod;
    uint m_uiLightSctrTechnique;

    BOOL m_bAnisotropicPhaseFunction;
    float3 m_f3Dummy;

    float4 m_f4RayleighBeta;
    float4 m_f4MieBeta;

#ifdef __cplusplus
    SPostProcessingAttribs() : 
        m_uiNumEpipolarSlices(1024),
        m_uiMaxSamplesInSlice(512),
        m_uiInitialSampleStepInSlice(16),
        // Note that sampling near the epipole is very cheap since only a few steps
        // required to perform ray marching
        m_uiEpipoleSamplingDensityFactor(4),
        m_fRefinementThreshold(0.02f),
        m_fDownscaleFactor(1.f),
        m_bShowSampling(FALSE),
        m_bCorrectScatteringAtDepthBreaks(TRUE),
        m_bShowDepthBreaks(FALSE),
        m_bStainedGlass(FALSE),
        m_bShowLightingOnly(FALSE),
        m_bOptimizeSampleLocations(TRUE),
        m_uiAccelStruct(ACCEL_STRUCT_MIN_MAX_TREE),
        m_fDistanceScaler(1.f),
        m_fMaxTracingDistance(20.f),
        m_uiMaxShadowMapStep(16),
        m_f2ShadowMapTexelSize(0,0),
        m_uiMinMaxShadowMapResolution(0),
        m_uiLightType(LIGHT_TYPE_SPOT),
        m_fExposure(1.f),
        m_uiInsctrIntglEvalMethod(INSCTR_INTGL_EVAL_METHOD_MY_LUT),
        m_uiLightSctrTechnique(LIGHT_SCTR_TECHNIQUE_EPIPOLAR_SAMPLING),
        m_bAnisotropicPhaseFunction(TRUE),
        m_f4RayleighBeta( 5.8e-6f, 13.5e-6f, 33.1e-6f, 0.f ),
        m_f4MieBeta(2.0e-5f, 2.0e-5f, 2.0e-5f, 0.f)
    {}
#endif
};
CHECK_STRUCT_ALIGNMENT(SPostProcessingAttribs);

struct SParticipatingMediaScatteringParams
{
    // Atmospheric light scattering constants
    float4 f4TotalRayleighBeta;
    float4 f4AngularRayleighBeta;
    float4 f4TotalMieBeta;
    float4 f4AngularMieBeta;
    float4 f4HG_g; // = float4(1 - HG_g*HG_g, 1 + HG_g*HG_g, -2*HG_g, 1.0);
    float4 f4SummTotalBeta;

#define INSCATTERING_MULTIPLIER 27.f/3.f   ///< Light scattering constant - Inscattering multiplier    
};
CHECK_STRUCT_ALIGNMENT(SParticipatingMediaScatteringParams);

struct SMiscDynamicParams
{
#ifdef __cplusplus
    uint ui4SrcMinMaxLevelXOffset;
    uint ui4SrcMinMaxLevelYOffset;
    uint ui4DstMinMaxLevelXOffset;
    uint ui4DstMinMaxLevelYOffset;
#else
    uint4 ui4SrcDstMinMaxLevelOffset;
#endif
    float fMaxStepsAlongRay;   // Maximum number of steps during ray tracing
    float3 f3Dummy; // Constant buffers must be 16-byte aligned
};
CHECK_STRUCT_ALIGNMENT(SMiscDynamicParams);

#endif //_STRCUTURES_FXH_