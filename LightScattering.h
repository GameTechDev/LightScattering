/////////////////////////////////////////////////////////////////////////////////////////////
// Copyright 2017 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");// you may not use this file except in compliance with the License.// You may obtain a copy of the License at//// http://www.apache.org/licenses/LICENSE-2.0//// Unless required by applicable law or agreed to in writing, software// distributed under the License is distributed on an "AS IS" BASIS,// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.// See the License for the specific language governing permissions and// limitations under the License.
/////////////////////////////////////////////////////////////////////////////////////////////

#include <d3dx9math.h>
//#include "CRTMemoryDebug.h" // Visual Studio CRT memory leak detection

#include "Structures.fxh"
// Temporary:
#undef float2
#undef float3
#undef float4

#include <stdio.h>

#include "CPUT_DX11.h"
#include "CPUTMaterial.h"

#include <D3D11.h> // for D3D11_BUFFER_DESC
#include <xnamath.h> // for XMFLOAT

#include <time.h> // for srand(time)

struct FrameConstantBuffer
{
    XMFLOAT4 Eye;
    XMFLOAT4 LookAt;
    XMFLOAT4 Up;
    XMFLOAT4 LightDirection;  

	XMMATRIX  worldMatrix;
    XMMATRIX  viewMatrix;	
	XMMATRIX  projectionMatrix;
};

const CPUTControlID ID_MAIN_PANEL = 10;
const CPUTControlID ID_SECONDARY_PANEL = 20;
const CPUTControlID ID_IGNORE_CONTROL_ID = -1;

enum CONTROL_IDS
{
    ID_FULLSCREEN_BUTTON = 100,
    ID_ENABLE_LIGHT_SCATTERING,
    ID_LIGHT_SCTR_TECHNIQUE,
    ID_LIGHT_TYPE,
    ID_NUM_EPIPOLAR_SLICES,
    ID_NUM_SAMPLES_IN_EPIPOLAR_SLICE,
    ID_INITIAL_SAMPLE_STEP_IN_EPIPOLAR_SLICE,
    ID_EPIPOLE_SAMPLING_DENSITY_FACTOR,
    ID_REFINEMENT_THRESHOLD,
    ID_DOWNSCALE_FACTOR,
    ID_SHOW_SAMPLING,
    ID_MIN_MAX_SHADOW_MAP_OPTIMIZATION,
    ID_INSCTR_INTGL_EVAL_METHOD,
    ID_OPTIMIZE_SAMPLE_LOCATIONS,
    ID_CORRECT_SCATTERING_AT_DEPTH_BREAKS,
    ID_LIGHT_INTENSITY,
    ID_EXPOSURE,
    ID_SHOW_DEPTH_BREAKS,   
    ID_SHOW_STAINED_GLASS,
    ID_ANISOTROPIC_PHASE_FUNC,
    ID_SHOW_LIGHTING_ONLY_CHECK,
    ID_SHADOW_MAP_RESOLUTION,
    ID_RLGH_COLOR_BTN,
    ID_MIE_COLOR_BTN,
    ID_POINT_LIGHT_COLOR_BTN,
    ID_SPOT_LIGHT_ANGLE_SLIDER,
    ID_TEXTLINES = 1000
};



// DirectX 11 Sample
//-----------------------------------------------------------------------------
class CLightScatteringSample:public CPUT_DX11
{
public:
    CLightScatteringSample();
    virtual ~CLightScatteringSample();

    // Event handling
    virtual CPUTEventHandledCode HandleKeyboardEvent(CPUTKey key);
    virtual CPUTEventHandledCode HandleMouseEvent(int x, int y, int wheel, CPUTMouseState state);
    virtual void                 HandleCallbackEvent( CPUTEventID Event, CPUTControlID ControlID, CPUTControl* pControl );

    // 'callback' handlers for rendering events.  Derived from CPUT_DX11
    virtual void Create();
    virtual void Render(double deltaSeconds);
    virtual void Update(double deltaSeconds);
    virtual void ResizeWindow(UINT width, UINT height);
    
    void Shutdown();

private:

    HRESULT CreateAuxTextures(ID3D11Device* pd3dDevice);
    void ReleaseAuxTextures();

    HRESULT CreateTmpBackBuffAndDepthBuff(ID3D11Device* pd3dDevice);
    void ReleaseTmpBackBuffAndDepthBuff();

    D3DXVECTOR3 m_pvSceneBoundBoxCorners[8];
    void RenderShadowMap(ID3D11DeviceContext *pContext, 
						 const D3DXVECTOR3& vLightDirection, 
                         const D3DXVECTOR3& vDirectionOnSun,
                         const D3DXVECTOR3& vLightPos);

    void Destroy();

    float GetSceneExtent();

    D3DXMATRIX m_WorldToLightProjSpaceMatr;
    D3DXMATRIX m_WorldToLightSpaceMatr;
    D3DXMATRIX m_LightOrthoMatrix;

    class CLightSctrPostProcess *m_pLightSctrPP;

    UINT m_uiShadowMapResolution;
    bool m_bEnableLightScattering;

    static const int m_iMinEpipolarSlices = 32;
    static const int m_iMaxEpipolarSlices = 2048;
    static const int m_iMinSamplesInEpipolarSlice = 32;
    static const int m_iMaxSamplesInEpipolarSlice = 2048;
    static const int m_iMaxEpipoleSamplingDensityFactor = 32;
    static const int m_iMinInitialSamplesInEpipolarSlice = 8;
    SPostProcessingAttribs m_PPAttribs;
    float m_fLightIntensity;

    CPUTRenderTargetDepth*  m_pShadowMap;
    CPUTRenderTargetColor*  m_pStainedGlassMap;
    CPUTRenderTargetDepth*  m_pStainedGlassDepth;
    CPUTRenderTargetColor*  m_pOffscreenRenderTarget;
    CPUTRenderTargetDepth*  m_pOffscreenDepth;

    CPUTAssetSet*   m_pCathedralAssetSet;
    CPUTAssetSet*   m_pStainedGlassAssetSet;
    CPUTAssetSet*   m_pTerrainAssetSet;

    CPUTAssetSet*   m_pCageAssetSet;
    CPUTAssetSet*   m_pKleigAssetSet;
    CPUTAssetSet*   m_pSkyLightAssetSet;

        
    CPUTCamera*           m_pDirectionalLightCamera;
    CPUTCamera*           m_pDirLightOrienationCamera;
    CPUTCamera*           m_pSpotLightOrienationCamera;
    CPUTCamera*           m_pViewCameras[2];
    CPUTCamera*           m_pSpotLightCamera;
    CPUTCameraController* mpCameraController;
    CPUTCameraController* m_pLightController;

    CPUTTimerWin          m_Timer;
    float                 m_fElapsedTime;

	D3DXVECTOR3 m_f3PrevDirOnLight;
    D3DXVECTOR3 m_f3PrevLightPosition;
    D3DXVECTOR3 m_f3PrevSpotLightAxis;

    float m_fSpotLightAngle, m_fPrevSpotLightAngle;
    D3DXVECTOR4 m_f4LightColor;
    
    int m_iGUIMode;
    
    CComPtr<ID3D11Buffer> m_pLightAttribsCB;

private:
    CLightScatteringSample(const CLightScatteringSample&);
    const CLightScatteringSample& operator = (const CLightScatteringSample&);
};
