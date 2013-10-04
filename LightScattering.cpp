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
#include "LightScattering.h"
#include "LightSctrPostProcess.h"
#include <iomanip>
#include "CPUTBufferDX11.h"
// important to use the right CPUT namespace

void UpdateConstantBuffer(ID3D11DeviceContext *pDeviceCtx, ID3D11Buffer *pCB, const void *pData, size_t DataSize);

extern const char *gpDefaultShaderSource;

class CParallelLightCamera : public CPUTCamera
{
public:
    virtual void Update( float deltaSeconds=0.0f ) {
        mView = inverse(*GetWorldMatrix());
    };
};

// Constructor
//-----------------------------------------------------------------------------
CLightScatteringSample::CLightScatteringSample() : 
    m_pCathedralAssetSet(NULL),
    m_pStainedGlassAssetSet(NULL),
    m_pTerrainAssetSet(NULL),
    m_pCageAssetSet(NULL),
    m_pKleigAssetSet(NULL),
    m_pSkyLightAssetSet(NULL),
    mpCameraController(NULL),
    m_pLightController(NULL),
    m_uiShadowMapResolution( 1024 ),
    m_bEnableLightScattering(true),
    m_pShadowMap(NULL),
    m_pStainedGlassMap(NULL),
    m_pStainedGlassDepth(NULL),
    m_pOffscreenRenderTarget(NULL),
    m_pOffscreenDepth(NULL),
	m_f3PrevDirOnLight(0,0,0),
    m_f3PrevLightPosition(0,0,0),
    m_f3PrevSpotLightAxis(0,0,0),
    m_fLightIntensity(12.f),
    m_fSpotLightAngle(D3DX_PI/6.f),
    m_fPrevSpotLightAngle(0),
    m_f4LightColor(1.f, 1.f, 1.f, 1.f),
    m_iGUIMode(1)
{
    m_pLightSctrPP = new CLightSctrPostProcess;
}

// Destructor
//-----------------------------------------------------------------------------
CLightScatteringSample::~CLightScatteringSample()
{
    Destroy();

    SAFE_DELETE( m_pLightSctrPP );
}

void CLightScatteringSample::Destroy()
{
    // release the model set
    SAFE_RELEASE(m_pCathedralAssetSet);
    SAFE_RELEASE(m_pStainedGlassAssetSet);
    SAFE_RELEASE(m_pTerrainAssetSet);

    SAFE_RELEASE(m_pCageAssetSet);
    SAFE_RELEASE(m_pKleigAssetSet);
    SAFE_RELEASE(m_pSkyLightAssetSet);

    ReleaseAuxTextures();
    ReleaseTmpBackBuffAndDepthBuff();

    m_pLightSctrPP->OnDestroyDevice();

    for(int iCam = 0; iCam < _countof(m_pViewCameras); ++iCam)
        SAFE_RELEASE( m_pViewCameras[iCam] );

    SAFE_RELEASE(m_pDirectionalLightCamera);
    SAFE_RELEASE(m_pSpotLightCamera);
    SAFE_RELEASE(m_pDirLightOrienationCamera);
    SAFE_RELEASE(m_pSpotLightOrienationCamera);

    SAFE_DELETE( mpCameraController);
    SAFE_DELETE( m_pLightController);
    m_pLightAttribsCB.Release();
}

// Handle keyboard events
//-----------------------------------------------------------------------------
CPUTEventHandledCode CLightScatteringSample::HandleKeyboardEvent(CPUTKey key)
{
    CPUTEventHandledCode    handled = CPUT_EVENT_UNHANDLED;
    CPUTGuiControllerDX11*      pGUI = CPUTGetGuiController(); 
    cString filename;

    switch(key)
    {
    case KEY_F1:
        ++m_iGUIMode;
        if( m_iGUIMode>2 )
            m_iGUIMode = 0;
        if(m_iGUIMode==1)
            pGUI->SetActivePanel(ID_MAIN_PANEL);
        else if(m_iGUIMode==2)
            pGUI->SetActivePanel(ID_SECONDARY_PANEL);
        handled = CPUT_EVENT_HANDLED;
        break;
    
    case KEY_ESCAPE:
        handled = CPUT_EVENT_HANDLED;
        Shutdown();
        break;
    }

    if((handled == CPUT_EVENT_UNHANDLED) && mpCameraController)
    {
        handled = mpCameraController->HandleKeyboardEvent(key);
    }

    if((handled == CPUT_EVENT_UNHANDLED) && m_pLightController)
    {
        handled = m_pLightController->HandleKeyboardEvent(key);
    }

    return handled;
}

// Handle mouse events
//-----------------------------------------------------------------------------
CPUTEventHandledCode CLightScatteringSample::HandleMouseEvent(int x, int y, int wheel, CPUTMouseState state)
{
    CPUTEventHandledCode handled = CPUT_EVENT_UNHANDLED;
    if( mpCameraController )
    {
        handled = mpCameraController->HandleMouseEvent(x,y,wheel, state);
    }
    if( (handled == CPUT_EVENT_UNHANDLED) && m_pLightController )
    {
        handled = m_pLightController->HandleMouseEvent(x,y,wheel, state);
    }
    return handled;
}

bool SelectColor(D3DXVECTOR4 &f4Color)
{
    // Create an initial color from the current value
    COLORREF InitColor = RGB( f4Color.x * 255.f, f4Color.y * 255.f, f4Color.z * 255.f );
    COLORREF CustomColors[16];
    // Now create a choose color structure with the original color as the default
    CHOOSECOLOR ChooseColorInitStruct;
    ZeroMemory( &ChooseColorInitStruct, sizeof(ChooseColorInitStruct));
    CPUTOSServices::GetOSServices()->GetWindowHandle( &ChooseColorInitStruct.hwndOwner );
    ChooseColorInitStruct.lStructSize = sizeof(ChooseColorInitStruct);
    ChooseColorInitStruct.rgbResult = InitColor;
    ChooseColorInitStruct.Flags = CC_ANYCOLOR | CC_FULLOPEN | CC_RGBINIT;
    ChooseColorInitStruct.lpCustColors = CustomColors;
    // Display a color selection dialog box and if the user does not cancel, select a color
    if( ChooseColor( &ChooseColorInitStruct ) && ChooseColorInitStruct.rgbResult != 0)
    {
        // Get the new color
        COLORREF NewColor = ChooseColorInitStruct.rgbResult;
        f4Color.x = (float)(NewColor&0x0FF) / 255.f;
        f4Color.y = (float)((NewColor>>8)&0x0FF) / 255.f;
        f4Color.z = (float)((NewColor>>16)&0x0FF) / 255.f;
        f4Color.w = 0;
        return true;
    }

    return false;
}

