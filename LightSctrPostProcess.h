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

#pragma once

#include <D3DX11.h>
#include <D3DX10math.h>

#include "RenderTechnique.h"

#include "structures.fxh"
struct SFrameAttribs
{
    ID3D11Device *pd3dDevice;
    ID3D11DeviceContext *pd3dDeviceContext;
    
    SLightAttribs LightAttribs;
    SCameraAttribs CameraAttribs;

    ID3D11ShaderResourceView *ptex2DSrcColorBufferSRV;
    ID3D11ShaderResourceView *ptex2DDepthBufferSRV;
    ID3D11ShaderResourceView *ptex2DShadowMapSRV;
    ID3D11ShaderResourceView *ptex2DStainedGlassSRV;
    ID3D11RenderTargetView *pDstRTV;
    ID3D11DepthStencilView *pDstDSV;
};

#undef float4
#undef float3
#undef float2

#include <atlcomcli.h>

class CLightSctrPostProcess
{
public:
    CLightSctrPostProcess();
    ~CLightSctrPostProcess();

    HRESULT OnCreateDevice(ID3D11Device* in_pd3dDevice, 
                           ID3D11DeviceContext *in_pd3dDeviceContext);
    void OnDestroyDevice();


    HRESULT OnResizedSwapChain(ID3D11Device* pd3dDevice, UINT uiBackBufferWidth, UINT uiBackBufferHeight);

    void PerformPostProcessing(SFrameAttribs &FrameAttribs,
                               SPostProcessingAttribs &PPAttribs);

    void ComputeSunColor(const D3DXVECTOR3 &vDirectionOnSun,
                         D3DXVECTOR4 &f4SunColorAtGround,
                         D3DXVECTOR4 &f4AmbientLight);

private:
    HRESULT CreateDownscaledInscatteringTextures(ID3D11Device* pd3dDevice, UINT Width, UINT Height);

    void ReconstructCameraSpaceZ(SFrameAttribs &FrameAttribs);
    void RenderSliceEndpoints(SFrameAttribs &FrameAttribs);
    void RenderCoordinateTexture(SFrameAttribs &FrameAttribs);
    void RefineSampleLocations(SFrameAttribs &FrameAttribs);
    void MarkRayMarchingSamples(SFrameAttribs &FrameAttribs);
    void Build1DMinMaxMipMap(SFrameAttribs &FrameAttribs);
    void DoRayMarching(SFrameAttribs &FrameAttribs, UINT uiMaxStepsAlongRay);
    void InterpolateInsctrIrradiance(SFrameAttribs &FrameAttribs);
    void UnwarpEpipolarScattering(SFrameAttribs &FrameAttribs);
    void FixInscatteringAtDepthBreaks(SFrameAttribs &FrameAttribs, bool bAttenuateBackground, UINT uiMaxStepsAlongRay);
    void UpscaleInscatteringRadiance(SFrameAttribs &FrameAttribs);
    void RenderSampleLocations(SFrameAttribs &FrameAttribs);

    void DefineMacros(class CD3DShaderMacroHelper &Macros);

    SPostProcessingAttribs m_PostProcessingAttribs;
    UINT m_uiSampleRefinementCSThreadGroupSize;
    UINT m_uiSampleRefinementCSMinimumThreadGroupSize;

    CComPtr<ID3D11ShaderResourceView> m_ptex2DSliceEndpointsSRV;
    CComPtr<ID3D11RenderTargetView> m_ptex2DSliceEndpointsRTV;

    CComPtr<ID3D11ShaderResourceView> m_ptex2DCoordianteTextureSRV;
    CComPtr<ID3D11RenderTargetView> m_ptex2DCoordianteTextureRTV;
    CComPtr<ID3D11DepthStencilView> m_ptex2DEpipolarImageDSV;

    CComPtr<ID3D11ShaderResourceView> m_ptex2DEpipolarCamSpaceZSRV;
    CComPtr<ID3D11RenderTargetView> m_ptex2DEpipolarCamSpaceZRTV;

    CComPtr<ID3D11ShaderResourceView> m_ptex2DInterpolationSourcesSRV;
    CComPtr<ID3D11UnorderedAccessView> m_ptex2DInterpolationSourcesUAV;

    CComPtr<ID3D11ShaderResourceView> m_ptex2DInitialScatteredLightSRV;
    CComPtr<ID3D11RenderTargetView> m_ptex2DInitialScatteredLightRTV;

    CComPtr<ID3D11ShaderResourceView> m_ptex2DScatteredLightSRV;
    CComPtr<ID3D11RenderTargetView> m_ptex2DScatteredLightRTV;

