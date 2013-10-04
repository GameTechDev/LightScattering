//--------------------------------------------------------------------------------------
// Copyright 2011 Intel Corporation
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

// Converter TODO:
// normalize normals
// Orthonormalize orientation matrices?  Or, figure out how to get 3dsMax units to work correctly.


// ********************************************************************************************************
struct VS_INPUT
{
    float3 Pos      : POSITION; // Projected position
    float3 Norm     : NORMAL;
};
struct PS_INPUT
{
    float4 Pos      : SV_POSITION;
    float3 Norm     : NORMAL;
    float4 LightUv  : TEXCOORD0;
    float3 Position : TEXCOORD1; // Object space position 
};

// ********************************************************************************************************
#ifdef _CPUT
    Texture2D    TEXTURE0 : register( t0 );
    SamplerState SAMPLER0 : register( s0 );
    Texture2D    TEXTURE1 : register( t1 );
    SamplerComparisonState SAMPLER1 : register( s1 );
#endif

// ********************************************************************************************************
cbuffer cbPerModelValues
{
    row_major float4x4 World : WORLD;
    row_major float4x4 WorldViewProjection : WORLDVIEWPROJECTION;
    row_major float4x4 InverseWorld : INVERSEWORLD;
              float4   LightDirection;
              float4   EyePosition;
    row_major float4x4 LightWorldViewProjection;
};

// ********************************************************************************************************
// TODO: Note: nothing sets these values yet
cbuffer cbPerFrameValues
{
    row_major float4x4  View;
    row_major float4x4  Projection;
};

// ********************************************************************************************************
PS_INPUT VSMain( VS_INPUT input )
{
    PS_INPUT output = (PS_INPUT)0;

    output.Pos      = mul( float4( input.Pos, 1.0f), WorldViewProjection );
    output.Position = mul( float4( input.Pos, 1.0f), World ).xyz;

    // TODO: transform the light into object space instead of the normal into world space
    output.Norm = mul( input.Norm, (float3x3)World );

    output.LightUv   = mul( float4( input.Pos, 1.0f), LightWorldViewProjection );

    return output;
}

// ********************************************************************************************************
float4 PSMain( PS_INPUT input ) : SV_Target
{
    // float3 ambientOcclusion = TEXTURE1.Sample( SAMPLER0, input.Uv1 );

    float3 lightUv = input.LightUv.xyz / input.LightUv.w;
    float2 uv = lightUv.xy * 0.5f + 0.5f;
    float2 uvInvertY = float2(uv.x, 1.0f-uv.y);
    float shadowAmount = TEXTURE1.SampleCmp( SAMPLER1, uvInvertY, lightUv.z );

    float3 eyeDirection = normalize(input.Position - EyePosition.xyz);
    float3 normal       = normalize(input.Norm);

    float  nDotL = saturate( dot( normal, -normalize(LightDirection.xyz) ) );
    nDotL = shadowAmount * nDotL;

    float3 reflection   = reflect( eyeDirection, normal );
    float  rDotL        = saturate(dot( reflection, -LightDirection.xyz ));
    float  specular     = 0.2f * pow( rDotL, 4.0f );
    specular = min( shadowAmount, specular );

    return float4( (nDotL + specular).xxx, 1.0f);
}

// ********************************************************************************************************
technique testNotSkinned
{
    pass pass1
    {
        VertexShader = compile vs_3_0 VSMain();
        PixelShader  = compile ps_3_0 PSMain();
        // AlphaBlendEnable = true;
        AlphaTestEnable  = false;
        CullMode         = ccw;
        AlphaFunc        = GREATEREQUAL;
        AlphaRef         = 128;
        SrcBlend         = SRCALPHA;
        DestBlend        = INVSRCALPHA;
//      DestBlend        = SRCALPHA;
//      SrcBlend         = INVSRCALPHA;
        ZEnable          = true;
        ZWriteEnable     = true;
        ZFunc            = LESSEQUAL;
    }
}