// Handle any control callback events
//-----------------------------------------------------------------------------
void CLightScatteringSample::HandleCallbackEvent( CPUTEventID Event, CPUTControlID ControlID, CPUTControl* pControl )
{
    cString SelectedItem;
    CPUTGuiControllerDX11*  pGUI            = CPUTGetGuiController();   
    switch(ControlID)
    {
    case ID_FULLSCREEN_BUTTON:
        CPUTToggleFullScreenMode();
        pGUI->GetControl(ID_RLGH_COLOR_BTN)->SetEnable(!CPUTGetFullscreenState());
        pGUI->GetControl(ID_MIE_COLOR_BTN)->SetEnable(!CPUTGetFullscreenState());
        pGUI->GetControl(ID_POINT_LIGHT_COLOR_BTN)->SetEnable(!CPUTGetFullscreenState() && (m_PPAttribs.m_uiLightType == LIGHT_TYPE_SPOT || m_PPAttribs.m_uiLightType == LIGHT_TYPE_POINT));
        break;

    case ID_ENABLE_LIGHT_SCATTERING:
        {
            CPUTCheckbox *pCheckBox = static_cast<CPUTCheckbox*>(pControl);
            m_bEnableLightScattering = pCheckBox->GetCheckboxState() == CPUT_CHECKBOX_CHECKED;
            break;
        }

    case ID_LIGHT_SCTR_TECHNIQUE:
        {
            CPUTDropdown* pDropDown = static_cast<CPUTDropdown*>(pControl);
            UINT uiSelectedItem;
            pDropDown->GetSelectedItem(uiSelectedItem);
            m_PPAttribs.m_uiLightSctrTechnique = uiSelectedItem;
            break;
        }

    case ID_LIGHT_TYPE:
        {
            CPUTDropdown* pDropDown = static_cast<CPUTDropdown*>(pControl);
            UINT uiSelectedItem;
            pDropDown->GetSelectedItem(uiSelectedItem);
            m_PPAttribs.m_uiLightType = uiSelectedItem;
            // We need to re-generate shadow map
            m_f3PrevDirOnLight = m_f3PrevSpotLightAxis = D3DXVECTOR3(0,0,0);
            m_pLightController->SetCamera( (m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL) ? m_pDirLightOrienationCamera : m_pSpotLightOrienationCamera );
            mpCameraController->SetCamera( m_pViewCameras[m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL ? 0 : 1] );
            pGUI->GetControl(ID_SHOW_STAINED_GLASS)->SetEnable(m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL);
            pGUI->GetControl(ID_POINT_LIGHT_COLOR_BTN)->SetEnable(!CPUTGetFullscreenState() && (m_PPAttribs.m_uiLightType == LIGHT_TYPE_SPOT || m_PPAttribs.m_uiLightType == LIGHT_TYPE_POINT));
            pGUI->GetControl(ID_SPOT_LIGHT_ANGLE_SLIDER)->SetEnable(m_PPAttribs.m_uiLightType == LIGHT_TYPE_SPOT);
            pGUI->GetControl(ID_INSCTR_INTGL_EVAL_METHOD)->SetEnable( m_PPAttribs.m_uiLightType == LIGHT_TYPE_SPOT || m_PPAttribs.m_uiLightType == LIGHT_TYPE_POINT );
            m_PPAttribs.m_bStainedGlass = ( ((CPUTCheckbox*)pGUI->GetControl(ID_SHOW_STAINED_GLASS))->GetCheckboxState() == CPUT_CHECKBOX_CHECKED ) && (m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL);
            break;
        }

    case ID_SHADOW_MAP_RESOLUTION:
        {
            CPUTDropdown* pDropDown = static_cast<CPUTDropdown*>(pControl);
            UINT uiSelectedItem;
            pDropDown->GetSelectedItem(uiSelectedItem);
            // uiSelectedItem is 1-based
            m_uiShadowMapResolution = 512 << uiSelectedItem;
            CreateAuxTextures(mpD3dDevice);
            // We need to re-generate shadow map
            m_f3PrevDirOnLight = m_f3PrevSpotLightAxis = D3DXVECTOR3(0,0,0);
            break;
        }

    case ID_NUM_EPIPOLAR_SLICES:
        {
            CPUTSlider* pSlider = static_cast<CPUTSlider*>(pControl);
            float fSliderVal;
            pSlider->GetValue(fSliderVal);
            m_PPAttribs.m_uiNumEpipolarSlices = 1 << (int)fSliderVal;
            std::wstringstream NumSlicesSS;
            NumSlicesSS << "Epipolar slices: " << m_PPAttribs.m_uiNumEpipolarSlices;
            pSlider->SetText( NumSlicesSS.str().c_str() );
            break;
        }

    case ID_NUM_SAMPLES_IN_EPIPOLAR_SLICE:
        {
            CPUTSlider* pNumSamplesSlider = static_cast<CPUTSlider*>(pControl);
            float fSliderVal;
            pNumSamplesSlider->GetValue(fSliderVal);
            m_PPAttribs.m_uiMaxSamplesInSlice = 1 << (int)fSliderVal;
            std::wstringstream NumSamplesSS;
            NumSamplesSS << "Total samples in slice: " << m_PPAttribs.m_uiMaxSamplesInSlice;
            pNumSamplesSlider->SetText( NumSamplesSS.str().c_str() );

            {
                CPUTSlider* pInitialSamplesSlider = static_cast<CPUTSlider*>(pGUI->GetControl(ID_INITIAL_SAMPLE_STEP_IN_EPIPOLAR_SLICE));
                unsigned long ulStartVal=0, ulEndVal, ulCurrVal;
                BitScanForward(&ulEndVal, m_PPAttribs.m_uiMaxSamplesInSlice / m_iMinInitialSamplesInEpipolarSlice);
                pInitialSamplesSlider->SetScale( (float)ulStartVal, (float)ulEndVal, ulEndVal-ulStartVal+1 );
                if( m_PPAttribs.m_uiInitialSampleStepInSlice > (1u<<ulEndVal) )
                {
                    m_PPAttribs.m_uiInitialSampleStepInSlice = 1 << ulEndVal;
                    std::wstringstream InitialSamplesStepSS;
                    InitialSamplesStepSS << "Initial sample step: " << m_PPAttribs.m_uiInitialSampleStepInSlice;
                    pInitialSamplesSlider->SetText( InitialSamplesStepSS.str().c_str() );
                }
                BitScanForward(&ulCurrVal, m_PPAttribs.m_uiInitialSampleStepInSlice);
                pInitialSamplesSlider->SetValue( (float)ulCurrVal );
            }
            break;
        }

    case ID_INITIAL_SAMPLE_STEP_IN_EPIPOLAR_SLICE:
        {
            CPUTSlider* pSlider = static_cast<CPUTSlider*>(pControl);
            float fSliderVal;
            pSlider->GetValue(fSliderVal);
            m_PPAttribs.m_uiInitialSampleStepInSlice = 1 << (int)fSliderVal;
            std::wstringstream InitialSamplesStepSS;
            InitialSamplesStepSS << "Initial sample step: " << m_PPAttribs.m_uiInitialSampleStepInSlice;
            pSlider->SetText( InitialSamplesStepSS.str().c_str() );

            break;
        }

    case ID_EPIPOLE_SAMPLING_DENSITY_FACTOR:
        {
            CPUTSlider* pSlider = static_cast<CPUTSlider*>(pControl);
            float fSliderVal;
            pSlider->GetValue(fSliderVal);
            m_PPAttribs.m_uiEpipoleSamplingDensityFactor = 1 << (int)fSliderVal;
            std::wstringstream EpipoleSamplingDensitySS;
            EpipoleSamplingDensitySS << "Epipole sampling density: " << m_PPAttribs.m_uiEpipoleSamplingDensityFactor;
            pSlider->SetText( EpipoleSamplingDensitySS.str().c_str() );

            break;
        }

    case ID_REFINEMENT_THRESHOLD:
        {
            CPUTSlider* pSlider = static_cast<CPUTSlider*>(pControl);
            pSlider->GetValue(m_PPAttribs.m_fRefinementThreshold);
            m_PPAttribs.m_fRefinementThreshold *= GetSceneExtent();
            break;
        }

    case ID_DOWNSCALE_FACTOR:
        {
            CPUTSlider* pSlider = static_cast<CPUTSlider*>(pControl);
            pSlider->GetValue(m_PPAttribs.m_fDownscaleFactor);
            std::wstringstream DownscaleFactorSS;
            DownscaleFactorSS.precision(2);
            DownscaleFactorSS.setf( std::ios_base::fixed );
            DownscaleFactorSS << "Downscale factor: " << m_PPAttribs.m_fDownscaleFactor;
            pSlider->SetText( DownscaleFactorSS.str().c_str() );
            break;
        }

    case ID_SHOW_SAMPLING:
        {
            CPUTCheckbox *pCheckBox = static_cast<CPUTCheckbox*>(pControl);
            m_PPAttribs.m_bShowSampling = pCheckBox->GetCheckboxState() == CPUT_CHECKBOX_CHECKED;
            break;
        }

    case ID_MIN_MAX_SHADOW_MAP_OPTIMIZATION:
        {
            CPUTDropdown *pDropDown = static_cast<CPUTDropdown*>(pControl);
            UINT uiSelectedItem;
            pDropDown->GetSelectedItem(uiSelectedItem);
            m_PPAttribs.m_uiAccelStruct = uiSelectedItem;
            break;
        }

    case ID_INSCTR_INTGL_EVAL_METHOD:
        {
            CPUTDropdown *pDropDown = static_cast<CPUTDropdown*>(pControl);
            UINT uiSelectedItem;
            pDropDown->GetSelectedItem(uiSelectedItem);
            m_PPAttribs.m_uiInsctrIntglEvalMethod = uiSelectedItem;
            break;
        }

    case ID_CORRECT_SCATTERING_AT_DEPTH_BREAKS:
        {
            CPUTCheckbox *pCheckBox = static_cast<CPUTCheckbox*>(pControl);
            m_PPAttribs.m_bCorrectScatteringAtDepthBreaks = pCheckBox->GetCheckboxState() == CPUT_CHECKBOX_CHECKED;
            break;
        }

    case ID_LIGHT_INTENSITY:
        {
            CPUTSlider* pSlider = static_cast<CPUTSlider*>(pControl);
            pSlider->GetValue(m_fLightIntensity);
            break;
        }

    case ID_EXPOSURE:
        {
            CPUTSlider* pSlider = static_cast<CPUTSlider*>(pControl);
            pSlider->GetValue(m_PPAttribs.m_fExposure);
            break;
        }

    case ID_OPTIMIZE_SAMPLE_LOCATIONS:
        {
            CPUTCheckbox *pCheckBox = static_cast<CPUTCheckbox*>(pControl);
            m_PPAttribs.m_bOptimizeSampleLocations = pCheckBox->GetCheckboxState() == CPUT_CHECKBOX_CHECKED;
            break;
        }

    case ID_SHOW_DEPTH_BREAKS:
        {
            CPUTCheckbox *pCheckBox = static_cast<CPUTCheckbox*>(pControl);
            m_PPAttribs.m_bShowDepthBreaks = pCheckBox->GetCheckboxState() == CPUT_CHECKBOX_CHECKED;
            break;
        }

    case ID_SHOW_STAINED_GLASS:
        {
            CPUTCheckbox *pCheckBox = static_cast<CPUTCheckbox*>(pControl);
            m_PPAttribs.m_bStainedGlass = pCheckBox->GetCheckboxState() == CPUT_CHECKBOX_CHECKED;
			if( m_PPAttribs.m_bStainedGlass )
            {
				// We need to re-generate shadow map
				m_f3PrevDirOnLight = m_f3PrevSpotLightAxis = D3DXVECTOR3(0,0,0);
            }
            else
            {
                // Clear stained glass depth so that stained glass color does not affect the shading
                mpContext->ClearDepthStencilView(m_pStainedGlassDepth->GetDepthBufferView(), D3D11_CLEAR_DEPTH, 0.f, 0);
            }
            break;
        }

    case ID_ANISOTROPIC_PHASE_FUNC:
        {
            CPUTCheckbox *pCheckBox = static_cast<CPUTCheckbox*>(pControl);
            m_PPAttribs.m_bAnisotropicPhaseFunction = pCheckBox->GetCheckboxState() == CPUT_CHECKBOX_CHECKED;
            break;
        }

    case ID_SHOW_LIGHTING_ONLY_CHECK:
        {
            CPUTCheckbox *pCheckBox = static_cast<CPUTCheckbox*>(pControl);
            m_PPAttribs.m_bShowLightingOnly = pCheckBox->GetCheckboxState() == CPUT_CHECKBOX_CHECKED;
            break;
        }

    case ID_RLGH_COLOR_BTN:
        {
            D3DXVECTOR4 f4RlghColor = m_PPAttribs.m_f4RayleighBeta / SPostProcessingAttribs().m_f4RayleighBeta.z;
            if( SelectColor(f4RlghColor ) )
            {
                m_PPAttribs.m_f4RayleighBeta = f4RlghColor * SPostProcessingAttribs().m_f4RayleighBeta.z;
            }
            break;
        }

    case ID_MIE_COLOR_BTN:
        {
            D3DXVECTOR4 f4MieColor = m_PPAttribs.m_f4MieBeta / SPostProcessingAttribs().m_f4MieBeta.x;
            if( SelectColor(f4MieColor ) )
            {
                m_PPAttribs.m_f4MieBeta = f4MieColor * SPostProcessingAttribs().m_f4MieBeta.x;
            }
            break;
        }

    case ID_POINT_LIGHT_COLOR_BTN:
        {
            SelectColor(m_f4LightColor);
            break;
        }

    case ID_SPOT_LIGHT_ANGLE_SLIDER:
        {
            CPUTSlider* pSlider = static_cast<CPUTSlider*>(pControl);
            pSlider->GetValue(m_fSpotLightAngle);
            m_pSpotLightCamera->SetFov( m_fSpotLightAngle * 2.f );
            break;
        }

    default:
        break;
    }
}