    CComPtr<ID3D11ShaderResourceView> m_ptex2DCameraSpaceZSRV;
    CComPtr<ID3D11RenderTargetView> m_ptex2DCameraSpaceZRTV;
    
    CComPtr<ID3D11ShaderResourceView> m_ptex2DDownscaledScatteredLightSRV;
    CComPtr<ID3D11RenderTargetView> m_ptex2DDownscaledScatteredLightRTV;

    CComPtr<ID3D11ShaderResourceView> m_ptex2DSliceUVDirAndOriginSRV;
    CComPtr<ID3D11RenderTargetView> m_ptex2DSliceUVDirAndOriginRTV;

    CComPtr<ID3D11ShaderResourceView> m_ptex2DMinMaxShadowMapSRV[2];
    CComPtr<ID3D11RenderTargetView> m_ptex2DMinMaxShadowMapRTV[2];

    CComPtr<ID3D11ShaderResourceView> m_ptex2DPrecomputedPointLightInsctrSRV;
    
    HRESULT CreateTextures(ID3D11Device* pd3dDevice);
    HRESULT CreateMinMaxShadowMap(ID3D11Device* pd3dDevice);
    HRESULT CreatePrecomputedPointLightInscatteringTexture(ID3D11Device* pd3dDevice, ID3D11DeviceContext *pd3dDeviceContext);
    CComPtr<ID3D11DepthStencilView> m_ptex2DScreenSizeDSV;
    CComPtr<ID3D11DepthStencilView> m_ptex2DDownscaledDSV;

    UINT m_uiBackBufferWidth, m_uiBackBufferHeight;

    LPCTSTR m_strEffectPath;

    CComPtr<ID3D11VertexShader> m_pGenerateScreenSizeQuadVS;

    CRenderTechnique m_ReconstrCamSpaceZTech;
    CRenderTechnique m_RendedSliceEndpointsTech;
    CRenderTechnique m_RendedCoordTexTech;
    CRenderTechnique m_RefineSampleLocationsTech;
    CRenderTechnique m_MarkRayMarchingSamplesInStencilTech;
    CRenderTechnique m_RenderSliceUVDirInSMTech;
    CRenderTechnique m_InitializeMinMaxShadowMapTech;
    CRenderTechnique m_ComputeMinMaxSMLevelTech;
    CRenderTechnique m_DoRayMarchTech[2]; // 0 - min/max optimization disabled; 1 - min/max optimization enabled
    CRenderTechnique m_InterpolateIrradianceTech;
    CRenderTechnique m_UnwarpEpipolarSctrImgTech[2]; // 0 - Unwarp inscattering image from epipolar coordinates only
                                                     // 1 - Unwarp inscattering image from epipolar coordinates to rectangular + apply it to attenuate background
    CRenderTechnique m_FixInsctrAtDepthBreaksTech[2]; // 0 - Fix inscattering image at depth breaks by doing ray marching only
                                                      // 1 - Fix inscattering image + apply it to attenuate background
    CRenderTechnique m_UpscaleInsctrdRadianceTech;
    CRenderTechnique m_RenderSampleLocationsTech;

    CComPtr<ID3D11SamplerState> m_psamLinearClamp;
    CComPtr<ID3D11SamplerState> m_psamLinearBorder0;
    CComPtr<ID3D11SamplerState> m_psamLinearUClampVWrap;
    CComPtr<ID3D11SamplerState> m_psamComparison;

    CComPtr<ID3D11DepthStencilState> m_pDisableDepthTestDS;
    CComPtr<ID3D11DepthStencilState> m_pDisableDepthTestIncrStencilDS;
    CComPtr<ID3D11DepthStencilState> m_pNoDepth_StEqual_IncrStencilDS;

    CComPtr<ID3D11RasterizerState> m_pSolidFillNoCullRS;

    CComPtr<ID3D11BlendState> m_pDefaultBS;

    void ComputeScatteringCoefficients(ID3D11DeviceContext *pDeviceCtx = NULL);
    
    const float m_fTurbidity;
    SParticipatingMediaScatteringParams m_MediaParams;

    CComPtr<ID3D11Buffer> m_pcbCameraAttribs;
    CComPtr<ID3D11Buffer> m_pcbLightAttribs;
    CComPtr<ID3D11Buffer> m_pcbPostProcessingAttribs;
    CComPtr<ID3D11Buffer> m_pcbMediaAttribs;
    CComPtr<ID3D11Buffer> m_pcbMiscParams;
};
