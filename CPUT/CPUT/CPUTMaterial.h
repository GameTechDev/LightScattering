/////////////////////////////////////////////////////////////////////////////////////////////
// Copyright 2017 Intel Corporation
//
// Licensed under the Apache License, Version 2.0 (the "License");// you may not use this file except in compliance with the License.// You may obtain a copy of the License at//// http://www.apache.org/licenses/LICENSE-2.0//// Unless required by applicable law or agreed to in writing, software// distributed under the License is distributed on an "AS IS" BASIS,// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.// See the License for the specific language governing permissions and// limitations under the License.
/////////////////////////////////////////////////////////////////////////////////////////////
#ifndef __CPUTMATERIAL_H__
#define __CPUTMATERIAL_H__

#include <stdio.h>
#include "CPUT.h"
#include "CPUTRefCount.h"
#include "CPUTConfigBlock.h"
#include "CPUTTexture.h"
#include "CPUTRenderStateBlock.h"

class CPUTShaderParameters;

// TODO: Where did this number come frome?  It should also be different for each API
#define CPUT_MATERIAL_MAX_TEXTURE_SLOTS         32
#define CPUT_MATERIAL_MAX_BUFFER_SLOTS          32
#define CPUT_MATERIAL_MAX_CONSTANT_BUFFER_SLOTS 32
#define CPUT_MATERIAL_MAX_SRV_SLOTS             32

#if 0 // Need to handle >=DX11 vs. < DX11, where max UAV slots == 1;
#   define CPUT_MATERIAL_MAX_UAV_SLOTS             7
#else
#   define CPUT_MATERIAL_MAX_UAV_SLOTS             1
#endif

class CPUTMaterial:public CPUTRefCount
{
protected:
    cString               mMaterialName;
    CPUTConfigBlock       mConfigBlock;
    CPUTRenderStateBlock *mpRenderStateBlock;
    UINT                  mBufferCount;
    CPUTTexture          *mpTexture[CPUT_MATERIAL_MAX_TEXTURE_SLOTS];

    // TODO: DX11 has buffers, UAVs, and constant buffers.  Do these belong there?
    CPUTBuffer           *mpBuffer[CPUT_MATERIAL_MAX_BUFFER_SLOTS];
    CPUTBuffer           *mpUAV[CPUT_MATERIAL_MAX_UAV_SLOTS];
    CPUTBuffer           *mpConstantBuffer[CPUT_MATERIAL_MAX_CONSTANT_BUFFER_SLOTS];

    // Destructor is not public.  Must release instead of delete.
    virtual ~CPUTMaterial(){
		// The following are allocated in the derived class.  So, release there too.
        // for( UINT ii=0; ii<CPUT_MATERIAL_MAX_TEXTURE_SLOTS; ii++ ) { SAFE_RELEASE( mpTexture[ii] ); }
        // for( UINT ii=0; ii<CPUT_MATERIAL_MAX_BUFFER_SLOTS; ii++ ) { SAFE_RELEASE( mpBuffer[ii] ); }
        // for( UINT ii=0; ii<CPUT_MATERIAL_MAX_CONSTANT_BUFFER_SLOTS; ii++ ) { SAFE_RELEASE( mpConstantBuffer[ii] ); }
        // SAFE_RELEASE(mpRenderStateBlock);
    }

public:
    static CPUTMaterial *CreateMaterial( const cString &absolutePathAndFilename, const cString &modelSuffix, const cString &meshSuffix );
    static CPUTConfigBlock mGlobalProperties;

    CPUTMaterial() :
		mpRenderStateBlock(NULL),
		mBufferCount(0)
	{
        for( UINT ii=0; ii<CPUT_MATERIAL_MAX_TEXTURE_SLOTS; ii++ )         { mpTexture[ii]       = NULL; }
        for( UINT ii=0; ii<CPUT_MATERIAL_MAX_BUFFER_SLOTS; ii++ )          { mpBuffer[ii]        = NULL; }
        for( UINT ii=0; ii<CPUT_MATERIAL_MAX_UAV_SLOTS; ii++ )             { mpUAV[ii]           = NULL; }
        for( UINT ii=0; ii<CPUT_MATERIAL_MAX_CONSTANT_BUFFER_SLOTS; ii++ ) { mpConstantBuffer[ii]= NULL; }
    };

    void                  SetMaterialName(const cString MaterialName) { mMaterialName = MaterialName; }
    void                  GetMaterialName(cString &MaterialName)      { MaterialName   = mMaterialName; }
    virtual CPUTResult    LoadMaterial(const cString &fileName, const cString &modelSuffix, const cString &meshSuffix) = 0;
    virtual void          ReleaseTexturesAndBuffers() = 0;
    virtual void          RebindTexturesAndBuffers() = 0;
    virtual void          SetRenderStates(CPUTRenderParameters &renderParams) { if( mpRenderStateBlock ) { mpRenderStateBlock->SetRenderStates(renderParams); } }
    virtual bool          MaterialRequiresPerModelPayload() = 0;
    virtual CPUTMaterial *CloneMaterial( const cString &absolutePathAndFilename, const cString &modelSuffix, const cString &meshSuffix ) = 0;
};

#endif //#ifndef __CPUTMATERIAL_H__