// Handle resize events
//-----------------------------------------------------------------------------
void CLightScatteringSample::ResizeWindow(UINT width, UINT height)
{
    if( width == 0 || height == 0 )
        return;
    
    // Before we can resize the swap chain, we must release any references to it.
    // We could have a "AssetLibrary::ReleaseSwapChainResources(), or similar.  But,
    // Generic "release all" works, is simpler to implement/maintain, and is not performance critical.
    //pAssetLibrary->ReleaseTexturesAndBuffers();

    CPUT_DX11::ResizeWindow( width, height );

    for(int iCam = 0; iCam < _countof(m_pViewCameras); ++iCam)
        m_pViewCameras[iCam]->SetAspectRatio(((float)width)/((float)height));

    m_pLightSctrPP->OnResizedSwapChain(mpD3dDevice, width, height );
    m_pOffscreenRenderTarget->RecreateRenderTarget(width, height);
    m_pOffscreenDepth->RecreateRenderTarget(width, height);

    //pAssetLibrary->RebindTexturesAndBuffers();
}


void CLightScatteringSample::ReleaseTmpBackBuffAndDepthBuff()
{
    SAFE_DELETE(m_pOffscreenRenderTarget);
    SAFE_DELETE(m_pOffscreenDepth);
}

HRESULT CLightScatteringSample::CreateTmpBackBuffAndDepthBuff(ID3D11Device* pd3dDevice)
{
    ReleaseTmpBackBuffAndDepthBuff();

    DXGI_SWAP_CHAIN_DESC SwapChainDesc;
    mpSwapChain->GetDesc(&SwapChainDesc);

    SAFE_DELETE(m_pOffscreenRenderTarget);
    m_pOffscreenRenderTarget = new CPUTRenderTargetColor();
    m_pOffscreenRenderTarget->CreateRenderTarget( 
        cString( _L("OffscreenRenderTarget") ),
        SwapChainDesc.BufferDesc.Width,                                 //UINT Width
        SwapChainDesc.BufferDesc.Height,                                //UINT Height
        DXGI_FORMAT_R8G8B8A8_UNORM_SRGB);

    SAFE_DELETE(m_pOffscreenDepth);
    m_pOffscreenDepth = new CPUTRenderTargetDepth();
    m_pOffscreenDepth->CreateRenderTarget( 
        cString( _L("OffscreenDepthBuffer") ),
        SwapChainDesc.BufferDesc.Width,                                 //UINT Width
        SwapChainDesc.BufferDesc.Height,                                //UINT Height
        DXGI_FORMAT_D32_FLOAT ); 


    return D3D_OK;
}

void CLightScatteringSample::ReleaseAuxTextures()
{
    // Check for the existance of a shadow map buffer and if it exists, destroy it and set its pointer to NULL

    // Release the light space depth shader resource and depth stencil views
    SAFE_DELETE(m_pShadowMap);
    SAFE_DELETE(m_pStainedGlassMap);
    SAFE_DELETE(m_pStainedGlassDepth);
}

HRESULT CLightScatteringSample::CreateAuxTextures(ID3D11Device* pd3dDevice)
{
    HRESULT hr;

    if( !m_pShadowMap )
    {
        m_pShadowMap = new CPUTRenderTargetDepth();
        hr = m_pShadowMap->CreateRenderTarget( 
            cString( _L("$shadow_depth") ),
            m_uiShadowMapResolution,                                 //UINT Width
            m_uiShadowMapResolution,                                 //UINT Height
            DXGI_FORMAT_D32_FLOAT );
    }
    else
        m_pShadowMap->RecreateRenderTarget(m_uiShadowMapResolution, m_uiShadowMapResolution);

    if( !m_pStainedGlassMap )
    {
        m_pStainedGlassMap = new CPUTRenderTargetColor();
        hr = m_pStainedGlassMap->CreateRenderTarget( 
            cString( _L("$StainedGlass") ),
            m_uiShadowMapResolution,                                 //UINT Width
            m_uiShadowMapResolution,                                 //UINT Height
            DXGI_FORMAT_R16G16B16A16_UNORM );
    }
    else
        m_pStainedGlassMap->RecreateRenderTarget(m_uiShadowMapResolution, m_uiShadowMapResolution);
    
    if( !m_pStainedGlassDepth )
    {
        m_pStainedGlassDepth = new CPUTRenderTargetDepth();
        hr = m_pStainedGlassDepth->CreateRenderTarget( 
            cString( _L("$StainedGlassDepth") ),
            m_uiShadowMapResolution,                                 //UINT Width
            m_uiShadowMapResolution,                                 //UINT Height
            DXGI_FORMAT_D32_FLOAT );
    }
    else
        m_pStainedGlassDepth->RecreateRenderTarget(m_uiShadowMapResolution, m_uiShadowMapResolution);
    mpContext->ClearDepthStencilView(m_pStainedGlassDepth->GetDepthBufferView(), D3D11_CLEAR_DEPTH, 0.f, 0);

    CPUTAssetLibrary *pAssetLibrary = CPUTAssetLibrary::GetAssetLibrary();
    pAssetLibrary->RebindTexturesAndBuffers();

    return D3D_OK;
}

float CLightScatteringSample::GetSceneExtent()
{
    return D3DXVec3Length( &(m_pvSceneBoundBoxCorners[0]-m_pvSceneBoundBoxCorners[7]) );
}

