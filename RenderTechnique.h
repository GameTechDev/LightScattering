////////////////////////////////////////////////////////////////////////////////
// Copyright 2017 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not
// use this file except in compliance with the License.  You may obtain a copy
// of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
// License for the specific language governing permissions and limitations
// under the License.
////////////////////////////////////////////////////////////////////////////////

#pragma once

#include <D3D11.h>
#include <atlcomcli.h>

class CRenderTechnique
{
public:
    CRenderTechnique(void);
    ~CRenderTechnique(void);

    void Release();
    void SetDeviceAndContext(ID3D11Device *pDevice, ID3D11DeviceContext *pCtx){m_pDevice = pDevice; m_pContext = pCtx;}
    void Apply();

    ID3D11VertexShader      * GetVS(){return m_pVS;}
    ID3D11GeometryShader    * GetGS(){return m_pGS;}
    ID3D11PixelShader       * GetPS(){return m_pPS;}
    ID3D11ComputeShader     * GetCS(){return m_pCS;}
    ID3D11RasterizerState   * GetRS(){return m_pRS;}
    ID3D11DepthStencilState * GetDS(){return m_pDS;}
    ID3D11BlendState        * GetBS(){return m_pBS;}

    void SetVS(ID3D11VertexShader      *pVS ){m_pVS = pVS;}
    void SetGS(ID3D11GeometryShader    *pGS ){m_pGS = pGS;}
    void SetPS(ID3D11PixelShader       *pPS ){m_pPS = pPS;}
    void SetCS(ID3D11ComputeShader     *pCS ){m_pCS = pCS;}
    void SetRS(ID3D11RasterizerState   *pRS ){m_pRS = pRS;}
    void SetDS(ID3D11DepthStencilState *pDS, UINT uiSampleRef = 0 ){m_pDS = pDS; m_uiSampleRef = uiSampleRef;}
    void SetBS(ID3D11BlendState        *pBS ){m_pBS = pBS;}

    HRESULT CreateVertexShaderFromFile   (LPCTSTR strFilePath, LPSTR strFunctionName, const D3D_SHADER_MACRO* pDefines);
    HRESULT CreateGeometryShaderFromFile (LPCTSTR strFilePath, LPSTR strFunctionName, const D3D_SHADER_MACRO* pDefines);
    HRESULT CreatePixelShaderFromFile    (LPCTSTR strFilePath, LPSTR strFunctionName, const D3D_SHADER_MACRO* pDefines);
    HRESULT CreateComputeShaderFromFile  (LPCTSTR strFilePath, LPSTR strFunctionName, const D3D_SHADER_MACRO* pDefines);
    
    HRESULT CreateVGPShadersFromFile     (LPCTSTR strFilePath, LPSTR strVSFunctionName, LPSTR strGSFunctionName, LPSTR strPSFunctionName, const D3D_SHADER_MACRO* pDefines);

    bool IsValid(){ return m_pDevice && m_pContext && (m_pPS || m_pCS);}

private:
    CComPtr<ID3D11Device> m_pDevice;
    CComPtr<ID3D11DeviceContext> m_pContext;
    CComPtr<ID3D11VertexShader> m_pVS;
    CComPtr<ID3D11GeometryShader> m_pGS;
    CComPtr<ID3D11PixelShader> m_pPS;
    CComPtr<ID3D11ComputeShader> m_pCS;
    CComPtr<ID3D11RasterizerState> m_pRS;
    CComPtr<ID3D11DepthStencilState> m_pDS;
    CComPtr<ID3D11BlendState> m_pBS;
    UINT m_uiSampleRef;
};
