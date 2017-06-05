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
#include "CPUTFontDX11.h"
#include "CPUTTextureDX11.h"

int gFontStartLocations_active[] =
{
    // auto-generated by off-line tool
    0,7,15,22,30,37,42,50,58,61,66,73,77,                   //a-m
    88,96,104,111,119,124,132,137,144,152,162,170,178,      //n-z
    185,195,204,213,223,231,239,249,258,262,270,279,287,    //A-M
    297,306,317,325,335,344,352,360,369,379,392,401,410,    //N-Z
    419,425,432,440,448,456,463,470,478,485,                //1-0
    493,497,500,506,510,515,520,525,530,535,543,547,561,    //symbols ,-#
    569,577,589,596,606,612,616,621,629,637,642,648,653,    //symbols $-:
    657,664,672,680,688,694,701                             //symbols "-=
    ,705,755,                                               //dead spot used for the space char and tab
    -1,                                                     //end marker
};

// height of the font
const int gFontHeight = 12;

// y offset to get to the next font down (the disabled font)
const int gYOffset = 12;
    
//-----------------------------------------------------------------------------
CPUTFont *CPUTFontDX11::CreateFont( cString FontName, cString AbsolutePathAndFilename )
{
    CPUTFontDX11 *pNewFont = new CPUTFontDX11();

    // load the actual font image
    CPUTAssetLibraryDX11 *pAssetLibrary = (CPUTAssetLibraryDX11*)CPUTAssetLibraryDX11::GetAssetLibrary();
    pNewFont->mpTextAtlas= (CPUTTextureDX11*) pAssetLibrary->GetTexture(AbsolutePathAndFilename, true);
    ASSERT(pNewFont->mpTextAtlas, _L("CPUTFontDX11::CreateFont() - Error loading specified font texture"));
    // get the TextureResourceView
    pNewFont->mpTextAtlasView = pNewFont->mpTextAtlas->GetShaderResourceView();
    pNewFont->mpTextAtlasView->AddRef();
    // CPUTSetDebugName( pNewFont->mpTextAtlasView, _L("GUI TextAtlasView"));
    
    // Get and store the atlas size
    D3D11_TEXTURE2D_DESC TextureDesc;
    ID3D11Texture2D *p2DTexture = NULL;

    // get the ID3D11Resource from the ID3D11ShaderResourceView
    ID3D11Resource *pResource = NULL;
    pNewFont->mpTextAtlasView->GetResource(&pResource);

    // get the ID3D11Texture2D from the ID3D11Resource
    HRESULT hr = pResource->QueryInterface(__uuidof(ID3D11Texture2D) ,(void**)&p2DTexture);
    ASSERT( SUCCEEDED(hr), _L("CPUTFontDX11::CreateFont() - Error loading specified font texture"));
    p2DTexture->GetDesc(&TextureDesc);
        
    // store the image dimensions/size
    pNewFont->mAtlasWidth = (float)TextureDesc.Width;
    pNewFont->mAtlasHeight = (float)TextureDesc.Height;
    
    // release the pointers
    SAFE_RELEASE(pResource);
    SAFE_RELEASE(p2DTexture);

    // todo: can use the tick marks above each glyph to determine start/stop
    // But this requires me to be able to map the texture so I can walk it and find the glyph start/stop
    // points.  Currently we register all textures as immutable, so we can't map the texture. 
    // For now, I have an offline tool generate the mappings found in gFontStartLocations_active[]
        
    int index=0;
    while(-1 != gFontStartLocations_active[index])
    {
        // record the start location
        pNewFont->mpGlyphStarts[index] = gFontStartLocations_active[index];

        // calculate the size of each glyph in pixels
        pNewFont->mpGlyphSizes[index].width = gFontStartLocations_active[index+1] - gFontStartLocations_active[index];
        pNewFont->mpGlyphSizes[index].height = gFontHeight-1; // -1 for top line of glyph start marker dots

        // calculate the UV coordinates for the 'enabled' version of this glyph
        pNewFont->mpGlyphUVCoords[4*index+0] = gFontStartLocations_active[index]/pNewFont->mAtlasWidth;       // u1 - upper left x
        pNewFont->mpGlyphUVCoords[4*index+1] = 1.0f/pNewFont->mAtlasHeight;                                   // v1 - upper left y
        pNewFont->mpGlyphUVCoords[4*index+2] = gFontStartLocations_active[index+1]/pNewFont->mAtlasWidth;     // u2 - lower right x
        pNewFont->mpGlyphUVCoords[4*index+3] = gFontHeight/pNewFont->mAtlasHeight;                            // v2 - lower right y

        // calculate the UV coordinates of the 'disabled'/greyed version of this glyph
        pNewFont->mpGlyphUVCoordsDisabled[4*index+0] = gFontStartLocations_active[index]/pNewFont->mAtlasWidth;       // u1 - upper left x
        pNewFont->mpGlyphUVCoordsDisabled[4*index+1] = (gYOffset+1)/pNewFont->mAtlasHeight;                           // v1 - upper left y
        pNewFont->mpGlyphUVCoordsDisabled[4*index+2] = gFontStartLocations_active[index+1]/pNewFont->mAtlasWidth;     // u2 - lower right x
        pNewFont->mpGlyphUVCoordsDisabled[4*index+3] = (gFontHeight+gYOffset)/pNewFont->mAtlasHeight;                 // v2 - lower right y


        index++;
    }
    pNewFont->mNumberOfGlyphsInAtlas = index;

    // add font to the asset library
    CPUTAssetLibrary::GetAssetLibrary()->AddFont( FontName, pNewFont);

    return pNewFont; 
}



// Constructor
//-----------------------------------------------------------------------------
CPUTFontDX11::CPUTFontDX11():mpTextAtlas(NULL),
    mpTextAtlasView(NULL)
{
    mDisabledYOffset = 0;
}

// Destructor
//-----------------------------------------------------------------------------
CPUTFontDX11::~CPUTFontDX11()
{
    // release the texture atlas
    SAFE_RELEASE(mpTextAtlasView);
    SAFE_RELEASE(mpTextAtlas);    
}

// Return the texture atlas texture
//-----------------------------------------------------------------------------
CPUTTextureDX11* CPUTFontDX11::GetAtlasTexture()
{
    return mpTextAtlas;
}

// Return the texture atlas texture resource view
//-----------------------------------------------------------------------------
ID3D11ShaderResourceView* CPUTFontDX11::GetAtlasTextureResourceView()
{
    return mpTextAtlasView;
}



// Load glyph mapping file
// The map file in an ordered list that tells you which glyph in the texture
// corresponds to the ASCII character value in this file (char->image lookup)
//--------------------------------------------------------------------------------
CPUTResult CPUTFontDX11::LoadGlyphMappingFile(const cString fileName)
{
    return CPUT_SUCCESS;
}