// Handle OnCreation events
//-----------------------------------------------------------------------------
void CLightScatteringSample::Create()
{    
    CPUTAssetLibrary*       pAssetLibrary   = CPUTAssetLibrary::GetAssetLibrary();
    CPUTGuiControllerDX11*  pGUI            = CPUTGetGuiController();

    pGUI->DrawFPS(true);
    /*
    * Initialize GUI
    */

    //
    // Create buttons
    //
    CPUTButton* pButton = NULL;
    pGUI->CreateButton(_L("Fullscreen"), ID_FULLSCREEN_BUTTON, ID_MAIN_PANEL, &pButton);

    {
        CPUTCheckbox *pCheckBox = NULL;
        pGUI->CreateCheckbox( L"Enable light scattering", ID_ENABLE_LIGHT_SCATTERING, ID_MAIN_PANEL, &pCheckBox);
        pCheckBox->SetCheckboxState( m_bEnableLightScattering ? CPUT_CHECKBOX_CHECKED : CPUT_CHECKBOX_UNCHECKED );
    }

    {
        CPUTDropdown* pDropDown = NULL;
        pGUI->CreateDropdown( L"Epipolar sampling", ID_LIGHT_SCTR_TECHNIQUE, ID_MAIN_PANEL, &pDropDown);
        pDropDown->AddSelectionItem( L"Brute force ray marching" );
        // SelectedItem is 1-based
        pDropDown->SetSelectedItem(m_PPAttribs.m_uiLightSctrTechnique+1);
    }

    {
        CPUTDropdown* pDropDown = NULL;
        pGUI->CreateDropdown( L"Light type: directional", ID_LIGHT_TYPE, ID_MAIN_PANEL, &pDropDown);
        pDropDown->AddSelectionItem( L"Light type: spot" );
        //pDropDown->AddSelectionItem( L"Light type: point" );
        // SelectedItem is 1-based
        pDropDown->SetSelectedItem(m_PPAttribs.m_uiLightType+1);
    }

    {
        CPUTDropdown* pDropDown = NULL;
        pGUI->CreateDropdown( L"Shadow Map res: 512x512", ID_SHADOW_MAP_RESOLUTION, ID_MAIN_PANEL, &pDropDown);
        pDropDown->AddSelectionItem( L"Shadow Map res: 1024x1024" );
        pDropDown->AddSelectionItem( L"Shadow Map res: 2048x2048" );
        pDropDown->AddSelectionItem( L"Shadow Map res: 4096x4096" );
        unsigned long ulCurrVal;
        BitScanForward(&ulCurrVal, m_uiShadowMapResolution);
        // SelectedItem is 1-based
        pDropDown->SetSelectedItem(ulCurrVal-9 + 1);
    }

    {
        CPUTSlider* pSlider = NULL;
        std::wstringstream NumSlicesSS;
        NumSlicesSS << "Epipolar slices: " << m_PPAttribs.m_uiNumEpipolarSlices;
        pGUI->CreateSlider( NumSlicesSS.str().c_str(), ID_NUM_EPIPOLAR_SLICES, ID_MAIN_PANEL, &pSlider);

        unsigned long ulStartVal, ulEndVal, ulCurrVal;
        BitScanForward(&ulStartVal, m_iMinEpipolarSlices);
        BitScanForward(&ulEndVal, m_iMaxEpipolarSlices);
        pSlider->SetScale( (float)ulStartVal, (float)ulEndVal, ulEndVal-ulStartVal+1 );

        BitScanForward(&ulCurrVal, m_PPAttribs.m_uiNumEpipolarSlices);
        pSlider->SetValue( (float)ulCurrVal );
    }

    {
        CPUTSlider* pSlider = NULL;
        std::wstringstream NumSamplesSS;
        NumSamplesSS << "Total samples in slice: " << m_PPAttribs.m_uiMaxSamplesInSlice;
        pGUI->CreateSlider( NumSamplesSS.str().c_str(), ID_NUM_SAMPLES_IN_EPIPOLAR_SLICE, ID_MAIN_PANEL, &pSlider);

        unsigned long ulStartVal, ulEndVal, ulCurrVal;
        BitScanForward(&ulStartVal, m_iMinSamplesInEpipolarSlice);
        BitScanForward(&ulEndVal, m_iMaxSamplesInEpipolarSlice);
        pSlider->SetScale( (float)ulStartVal, (float)ulEndVal, ulEndVal-ulStartVal+1 );

        BitScanForward(&ulCurrVal, m_PPAttribs.m_uiMaxSamplesInSlice);
        pSlider->SetValue( (float)ulCurrVal );
    }

    {
        CPUTSlider* pSlider = NULL;
        std::wstringstream InitialSamplesStepSS;
        InitialSamplesStepSS << "Initial sample step: " << m_PPAttribs.m_uiInitialSampleStepInSlice;
        pGUI->CreateSlider( InitialSamplesStepSS.str().c_str(), ID_INITIAL_SAMPLE_STEP_IN_EPIPOLAR_SLICE, ID_MAIN_PANEL, &pSlider);

        unsigned long ulStartVal=0, ulEndVal, ulCurrVal;
        BitScanForward(&ulEndVal, m_PPAttribs.m_uiMaxSamplesInSlice / m_iMinInitialSamplesInEpipolarSlice);
        pSlider->SetScale( (float)ulStartVal, (float)ulEndVal, ulEndVal-ulStartVal+1 );

        BitScanForward(&ulCurrVal, m_PPAttribs.m_uiInitialSampleStepInSlice);
        pSlider->SetValue( (float)ulCurrVal );
    }

    {
        CPUTSlider* pSlider = NULL;
        std::wstringstream EpipoleSamplingDensitySS;
        EpipoleSamplingDensitySS << "Epipole sampling density: " << m_PPAttribs.m_uiEpipoleSamplingDensityFactor;
        pGUI->CreateSlider( EpipoleSamplingDensitySS.str().c_str(), ID_EPIPOLE_SAMPLING_DENSITY_FACTOR, ID_MAIN_PANEL, &pSlider);

        unsigned long ulStartVal=0, ulEndVal, ulCurrVal;
        BitScanForward(&ulEndVal, m_iMaxEpipoleSamplingDensityFactor);
        pSlider->SetScale( (float)ulStartVal, (float)ulEndVal, ulEndVal-ulStartVal+1 );

        BitScanForward(&ulCurrVal, m_PPAttribs.m_uiEpipoleSamplingDensityFactor);
        pSlider->SetValue( (float)ulCurrVal );
    }

    {
        CPUTSlider* pSlider = NULL;
        pGUI->CreateSlider( L"Refinement threshold", ID_REFINEMENT_THRESHOLD, ID_MAIN_PANEL, &pSlider);
        pSlider->SetScale( 0.005f, 0.1f, 100 );
        pSlider->SetValue( m_PPAttribs.m_fRefinementThreshold );
    }

    {
        CPUTSlider* pSlider = NULL;
        std::wstringstream DownscaleFactorSS;
        DownscaleFactorSS.precision(2);
        DownscaleFactorSS.setf( std::ios_base::fixed );
        DownscaleFactorSS << "Downscale factor: " << m_PPAttribs.m_fDownscaleFactor;
        pGUI->CreateSlider( DownscaleFactorSS.str().c_str(), ID_DOWNSCALE_FACTOR, ID_MAIN_PANEL, &pSlider);
        pSlider->SetScale( 1.f, 8.f, 15 );
        pSlider->SetValue( m_PPAttribs.m_fDownscaleFactor );
    }

    {
        CPUTSlider* pSlider = NULL;
        pGUI->CreateSlider( L"Light intensity", ID_LIGHT_INTENSITY, ID_MAIN_PANEL, &pSlider);
        pSlider->SetScale( 1.f, 50.f, 50 );
        pSlider->SetValue( m_fLightIntensity );
    }

    {
        CPUTSlider* pSlider = NULL;
        pGUI->CreateSlider( L"Exposure", ID_EXPOSURE, ID_MAIN_PANEL, &pSlider);
        pSlider->SetScale( 0.2f, 5.f, 50 );
        pSlider->SetValue( m_PPAttribs.m_fExposure );
    }

    {
        CPUTCheckbox *pCheckBox = NULL;
        pGUI->CreateCheckbox( L"Show sampling", ID_SHOW_SAMPLING, ID_MAIN_PANEL, &pCheckBox);
        pCheckBox->SetCheckboxState( m_PPAttribs.m_bShowSampling ? CPUT_CHECKBOX_CHECKED : CPUT_CHECKBOX_UNCHECKED );
    }

    {
        CPUTDropdown* pDropDown = NULL;
        pGUI->CreateDropdown( L"Acceleration: none", ID_MIN_MAX_SHADOW_MAP_OPTIMIZATION, ID_MAIN_PANEL, &pDropDown);
        pDropDown->AddSelectionItem( L"Acceleration: min/max tree" );
        //pDropDown->AddSelectionItem( L"Acceleration: BV tree" );
        // SelectedItem is 1-based
        pDropDown->SetSelectedItem(m_PPAttribs.m_uiAccelStruct + 1);
    }

    {
        CPUTDropdown* pDropDown = NULL;
        pGUI->CreateDropdown( L"Insctr integral: My LUT", ID_INSCTR_INTGL_EVAL_METHOD, ID_MAIN_PANEL, &pDropDown);
        pDropDown->AddSelectionItem( L"Insctr integral: Sun et al." );
        pDropDown->AddSelectionItem( L"Insctr integral: Analytic." );
        // SelectedItem is 1-based
        pDropDown->SetSelectedItem(m_PPAttribs.m_uiInsctrIntglEvalMethod + 1);
        pDropDown->SetEnable( m_PPAttribs.m_uiLightType == LIGHT_TYPE_SPOT || m_PPAttribs.m_uiLightType == LIGHT_TYPE_POINT );
    }

    {
        CPUTCheckbox *pCheckBox = NULL;
        pGUI->CreateCheckbox( L"Optimize sample locations", ID_OPTIMIZE_SAMPLE_LOCATIONS, ID_MAIN_PANEL, &pCheckBox);
        pCheckBox->SetCheckboxState( m_PPAttribs.m_bOptimizeSampleLocations ? CPUT_CHECKBOX_CHECKED : CPUT_CHECKBOX_UNCHECKED );
    }

    {
        CPUTCheckbox *pCheckBox = NULL;
        pGUI->CreateCheckbox( L"Correction at depth breaks", ID_CORRECT_SCATTERING_AT_DEPTH_BREAKS, ID_MAIN_PANEL, &pCheckBox);
        pCheckBox->SetCheckboxState( m_PPAttribs.m_bCorrectScatteringAtDepthBreaks ? CPUT_CHECKBOX_CHECKED : CPUT_CHECKBOX_UNCHECKED );
    }

    {
        CPUTCheckbox *pCheckBox = NULL;
        pGUI->CreateCheckbox( L"Show depth breaks", ID_SHOW_DEPTH_BREAKS, ID_MAIN_PANEL, &pCheckBox);
        pCheckBox->SetCheckboxState( m_PPAttribs.m_bShowDepthBreaks ? CPUT_CHECKBOX_CHECKED : CPUT_CHECKBOX_UNCHECKED );
    }

    {
        CPUTCheckbox *pCheckBox = NULL;
        pGUI->CreateCheckbox( L"Stained glass", ID_SHOW_STAINED_GLASS, ID_MAIN_PANEL, &pCheckBox);
        pCheckBox->SetCheckboxState( m_PPAttribs.m_bStainedGlass ? CPUT_CHECKBOX_CHECKED : CPUT_CHECKBOX_UNCHECKED );
        pCheckBox->SetEnable( m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL );
    }

    {
        CPUTCheckbox *pCheckBox = NULL;
        pGUI->CreateCheckbox( L"Anisotropic phase func", ID_ANISOTROPIC_PHASE_FUNC, ID_MAIN_PANEL, &pCheckBox);
        pCheckBox->SetCheckboxState( m_PPAttribs.m_bAnisotropicPhaseFunction ? CPUT_CHECKBOX_CHECKED : CPUT_CHECKBOX_UNCHECKED );
    }

    {
        CPUTCheckbox *pCheckBox = NULL;
        pGUI->CreateCheckbox( L"Lighting only", ID_SHOW_LIGHTING_ONLY_CHECK, ID_MAIN_PANEL, &pCheckBox);
        pCheckBox->SetCheckboxState( m_PPAttribs.m_bShowLightingOnly ? CPUT_CHECKBOX_CHECKED : CPUT_CHECKBOX_UNCHECKED );
    }

    {
        CPUTButton *pBtn = NULL;
        pGUI->CreateButton( L"Set Rayleigh color", ID_RLGH_COLOR_BTN, ID_MAIN_PANEL, &pBtn);
        pBtn->SetEnable(!CPUTGetFullscreenState());
    }

    {
        CPUTButton *pBtn = NULL;
        pGUI->CreateButton( L"Set Mie color", ID_MIE_COLOR_BTN, ID_MAIN_PANEL, &pBtn);
        pBtn->SetEnable(!CPUTGetFullscreenState());
    }

    {
        CPUTButton *pBtn = NULL;
        pGUI->CreateButton( L"Set spot light color", ID_POINT_LIGHT_COLOR_BTN, ID_MAIN_PANEL, &pBtn);
        pBtn->SetEnable( !CPUTGetFullscreenState() && (m_PPAttribs.m_uiLightType == LIGHT_TYPE_SPOT || m_PPAttribs.m_uiLightType == LIGHT_TYPE_POINT) );
    }

    {
        CPUTSlider* pSlider = NULL;
        pGUI->CreateSlider( L"Spot light angle", ID_SPOT_LIGHT_ANGLE_SLIDER, ID_MAIN_PANEL, &pSlider);
        pSlider->SetScale( D3DX_PI/12, D3DX_PI/4, 50 );
        pSlider->SetValue( m_fSpotLightAngle );
        pSlider->SetEnable( m_PPAttribs.m_uiLightType == LIGHT_TYPE_SPOT);
    }

    pGUI->CreateText( _L("F1 for Help"), ID_IGNORE_CONTROL_ID, ID_SECONDARY_PANEL);
    pGUI->CreateText( _L("[Escape] to quit application"), ID_IGNORE_CONTROL_ID, ID_SECONDARY_PANEL);
    pGUI->CreateText( _L("A,S,D,F - move camera position"), ID_IGNORE_CONTROL_ID, ID_SECONDARY_PANEL);
    pGUI->CreateText( _L("Q - camera position down"), ID_IGNORE_CONTROL_ID, ID_SECONDARY_PANEL);
    pGUI->CreateText( _L("E - camera position up"), ID_IGNORE_CONTROL_ID, ID_SECONDARY_PANEL);
    pGUI->CreateText( _L("[Shift] - accelerate camera movement"), ID_IGNORE_CONTROL_ID, ID_SECONDARY_PANEL);
    pGUI->CreateText( _L("mouse + left click - camera look rotation"), ID_IGNORE_CONTROL_ID, ID_SECONDARY_PANEL);
    pGUI->CreateText( _L("mouse + right click - light rotation"), ID_IGNORE_CONTROL_ID, ID_SECONDARY_PANEL);

    //
    // Make the main panel active
    //
    pGUI->SetActivePanel(ID_MAIN_PANEL);

    CreateTmpBackBuffAndDepthBuff(mpD3dDevice);

    // Create shadow map before other assets!!!
    HRESULT hResult = CreateAuxTextures(mpD3dDevice);
    if( FAILED( hResult ) )
        return;

    pAssetLibrary->SetMediaDirectoryName(  _L("Media\\"));

    // Add our programatic (and global) material parameters
    CPUTMaterial::mGlobalProperties.AddValue( _L("cbPerFrameValues"), _L("$cbPerFrameValues") );
    CPUTMaterial::mGlobalProperties.AddValue( _L("cbPerModelValues"), _L("#cbPerModelValues") );

    // Create default shaders
    CPUTPixelShaderDX11  *pPS       = CPUTPixelShaderDX11::CreatePixelShaderFromMemory(            _L("$DefaultShader"), mpD3dDevice,          _L("PSMain"), _L("ps_4_0"), gpDefaultShaderSource );
    CPUTPixelShaderDX11  *pPSNoTex  = CPUTPixelShaderDX11::CreatePixelShaderFromMemory(   _L("$DefaultShaderNoTexture"), mpD3dDevice, _L("PSMainNoTexture"), _L("ps_4_0"), gpDefaultShaderSource );
    CPUTVertexShaderDX11 *pVS       = CPUTVertexShaderDX11::CreateVertexShaderFromMemory(          _L("$DefaultShader"), mpD3dDevice,          _L("VSMain"), _L("vs_4_0"), gpDefaultShaderSource );
    CPUTVertexShaderDX11 *pVSNoTex  = CPUTVertexShaderDX11::CreateVertexShaderFromMemory( _L("$DefaultShaderNoTexture"), mpD3dDevice, _L("VSMainNoTexture"), _L("vs_4_0"), gpDefaultShaderSource );

    // We just want to create them, which adds them to the library.  We don't need them any more so release them, leaving refCount at 1 (only library owns a ref)
    SAFE_RELEASE(pPS);
    SAFE_RELEASE(pPSNoTex);
    SAFE_RELEASE(pVS);
    SAFE_RELEASE(pVSNoTex);
    
    int width, height;
    CPUTOSServices::GetOSServices()->GetClientDimensions(&width, &height);

    CPUTRenderStateBlockDX11 *pBlock = new CPUTRenderStateBlockDX11();
    CPUTRenderStateDX11 *pStates = pBlock->GetState();

    // Override default sampler desc for our default shadowing sampler
    pStates->SamplerDesc[1].Filter         = D3D11_FILTER_COMPARISON_MIN_MAG_LINEAR_MIP_POINT;
    pStates->SamplerDesc[1].AddressU       = D3D11_TEXTURE_ADDRESS_BORDER;
    pStates->SamplerDesc[1].AddressV       = D3D11_TEXTURE_ADDRESS_BORDER;
    pStates->SamplerDesc[1].ComparisonFunc = D3D11_COMPARISON_GREATER;
    pBlock->CreateNativeResources();
    CPUTAssetLibrary::GetAssetLibrary()->AddRenderStateBlock( _L("$DefaultRenderStates"), pBlock );
    
    D3D11_BUFFER_DESC CBDesc = 
    {
        sizeof(D3DXVECTOR4)*2,
        D3D11_USAGE_DYNAMIC,
        D3D11_BIND_CONSTANT_BUFFER,
        D3D11_CPU_ACCESS_WRITE, //UINT CPUAccessFlags
        0, //UINT MiscFlags;
        0, //UINT StructureByteStride;
    };
    mpD3dDevice->CreateBuffer( &CBDesc, NULL, &m_pLightAttribsCB);
    CPUTBufferDX11 *pCPUTLightAttribsBuff = new CPUTBufferDX11();
    pCPUTLightAttribsBuff->SetBufferAndViews(m_pLightAttribsCB, NULL, NULL);
    CPUTAssetLibrary::GetAssetLibrary()->AddConstantBuffer( _L("$LightAttribsCB"), pCPUTLightAttribsBuff );
    pCPUTLightAttribsBuff->Release();

    pBlock->Release(); // We're done with it.  The library owns it now.

    // Initialize
    pAssetLibrary->SetAllAssetDirectoryNames(   _L("media/Cage/Asset/")    );
    pAssetLibrary->SetMaterialDirectoryName(    _L("media/Cage/Material/") );
    pAssetLibrary->SetTextureDirectoryName(     _L("media/Cage/Texture/")  );
    pAssetLibrary->SetShaderDirectoryName(      _L("media/Cage/shader/")   );
    m_pCageAssetSet = pAssetLibrary->GetAssetSet( _L("cage_01") );
    m_pKleigAssetSet  = pAssetLibrary->GetAssetSet( _L("kleig") );
    m_pSkyLightAssetSet = pAssetLibrary->GetAssetSet( _L("skyLight") );

    pAssetLibrary->SetAllAssetDirectoryNames(   _L("media/cathedral/Asset/")    );
    pAssetLibrary->SetMaterialDirectoryName(    _L("media/cathedral/Material/") );
    pAssetLibrary->SetTextureDirectoryName(     _L("media/cathedral/Texture/")  );
    pAssetLibrary->SetShaderDirectoryName(      _L("media/shader/")             );

    m_pCathedralAssetSet = pAssetLibrary->GetAssetSet( _L("cathedral_02_noGlass") );
    ASSERT( m_pCathedralAssetSet, _L("Failed loading cathedral.") );

    m_pStainedGlassAssetSet = pAssetLibrary->GetAssetSet( _L("glass_01") );
    ASSERT( m_pStainedGlassAssetSet, _L("Failed loading stained glass.") );

    pAssetLibrary->SetAllAssetDirectoryNames( _L("media/terrain/Asset/")    );
    pAssetLibrary->SetMaterialDirectoryName(  _L("media/terrain/Material/") );
    pAssetLibrary->SetTextureDirectoryName(   _L("media/terrain/Texture/")  );
    pAssetLibrary->SetShaderDirectoryName(    _L("media/shader/")           );
    m_pTerrainAssetSet = pAssetLibrary->GetAssetSet( _L("terrain_01") );
    ASSERT( m_pTerrainAssetSet, _L("Failed loading terrain.") );
    

    // 
    // Create camera
    // 

    for(int iCam = 0; iCam < _countof(m_pViewCameras); ++iCam)
    {
        m_pViewCameras[iCam] = new CPUTCamera;
        m_pViewCameras[iCam]->SetAspectRatio(((float)width)/((float)height));
        m_pViewCameras[iCam]->SetFov(XMConvertToRadians(60.0f));
    }
    
    m_pDirectionalLightCamera = new CParallelLightCamera();
    
    m_pDirLightOrienationCamera = new CParallelLightCamera();
    float4x4 LightOrientationWorld
    (
        0.66866267f, 0.35822296f, 0.65158772f, 0.00000000f,
		0.17569630f, 0.77536952f, -0.60657483f, 0.00000000f,
		-0.72251028f, 0.52007550f, 0.45552221f, 0.00000000f,
		0.086703561f, 1.4985714f, 0.62183738f, 1.0000000f
    );
    m_pDirLightOrienationCamera->SetParentMatrix( LightOrientationWorld );
    m_pDirLightOrienationCamera->Update();

    m_pSpotLightOrienationCamera = new CParallelLightCamera();
    float4x4 SpotLightOrientationWorld
    (
        0.66866267f, 0.35822296f, 0.65158772f, 0.00000000f,
		0.17569630f, 0.77536952f, -0.60657483f, 0.00000000f,
		-0.72251028f, 0.52007550f, 0.45552221f, 0.00000000f,
		0.f, 0.f, 0.f, 1.0f
    );
    m_pSpotLightOrienationCamera->SetParentMatrix( SpotLightOrientationWorld );
    m_pSpotLightOrienationCamera->Update();

    m_pSpotLightCamera = new CPUTCamera;
    m_pSpotLightCamera->SetAspectRatio( 1.f );
    m_pSpotLightCamera->SetFov( m_fSpotLightAngle * 2.f );

    float4x4 CathedralSceneCameraWorld
    (
		0.80447638f,  0.00000000f,  0.59398466f, 0.0000000f,
        0.21147405f,  0.93447608f, -0.28641459f, 0.0000000f,
       -0.55506444f,  0.35602611f,  0.75176394f, 0.0000000f,
        1.8393451f,   0.47897750f, -5.0012612f,  1.0000000f
    );
    m_pViewCameras[0]->SetParentMatrix( CathedralSceneCameraWorld );
    m_pViewCameras[0]->Update();

    float4x4 CageSceneCameraWorld
    (
		 0.94168627f,   0.00000000f,    0.33649212f,    0.00000000f,
        -0.013452680f,  0.99920052f,    0.037647847f,   0.00000000f,
        -0.33622313f,  -0.039979182f,   0.94093347f,    0.00000000f,
         0.79570317f,   5.1007614f,    -6.9957843f,     1.0000000f
    );
    m_pViewCameras[1]->SetParentMatrix( CageSceneCameraWorld );
    m_pViewCameras[1]->Update();

    mpCameraController = new CPUTCameraControllerFPS();
    mpCameraController->SetCamera( m_pViewCameras[m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL ? 0 : 1] );
    mpCameraController->SetLookSpeed(0.002f);
    mpCameraController->SetMoveSpeed(1.0f);

    m_pLightController = new CPUTCameraControllerArcBall();
    m_pLightController->SetCamera( (m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL) ? m_pDirLightOrienationCamera : m_pSpotLightOrienationCamera );
    m_pLightController->SetLookSpeed(0.002f);

    // Call ResizeWindow() because it creates some resources that our blur material needs (e.g., the back buffer)
    ResizeWindow(width, height);

    for(UINT j=0; j < m_pCathedralAssetSet->GetAssetCount(); j++)
    {
        CPUTRenderNode* pRenderNode = NULL;
        m_pCathedralAssetSet->GetAssetByIndex(j, &pRenderNode);
        float3 MeshCenter(0.f), MeshHalf(0.f);
        pRenderNode->GetBoundingBoxRecursive(&MeshCenter, &MeshHalf);
        for(int iBBCorner = 0; iBBCorner < 8; ++iBBCorner)
        {
            const float tmpBoundBoxScale = 2.5f;//( m_Scene == SCENE_CATHEDRAL ) ? 2.5f : 1.f;
            m_pvSceneBoundBoxCorners[iBBCorner].x = MeshCenter.x + (iBBCorner & 0x01 ? 1.f : -1.f) * MeshHalf.x * tmpBoundBoxScale;
            m_pvSceneBoundBoxCorners[iBBCorner].y = MeshCenter.y + (iBBCorner & 0x02 ? 1.f : -1.f) * MeshHalf.y * tmpBoundBoxScale;
            m_pvSceneBoundBoxCorners[iBBCorner].z = MeshCenter.z + (iBBCorner & 0x04 ? 1.f : -1.f) * MeshHalf.z * tmpBoundBoxScale;
        }
        pRenderNode->Release();
    }

    float SceneExtent = GetSceneExtent();

    m_pViewCameras[0]->SetNearPlaneDistance( SceneExtent * 0.001f);
    m_pViewCameras[0]->SetFarPlaneDistance( SceneExtent * 10.f );

    float3 CageSceneCenter, CageSceneHalf;
    m_pCageAssetSet->GetBoundingBox(&CageSceneCenter, &CageSceneHalf);
    float fCageSceneExt = CageSceneHalf.length();
    m_pViewCameras[1]->SetNearPlaneDistance( fCageSceneExt * 0.001f);
    m_pViewCameras[1]->SetFarPlaneDistance( fCageSceneExt * 10.f );

    m_pSpotLightCamera->SetNearPlaneDistance( SceneExtent * 0.001f);
    m_pSpotLightCamera->SetFarPlaneDistance( SceneExtent * 10.f );
    m_pSpotLightCamera->Update();
    m_PPAttribs.m_fRefinementThreshold *= SceneExtent;


    /*
    * Create DX resources
    */ 

    // Initialize the post process object to the device and context
    hResult = m_pLightSctrPP->OnCreateDevice(mpD3dDevice, mpContext);
    if( FAILED( hResult ) )
        return;
}

