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

struct VS_INPUT
{
    float3 Pos     : POSITION;
    float3 Norm    : NORMAL;
    float2 Uv      : TEXCOORD0;
};
struct PS_INPUT
{
    float4 Pos      : SV_POSITION;
    float3 Norm     : NORMAL;
    float2 Uv       : TEXCOORD0;
    float4 LightUv  : TEXCOORD1;
    float3 Position : TEXCOORD2; // Object space position 
};

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
cbuffer cbPerFrameValues
{
    row_major float4x4  View;
    row_major float4x4  Projection;
};

// ********************************************************************************************************
PS_INPUT VS( VS_INPUT input )
{
    PS_INPUT output = (PS_INPUT)0;

    output.Pos  = mul( float4( input.Pos, 1.0f), WorldViewProjection );
    output.Norm = mul( (float3x3)World, input.Norm );
    output.Uv   = input.Uv;   
	output.LightUv   = mul( float4( input.Pos, 1.0f), LightWorldViewProjection );

    return output;
}
