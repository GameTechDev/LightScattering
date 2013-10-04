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

#ifndef NORMAL_MAPPING
#   define NORMAL_MAPPING 0
#endif

// ********************************************************************************************************
struct VS_INPUT
{
    float3 Pos      : POSITION; // Projected position
    float3 Norm     : NORMAL;
    float2 Uv0      : TEXCOORD0;
    float2 Uv1      : TEXCOORD1;
#if NORMAL_MAPPING
    float3 Tangent  : TANGENT;
    float3 Binormal : BINORMAL;
#endif
};
struct PS_INPUT
{
    float4 Pos      : SV_POSITION;
    float3 Norm     : NORMAL;
    float2 Uv0      : TEXCOORD0;
    float2 Uv1      : TEXCOORD1;
    float4 LightUv  : TEXCOORD2;
    float3 Position : TEXCOORD3; // Object space position 
#if NORMAL_MAPPING
    float3 Tangent  : TANGENT;
    float3 Binormal : BINORMAL;
#endif
};

// ********************************************************************************************************
#ifdef _CPUT
    Texture2D g_tex2DDiffuse             : register( t0 );
    Texture2D g_tex2DNormalMap           : register( t1 );
    Texture2D g_tex2DAO                  : register( t2 );
    Texture2D g_tex2DShadowMap           : register( t3 );
    Texture2D g_tex2DStainedGlassColor   : register( t4 );
    Texture2D g_tex2DStainedGlassDepth   : register( t5 );
    
    SamplerState SAMPLER0 : register( s0 );
    SamplerComparisonState SAMPLER1 : register( s1 );
#else
    Texture2D g_tex2DDiffuse < string Name = "color1"; string UIName = "color1"; string ResourceType = "2D";>;
    sampler2D SAMPLER0 = sampler_state { texture = (g_tex2DDiffuse);};
    Texture2D g_tex2DAO < string Name = "shadow"; string UIName = "shadow"; string ResourceType = "2D";>;
    sampler2D SAMPLER1 = sampler_state { texture = (g_tex2DAO);};
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
    PS_INPUT output;

    output.Pos      = mul( float4( input.Pos, 1.0f), WorldViewProjection );
    output.Position = mul( float4( input.Pos, 1.0f), World ).xyz;

    // TODO: transform the light into object space instead of the normal into world space
    output.Norm    = mul( input.Norm, (float3x3)World );
    output.Uv0     = input.Uv0;
    output.Uv1     = input.Uv1;
    output.LightUv = mul( float4( input.Pos, 1.0f), LightWorldViewProjection );
#if NORMAL_MAPPING
    output.Tangent = input.Tangent;
    output.Binormal = input.Binormal;
#endif
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

    // Compute ambient contribution
    float3 albedo           = g_tex2DDiffuse.Sample( SAMPLER0, input.Uv0 ).rgb;
    float3 ambientOcclusion = g_tex2DAO.Sample( SAMPLER0, input.Uv1 ).rgb;
    float3  ambient          = 0.6*ambientOcclusion * albedo;
    
    // Compute diffuse contribution
    float3 normal;
#if NORMAL_MAPPING
        float3 f3TangentSpaceNormal = g_tex2DNormalMap.Sample( SAMPLER0, input.Uv0 ).rgb * 2 - 1;
        //normal = normalize( input.Tangent * f3TangentSpaceNormal.x + input.Binormal * f3TangentSpaceNormal.y + input.Norm * f3TangentSpaceNormal.z);
        float3 f3Normal = cross(input.Binormal, input.Tangent);
        normal = normalize( mul( f3TangentSpaceNormal, float3x3(input.Tangent, input.Binormal, f3Normal)) );
#else
        normal = normalize(input.Norm);
#endif
    float  nDotL            = saturate( dot( normal, -LightDirection.xyz ) );
    float3 diffuse          = nDotL * shadowAmount * albedo * f3StainedGlassColor.rgb;

    // Compute specular contribution
    float3 eyeDirection     = normalize(EyePosition.xyz - input.Position);
    float3 HalfVector = normalize( eyeDirection + (-LightDirection.xyz) );
    float  nDotH            = saturate( dot(normal, HalfVector) );
    float3 specular         = pow(nDotH, 50.0f );
    specular               *= 0.3 * shadowAmount * f3StainedGlassColor.rgb;

    return float4(ambient + diffuse + specular, 1);
}