extern float3 gLightDir;
void CLightScatteringSample::RenderShadowMap(ID3D11DeviceContext *pContext,
                                             const D3DXVECTOR3& v3LightDirection,
											 const D3DXVECTOR3& v3DirOnLight,
                                             const D3DXVECTOR3& vLightPos)
{
    CPUTRenderParametersDX drawParams(pContext);

    CPUTCamera *pLastCamera = mpCamera;

    gLightDir.x = v3LightDirection.x;
    gLightDir.y = v3LightDirection.y;
    gLightDir.z = v3LightDirection.z;

    if( m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL )
    {
        // Declare working vectors
        D3DXVECTOR3 vLightSpaceX, vLightSpaceY, vLightSpaceZ;

        // Compute an inverse vector for the direction on the sun
        vLightSpaceZ = v3LightDirection;
        // And a vector for X light space
        vLightSpaceX = D3DXVECTOR3( 1.0f, 0.0, 0.0 );
        // Compute the cross products
        D3DXVec3Cross(&vLightSpaceY, &vLightSpaceX, &vLightSpaceZ);
        D3DXVec3Cross(&vLightSpaceX, &vLightSpaceZ, &vLightSpaceY);
        // And then normalize them
        D3DXVec3Normalize( &vLightSpaceX, &vLightSpaceX );
        D3DXVec3Normalize( &vLightSpaceY, &vLightSpaceY );
        D3DXVec3Normalize( &vLightSpaceZ, &vLightSpaceZ );

        // Declare a world to light space transformation matrix
        // Initialize to an identity matrix
        D3DXMatrixIdentity( &m_WorldToLightSpaceMatr );
        // Adjust elements to the light space
        m_WorldToLightSpaceMatr._11 = vLightSpaceX.x;
        m_WorldToLightSpaceMatr._21 = vLightSpaceX.y;
        m_WorldToLightSpaceMatr._31 = vLightSpaceX.z;

        m_WorldToLightSpaceMatr._12 = vLightSpaceY.x;
        m_WorldToLightSpaceMatr._22 = vLightSpaceY.y;
        m_WorldToLightSpaceMatr._32 = vLightSpaceY.z;

        m_WorldToLightSpaceMatr._13 = vLightSpaceZ.x;
        m_WorldToLightSpaceMatr._23 = vLightSpaceZ.y;
        m_WorldToLightSpaceMatr._33 = vLightSpaceZ.z;

        // Set reference minimums and maximums for each coordinate
        float MinX = +FLT_MAX;
        float MinY = +FLT_MAX;
        float MinZ = +FLT_MAX;
        float MaxX = -FLT_MAX;
        float MaxY = -FLT_MAX;
        float MaxZ = -FLT_MAX;

        // For each of the eight corners of a cube
        for(int iCornerNum = 0; iCornerNum < 8; iCornerNum++)
        {
            // Declare a vector to represent a corner of the bounding box in light space
            D3DXVECTOR3 BBCornerInLightSpace;
            // Transform the corner by the world to light space transformation matrix
            D3DXVec3TransformCoord(&BBCornerInLightSpace, m_pvSceneBoundBoxCorners + iCornerNum, &m_WorldToLightSpaceMatr);
            // Take the smaller of the reference and the computed parameter for new minimum values
            MinX = min(MinX, BBCornerInLightSpace.x);
            MinY = min(MinY, BBCornerInLightSpace.y);
            MinZ = min(MinZ, BBCornerInLightSpace.z);
            // Take the larger of the refernce and the computed parameter for new maximum values
            MaxX = max(MaxX, BBCornerInLightSpace.x);
            MaxY = max(MaxY, BBCornerInLightSpace.y);
            MaxZ = max(MaxZ, BBCornerInLightSpace.z);
        }

        // Initialilze a left-handed transformation matrix for orthogonal light
        D3DXMatrixOrthoOffCenterLH( &m_LightOrthoMatrix, MinX, MaxX, MinY, MaxY, MaxZ, MinZ);
        //D3DXMatrixOrthoOffCenterLH( &m_LightOrthoMatrix, -20, 20, -20, 20, 20, -20);

        m_pDirectionalLightCamera->SetProjectionMatrix( (float4x4&)m_LightOrthoMatrix );
        D3DXMATRIX LightCameraWorld;
        D3DXMatrixInverse( &LightCameraWorld, NULL, &m_WorldToLightSpaceMatr );
        m_pDirectionalLightCamera->SetParentMatrix( (float4x4&)LightCameraWorld );
        mpCamera = m_pDirectionalLightCamera;
        m_pDirectionalLightCamera->Update();

        // Adjust the world to light space transformation matrix
        m_WorldToLightProjSpaceMatr = m_WorldToLightSpaceMatr * m_LightOrthoMatrix;
        mpShadowCamera = m_pDirectionalLightCamera;
    }
    else
    {
        D3DXMATRIX mProj = (D3DXMATRIX &)*m_pSpotLightCamera->GetProjectionMatrix();
        //D3DXMATRIX mView = (D3DXMATRIX &)*m_pSpotLightOrienationCamera->GetViewMatrix();
        D3DXMATRIX mView, mCameraWorld;
        D3DXVECTOR3 LookAt = vLightPos + v3LightDirection;
        D3DXMatrixLookAtLH( &mView, &vLightPos, &LookAt, &D3DXVECTOR3(0,0,1) );
        D3DXMatrixInverse(&mCameraWorld, NULL, &mView);
        m_WorldToLightProjSpaceMatr = mView * mProj;
        m_pSpotLightCamera->SetParentMatrix( /**m_pSpotLightOrienationCamera->GetParentMatrix() */ (float4x4&)mCameraWorld );
        m_pSpotLightCamera->Update();
        mpShadowCamera = m_pSpotLightCamera;
    }

    m_pShadowMap->SetRenderTarget( drawParams, 0, 0.f, true );

    drawParams.mRenderOnlyVisibleModels = true;
    mpCamera = drawParams.mpCamera = mpShadowCamera;
    if( m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL )
        m_pCathedralAssetSet->RenderShadowRecursive(drawParams);
    else
        m_pCageAssetSet->RenderShadowRecursive(drawParams);

    m_pShadowMap->RestoreRenderTarget( drawParams );

    if( m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL && 
        m_PPAttribs.m_bStainedGlass )
    {
        float pStainedGlassClearColor[4] = {1,1,1,0};
        m_pStainedGlassMap->SetRenderTarget( drawParams, m_pStainedGlassDepth, 0, pStainedGlassClearColor, true, 0.f );
        m_pStainedGlassAssetSet->RenderRecursive(drawParams);
        m_pStainedGlassMap->RestoreRenderTarget( drawParams );
    }

    mpCamera = pLastCamera;
}

