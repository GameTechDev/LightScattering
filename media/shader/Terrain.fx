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
    float2 Uv0      : TEXCOORD0;
};
struct PS_INPUT
{
    float4 Pos      : SV_POSITION;
    float3 Norm     : NORMAL;
    float2 Uv0      : TEXCOORD0;
    float4 LightUv  : TEXCOORD2;
    float3 Position : TEXCOORD3; // Object space position 
};

// ********************************************************************************************************
#ifdef _CPUT
    Texture2D    g_tex2DMask                : register( t0 );
    Texture2D    g_tex2DGrass               : register( t1 );
    Texture2D    g_tex2DDirt                : register( t2 );
    Texture2D    g_tex2DStone               : register( t3 );
    Texture2D    g_tex2DShadowMap           : register( t4 );
    Texture2D    g_tex2DStainedGlassColor   : register( t5 );
    Texture2D    g_tex2DStainedGlassDepth   : register( t6 );

    SamplerState SAMPLER0 : register( s0 );
    SamplerComparisonState SAMPLER1 : register( s1 );
#else
    texture2D g_tex2DMask < string Name = "color1"; string UIName = "color1"; string ResourceType = "2D";>;
    sampler2D SAMPLER0 = sampler_state { texture = (g_tex2DMask);};
    texture2D g_tex2DShadowMap < string Name = "shadow"; string UIName = "shadow"; string ResourceType = "2D";>;
    sampler2D SAMPLER1 = sampler_state { texture = (g_tex2DShadowMap);};
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
    output.Norm    = mul( input.Norm, (float3x3)World );
    output.Uv0     = input.Uv0;
    output.LightUv = mul( float4( input.Pos, 1.0f), LightWorldViewProjection );

    return output;
}

// ********************************************************************************************************
float4 PSMain( PS_INPUT input ) : SV_Target
{
    // Compute shadow amount (the light's visibility function)
    float shadowAmount = 1;
    float3 f3StainedGlassColor = 1;
    if( input.LightUv.w > 0 )
    {
        float3  lightUv = input.LightUv.xyz / input.LightUv.w;
        lightUv.xy = lightUv.xy * 0.5f + 0.5f; // TODO: Move to matrix?
        lightUv.y  = 1.0f - lightUv.y;
        lightUv.z = max(lightUv.z - 1e-4, 1e-7);
        shadowAmount     = g_tex2DShadowMap.SampleCmp( SAMPLER1, lightUv, lightUv.z ).x;
        f3StainedGlassColor = g_tex2DStainedGlassColor.Sample( SAMPLER0, lightUv )*1.5;
        float fPureLightAmount = g_tex2DStainedGlassDepth.SampleCmp( SAMPLER1, lightUv, lightUv.z ).x;
        f3StainedGlassColor.rgb = lerp( f3StainedGlassColor.rgb, float3(1,1,1), fPureLightAmount );
    }
    
    // Get material mask
    float3 mask = float3(0, g_tex2DMask.Sample( SAMPLER0, input.Uv0 ).rg);
    mask.r = max(1 - dot(mask.gb, 1), 0);
    mask /= dot(mask, 1);
    
    float fTilingScale = 30;
    float3 f3GrassAlbedo = g_tex2DGrass.Sample( SAMPLER0, input.Uv0 * fTilingScale ).rgb;
    float3 f3DirtAlbedo  = g_tex2DDirt.Sample(  SAMPLER0, input.Uv0 * fTilingScale ).rgb;
    float3 f3StoneAlbedo = g_tex2DStone.Sample( SAMPLER0, input.Uv0 * fTilingScale ).rgb;
    float3 albedo = f3GrassAlbedo * mask.r + f3DirtAlbedo * mask.g + f3StoneAlbedo * mask.b;
   
    // Compute diffuse contribution
    float3 normal           = normalize(input.Norm);
    float  nDotL            = saturate( dot( normal, -LightDirection.xyz ) );
    float3 diffuse          = nDotL * shadowAmount*f3StainedGlassColor.rgb * albedo;

    // Compute specular contribution
    float3 eyeDirection     = normalize(EyePosition.xyz - input.Position);
    float3 HalfVector = normalize( eyeDirection + (-LightDirection.xyz) );
    float  nDotH            = saturate( dot(normal, HalfVector) );
    float3 specular         = pow(nDotH, 50.0f );
    specular               *= 0.1 * shadowAmount*f3StainedGlassColor.rgb;

    float3 ambient = float3(0.2,0.2,0.2) * albedo;

    return float4( ambient + diffuse + specular, 1.0f );
}
