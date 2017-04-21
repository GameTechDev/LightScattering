/////////////////////////////////////////////////////////////////////////////////////////////
// Copyright 2017 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");// you may not use this file except in compliance with the License.// You may obtain a copy of the License at//// http://www.apache.org/licenses/LICENSE-2.0//// Unless required by applicable law or agreed to in writing, software// distributed under the License is distributed on an "AS IS" BASIS,// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.// See the License for the specific language governing permissions and// limitations under the License.
/////////////////////////////////////////////////////////////////////////////////////////////

#include "RenderTechnique.h"
#include <D3DX11.h>
#include <D3Dcompiler.h>
#include <fstream>

CRenderTechnique::CRenderTechnique(void)
{
}


CRenderTechnique::~CRenderTechnique(void)
{
}

void CRenderTechnique::Release()
{
    m_pVS.Release();
    m_pGS.Release();
    m_pPS.Release();
    m_pCS.Release();
    m_pRS.Release();
    m_pDS.Release();
    m_pBS.Release();
    m_pContext.Release();
    m_pDevice.Release();
}

static
HRESULT CompileShaderFromFile(LPCTSTR strFilePath, 
                              LPCSTR strFunctionName,
                              const D3D_SHADER_MACRO* pDefines, 
                              LPCSTR profile, 
                              ID3DBlob **ppBlobOut)
{
    DWORD dwShaderFlags = D3D10_SHADER_ENABLE_STRICTNESS;
#if defined( DEBUG ) || defined( _DEBUG )
    // Set the D3D10_SHADER_DEBUG flag to embed debug information in the shaders.
    // Setting this flag improves the shader debugging experience, but still allows 
    // the shaders to be optimized and to run exactly the way they will run in 
    // the release configuration of this program.
    dwShaderFlags |= D3D10_SHADER_DEBUG;
#else
    // Warning: do not use this flag as it causes shader compiler to fail the compilation and 
    // report strange errors:
    // dwShaderFlags |= D3D10_SHADER_OPTIMIZATION_LEVEL3;
#endif
	HRESULT hr;
	do
	{
		CComPtr<ID3DBlob> errors;
        hr = D3DX11CompileFromFile(strFilePath, pDefines, NULL, strFunctionName, profile, dwShaderFlags, 0, NULL, ppBlobOut, &errors, NULL);
		if( errors )
		{
			OutputDebugStringA((char*) errors->GetBufferPointer());
			if( FAILED(hr) && 
				IDRETRY != MessageBoxA(NULL, (char*) errors->GetBufferPointer(), "FX Error", MB_ICONERROR|MB_ABORTRETRYIGNORE) )
			{
				break;
			}
		}
	} while( FAILED(hr) );
	return hr;
}

HRESULT CRenderTechnique::CreateVertexShaderFromFile(LPCTSTR strFilePath, 
                                                      LPSTR strFunctionName,
                                                      const D3D_SHADER_MACRO* pDefines)
{
    CComPtr<ID3DBlob> pShaderByteCode;

    HRESULT hr;
    hr = CompileShaderFromFile( strFilePath, strFunctionName, pDefines, "vs_5_0", &pShaderByteCode );
    if( !pShaderByteCode )hr = E_FAIL;
    if(FAILED(hr))return hr;

    m_pVS.Release();
    hr = m_pDevice->CreateVertexShader( pShaderByteCode->GetBufferPointer(), pShaderByteCode->GetBufferSize(), NULL, &m_pVS );

    return hr;
}

HRESULT CRenderTechnique::CreateGeometryShaderFromFile(LPCTSTR strFilePath, 
                                                        LPSTR strFunctionName,
                                                        const D3D_SHADER_MACRO* pDefines)
{
    CComPtr<ID3DBlob> pShaderByteCode;

    HRESULT hr;
    hr = CompileShaderFromFile( strFilePath, strFunctionName, pDefines, "gs_5_0", &pShaderByteCode );
    if( !pShaderByteCode )hr = E_FAIL;
    if(FAILED(hr))return hr;

    m_pGS.Release();
    hr = m_pDevice->CreateGeometryShader( pShaderByteCode->GetBufferPointer(), pShaderByteCode->GetBufferSize(), NULL, &m_pGS );

    return hr;
}

HRESULT CRenderTechnique::CreatePixelShaderFromFile(LPCTSTR strFilePath, 
                                                     LPSTR strFunctionName,
                                                     const D3D_SHADER_MACRO* pDefines)
{
    CComPtr<ID3DBlob> pShaderByteCode;

    HRESULT hr;
    hr = CompileShaderFromFile( strFilePath, strFunctionName, pDefines, "ps_5_0", &pShaderByteCode );
    if( !pShaderByteCode )hr = E_FAIL;
    if(FAILED(hr))return hr;

    m_pPS.Release();
    hr = m_pDevice->CreatePixelShader( pShaderByteCode->GetBufferPointer(), pShaderByteCode->GetBufferSize(), NULL, &m_pPS );

    return hr;
}

HRESULT CRenderTechnique::CreateComputeShaderFromFile(LPCTSTR strFilePath, 
                                                       LPSTR strFunctionName,
                                                       const D3D_SHADER_MACRO* pDefines)
{
    CComPtr<ID3DBlob> pShaderByteCode;

    HRESULT hr;
    hr = CompileShaderFromFile( strFilePath, strFunctionName, pDefines, "cs_5_0", &pShaderByteCode );
    if( !pShaderByteCode )hr = E_FAIL;
    if(FAILED(hr))return hr;

    m_pCS.Release();
    hr = m_pDevice->CreateComputeShader( pShaderByteCode->GetBufferPointer(), pShaderByteCode->GetBufferSize(), NULL, &m_pCS );

    return hr;
}

HRESULT CRenderTechnique::CreateVGPShadersFromFile(LPCTSTR strFilePath, 
                                                    LPSTR strVSFunctionName, 
                                                    LPSTR strGSFunctionName, 
                                                    LPSTR strPSFunctionName, 
                                                    const D3D_SHADER_MACRO* pDefines)
{
    HRESULT hr = S_OK;
    if( strVSFunctionName )
    {
        hr = CreateVertexShaderFromFile(strFilePath, strVSFunctionName, pDefines);
        if( FAILED(hr) )return hr;
    }

    if( strPSFunctionName )
    {
        hr = CreatePixelShaderFromFile(strFilePath, strPSFunctionName, pDefines);
        if( FAILED(hr) )return hr;
    }

    if( strGSFunctionName )
    {
        hr = CreateGeometryShaderFromFile(strFilePath, strGSFunctionName, pDefines);
        if( FAILED(hr) )return hr;
    }

    return hr;
}

void CRenderTechnique::Apply()
{
    m_pContext->HSSetShader(NULL, NULL, 0);
    m_pContext->DSSetShader(NULL, NULL, 0);
    m_pContext->VSSetShader(m_pVS, NULL, 0);
    m_pContext->GSSetShader(m_pGS, NULL, 0);
    m_pContext->PSSetShader(m_pPS, NULL, 0);
    m_pContext->CSSetShader(m_pCS, NULL, 0);
    m_pContext->RSSetState(m_pRS);
    m_pContext->OMSetDepthStencilState(m_pDS, m_uiSampleRef);  
    float fBlendFactor[] = {0, 0, 0, 0};
    m_pContext->OMSetBlendState(m_pBS, fBlendFactor, 0xFFFFFFFF);
}