//-----------------------------------------------------------------------------
void CLightScatteringSample::Update(double deltaSeconds)
{
    if( mpCameraController )
    {
        mpCameraController->Update( static_cast<float>(deltaSeconds) );
    }
}

static D3DXVECTOR2 ProjToUV(const D3DXVECTOR2& f2ProjSpaceXY)
{
    return D3DXVECTOR2(0.5f + 0.5f*f2ProjSpaceXY.x, 0.5f - 0.5f*f2ProjSpaceXY.y);
}

// DirectX 11 render callback
//-----------------------------------------------------------------------------
void CLightScatteringSample::Render(double deltaSeconds)
{
    const float srgbClearColor[] = { 0.0993f, 0.0993f, 0.0993f, 1.0f }; //sRGB - red,green,blue,alpha pow(0.350, 2.2)
    const float  rgbClearColor[] = {  0.350f,  0.350f,  0.350f, 1.0f }; //RGB - red,green,blue,alpha

    // Clear back buffer
    const float clearColor[] = { 0.0993f, 0.0993f, 0.0993f, 1.0f };
    mpContext->ClearRenderTargetView( mpBackBufferRTV,  clearColor );
    mpContext->ClearDepthStencilView( mpDepthStencilView, D3D11_CLEAR_DEPTH | D3D11_CLEAR_STENCIL, 0.0f, 0);

    CPUTRenderParametersDX drawParams(mpContext);
    mpCamera = m_pViewCameras[m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL ? 0 : 1];

    D3DXMATRIX mProj = (D3DXMATRIX &)*mpCamera->GetProjectionMatrix();
    D3DXMATRIX mView = (D3DXMATRIX &)*mpCamera->GetViewMatrix();
    D3DXMATRIX mViewProj = mView * mProj;

    // Get the camera position
    D3DXMATRIX CameraWorld;
    D3DXMatrixInverse(&CameraWorld, NULL, &mView);
    D3DXVECTOR3 CameraPos = *(D3DXVECTOR3*)&CameraWorld._41;

    D3DXVECTOR3 v3LightPosition(0,2,0);//( (D3DXVECTOR3&)m_pSpotLightOrienationCamera->GetPosition() );
    D3DXVECTOR3 v3SpotLightAxis( (D3DXVECTOR3&)m_pSpotLightOrienationCamera->GetLook() );
    D3DXVECTOR3 v3LightDir, v3DirOnLight;
    if( m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL )
    {
        v3LightDir = -(D3DXVECTOR3&)m_pDirLightOrienationCamera->GetLook();
        v3DirOnLight = -v3LightDir;
    }
    else
    {
        v3LightDir = v3SpotLightAxis;
        v3DirOnLight = v3LightPosition - CameraPos;
        D3DXVec3Normalize(&v3DirOnLight, &v3DirOnLight);
    }

    struct SLightAttribsCBData
    {
        D3DXVECTOR4 LightPosAndCosAngle;
        D3DXVECTOR4 FogColor;
    }LightAttrbisCBData;
    LightAttrbisCBData.LightPosAndCosAngle = D3DXVECTOR4(v3LightPosition.x, v3LightPosition.y, v3LightPosition.z, cos(m_fSpotLightAngle));
    LightAttrbisCBData.FogColor = m_PPAttribs.m_f4RayleighBeta;
    LightAttrbisCBData.FogColor.w = 70;
    UpdateConstantBuffer(mpContext, m_pLightAttribsCB, &LightAttrbisCBData, sizeof(LightAttrbisCBData));


    if( (m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL && m_f3PrevDirOnLight != v3DirOnLight) ||
        ( (m_PPAttribs.m_uiLightType == LIGHT_TYPE_SPOT || m_PPAttribs.m_uiLightType == LIGHT_TYPE_POINT) && 
          (m_f3PrevLightPosition != v3LightPosition || m_f3PrevSpotLightAxis != v3SpotLightAxis || m_fSpotLightAngle != m_fPrevSpotLightAngle) ) )
	{
		RenderShadowMap(mpContext, v3LightDir, v3DirOnLight, v3LightPosition);
		m_f3PrevDirOnLight = v3DirOnLight;
        m_f3PrevLightPosition = v3LightPosition;
        m_f3PrevSpotLightAxis = v3SpotLightAxis;
        m_fPrevSpotLightAngle = m_fSpotLightAngle;
	}

    drawParams.mpCamera = mpCamera = 
        m_pViewCameras[m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL ? 0 : 1];
        
    if( m_bEnableLightScattering )
    {
        float pClearColor[4] = {0,0,0,0};
        m_pOffscreenRenderTarget->SetRenderTarget( drawParams, m_pOffscreenDepth, 0, pClearColor, true, 0.f );
    }
    else
    {
        mpContext->ClearRenderTargetView( mpBackBufferRTV, srgbClearColor );
        mpContext->ClearDepthStencilView(mpDepthStencilView, D3D11_CLEAR_DEPTH, 0.0f, 0);   
    }

    if( m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL )
        m_pCathedralAssetSet->RenderRecursive(drawParams);
    else
    {
        m_pCageAssetSet->RenderRecursive(drawParams);
        m_pSkyLightAssetSet->RenderRecursive(drawParams);

        CPUTRenderNode *pRootNode = m_pKleigAssetSet->GetRoot();
        pRootNode->SetParentMatrix( *m_pSpotLightCamera->GetWorldMatrix() );
        pRootNode->UpdateRecursive(0);
        pRootNode->Release();
        drawParams.mRenderOnlyVisibleModels = false;
        m_pKleigAssetSet->RenderRecursive(drawParams);
    }

    if( m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL && 
        m_PPAttribs.m_bStainedGlass )
    {
        m_pStainedGlassAssetSet->RenderRecursive(drawParams);
    }

    if( m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL )
        m_pTerrainAssetSet->RenderRecursive(drawParams);

    D3DXVECTOR4 f4LightColorAndIntensity, f4AmbientLight;
    if(m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL)
        m_pLightSctrPP->ComputeSunColor( v3DirOnLight, f4LightColorAndIntensity, f4AmbientLight );
    else
    {
        f4LightColorAndIntensity = m_f4LightColor;
        f4AmbientLight = D3DXVECTOR4(1,1,1,1);
    }
    mLightColor = (float3&)f4LightColorAndIntensity;

    if( m_bEnableLightScattering )
    {
        D3DXMATRIX mViewProjInverseMatr;
        D3DXMatrixInverse(&mViewProjInverseMatr, NULL, &mViewProj);

        D3DXVECTOR3 vSceneDiag = m_pvSceneBoundBoxCorners[7] - m_pvSceneBoundBoxCorners[0];
        float fSceneExtent = D3DXVec3Length(&vSceneDiag);

        SFrameAttribs FrameAttribs;

        FrameAttribs.pd3dDevice = mpD3dDevice;
        FrameAttribs.pd3dDeviceContext = mpContext;

        FrameAttribs.LightAttribs.f4DirOnLight = D3DXVECTOR4(v3DirOnLight.x, v3DirOnLight.y, v3DirOnLight.z, 0);
        (D3DXVECTOR3&)FrameAttribs.LightAttribs.f4SpotLightAxisAndCosAngle = v3SpotLightAxis;
        FrameAttribs.LightAttribs.f4SpotLightAxisAndCosAngle.w = cos(m_fSpotLightAngle);
        
        (D3DXVECTOR3&)FrameAttribs.LightAttribs.f4LightWorldPos = v3LightPosition;
        FrameAttribs.LightAttribs.f4LightWorldPos.w = 1;

        FrameAttribs.LightAttribs.f4LightColorAndIntensity = f4LightColorAndIntensity;
        FrameAttribs.LightAttribs.f4AmbientLight = f4AmbientLight;

        FrameAttribs.LightAttribs.f4LightColorAndIntensity.w = m_fLightIntensity * (m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL ? 1 : fSceneExtent*fSceneExtent*4);
        D3DXMatrixTranspose( &FrameAttribs.LightAttribs.mLightViewT, &m_WorldToLightSpaceMatr);
        D3DXMatrixTranspose( &FrameAttribs.LightAttribs.mLightProjT, &m_LightOrthoMatrix);
        D3DXMatrixTranspose( &FrameAttribs.LightAttribs.mWorldToLightProjSpaceT, &m_WorldToLightProjSpaceMatr);
        D3DXMATRIX mCameraProjToLightProjSpace = mViewProjInverseMatr * m_WorldToLightProjSpaceMatr;
        D3DXMatrixTranspose( &FrameAttribs.LightAttribs.mCameraProjToLightProjSpaceT, &mCameraProjToLightProjSpace);

        // Calculate location of the sun on the screen
        D3DXVECTOR4 &f4LightPosPS = FrameAttribs.LightAttribs.f4LightScreenPos;
        if( m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL )
            D3DXVec4Transform(&f4LightPosPS, &FrameAttribs.LightAttribs.f4DirOnLight, &mViewProj);
        else
            D3DXVec4Transform(&f4LightPosPS, &FrameAttribs.LightAttribs.f4LightWorldPos, &mViewProj);

        f4LightPosPS /= f4LightPosPS.w;
        float fDistToLightOnScreen = D3DXVec2Length( (D3DXVECTOR2*)&f4LightPosPS );
        float fMaxDist = 100;
        if( fDistToLightOnScreen > fMaxDist )
            (D3DXVECTOR2&)f4LightPosPS *= fMaxDist/fDistToLightOnScreen;

        FrameAttribs.LightAttribs.bIsLightOnScreen = abs(f4LightPosPS.x) <= 1 && abs(f4LightPosPS.y) <= 1;

        // Compute camera UV in shadow map
        D3DXVECTOR4 f4CameraPosInLightProjSpace;
        D3DXMATRIX mWorldToLightProjSpace;
        D3DXVECTOR4 f4CameraPos = D3DXVECTOR4(CameraPos.x, CameraPos.y, CameraPos.z, 1);
        D3DXVec4Transform(&f4CameraPosInLightProjSpace, &f4CameraPos, &m_WorldToLightProjSpaceMatr);
        (D3DXVECTOR3&)f4CameraPosInLightProjSpace /= f4CameraPosInLightProjSpace.w;
        (D3DXVECTOR2&)FrameAttribs.LightAttribs.f4CameraUVAndDepthInShadowMap = ProjToUV( (D3DXVECTOR2&)f4CameraPosInLightProjSpace );
        FrameAttribs.LightAttribs.f4CameraUVAndDepthInShadowMap.z = f4CameraPosInLightProjSpace.z;
        FrameAttribs.LightAttribs.f4CameraUVAndDepthInShadowMap.w = f4CameraPosInLightProjSpace.w;

        

        FrameAttribs.CameraAttribs.f4CameraPos = D3DXVECTOR4(CameraPos.x, CameraPos.y, CameraPos.z, 0);            ///< Camera world position
        D3DXMatrixTranspose( &FrameAttribs.CameraAttribs.mViewT, &mView);
        D3DXMatrixTranspose( &FrameAttribs.CameraAttribs.mProjT, &mProj);
        D3DXMatrixTranspose( &FrameAttribs.CameraAttribs.mViewProjInvT, &mViewProjInverseMatr);


        m_PPAttribs.m_fMaxTracingDistance = fSceneExtent * ( m_PPAttribs.m_uiLightType == LIGHT_TYPE_DIRECTIONAL  ? 1.5f : 10.f);
        m_PPAttribs.m_fDistanceScaler = 60000.f / m_PPAttribs.m_fMaxTracingDistance;

        m_PPAttribs.m_uiMaxShadowMapStep = m_uiShadowMapResolution / 32;

        m_PPAttribs.m_f2ShadowMapTexelSize = D3DXVECTOR2( 1.f / static_cast<float>(m_uiShadowMapResolution), 1.f / static_cast<float>(m_uiShadowMapResolution) );
        m_PPAttribs.m_uiShadowMapResolution = m_uiShadowMapResolution;
        m_PPAttribs.m_uiMinMaxShadowMapResolution = m_uiShadowMapResolution;

        FrameAttribs.ptex2DSrcColorBufferSRV = m_pOffscreenRenderTarget->GetColorResourceView();
        FrameAttribs.ptex2DDepthBufferSRV    = m_pOffscreenDepth->GetDepthResourceView();
        FrameAttribs.ptex2DShadowMapSRV      = m_pShadowMap->GetDepthResourceView();
        FrameAttribs.pDstRTV                 = mpBackBufferRTV;
        FrameAttribs.pDstDSV                 = mpDepthStencilView;
        FrameAttribs.ptex2DStainedGlassSRV   = m_pStainedGlassMap->GetColorResourceView();

        // Then perform the post processing, swapping the inverseworld view  projection matrix axes.
        m_pLightSctrPP->PerformPostProcessing(FrameAttribs, m_PPAttribs);

        m_pOffscreenRenderTarget->RestoreRenderTarget(drawParams);
    }

    // Draw GUI
    //
    if( m_iGUIMode )
        CPUTDrawGUI();
}

// Handle the shutdown event - clean up everything you created
//-----------------------------------------------------------------------------
void CLightScatteringSample::Shutdown()
{
    CPUT_DX11::Shutdown();
}


// Entrypoint for your sample
//-----------------------------------------------------------------------------
int WINAPI wWinMain( HINSTANCE hInstance, HINSTANCE hPrevInstance, LPWSTR lpCmdLine, int nCmdShow )
{
    UNREFERENCED_PARAMETER(hInstance);
    UNREFERENCED_PARAMETER(hPrevInstance);
    UNREFERENCED_PARAMETER(lpCmdLine);
    UNREFERENCED_PARAMETER(nCmdShow);

    // tell VS to report leaks at any exit of the program
    _CrtSetDbgFlag ( _CRTDBG_ALLOC_MEM_DF | _CRTDBG_LEAK_CHECK_DF );

    CPUTResult result=CPUT_SUCCESS;
    int returnCode=0;

    // create an instance of my sample
    CLightScatteringSample* sample = new CLightScatteringSample(); 


    // Initialize the system and give it the base CPUT resource directory (location of GUI images/etc)
    sample->CPUTInitialize(_L("CPUT//resources//"));

    // window parameters
    CPUTWindowCreationParams params;
    params.startFullscreen  = false;
    params.windowPositionX = 64;
    params.windowPositionY = 64;

    // device parameters
    params.deviceParams.refreshRate         = 60;
    params.deviceParams.swapChainBufferCount= 1;
    params.deviceParams.swapChainFormat     = DXGI_FORMAT_R8G8B8A8_UNORM_SRGB;
    params.deviceParams.swapChainUsage      = DXGI_USAGE_RENDER_TARGET_OUTPUT | DXGI_USAGE_SHADER_INPUT;

    // parse out the parameter settings
    cString AssetFilename_NotUsed;
    cString CommandLine(lpCmdLine);
    sample->CPUTParseCommandLine(CommandLine, &params, &AssetFilename_NotUsed);       

    // create the window and device context
    result = sample->CPUTCreateWindowAndContext(_L("Light Scattering Sample"), params);
    ASSERT( CPUTSUCCESS(result), _L("CPUT Error creating window and context.") );

    // start the main message loop
    returnCode = sample->CPUTMessageLoop();

	sample->DeviceShutdown();

    // cleanup resources
    delete sample; 

    // exit
    return returnCode;
}
