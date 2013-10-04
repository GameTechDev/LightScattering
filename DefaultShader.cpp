
const char *gpDefaultShaderSource =  "\n\
// ********************************************************************************************************\n\
struct VS_INPUT\n\
{\n\
    float3 Pos      : POSITION; // Projected position\n\
    float3 Norm     : NORMAL;\n\
    float2 Uv       : TEXCOORD0;\n\
};\n\
struct PS_INPUT\n\
{\n\
    float4 Pos      : SV_POSITION;\n\
    float3 Norm     : NORMAL;\n\
    float2 Uv       : TEXCOORD0;\n\
    float3 Position : TEXCOORD1; // Object space position \n\
};\n\
// ********************************************************************************************************\n\
    Texture2D    TEXTURE0 : register( t0 );\n\
    SamplerState SAMPLER0 : register( s0 );\n\
// ********************************************************************************************************\n\
cbuffer cbPerModelValues\n\
{\n\
    row_major float4x4 World : WORLD;\n\
    row_major float4x4 WorldViewProjection : WORLDVIEWPROJECTION;\n\
    row_major float4x4 InverseWorld : INVERSEWORLD;\n\
              float4   LightDirection;\n\
              float4   EyePosition;\n\
    row_major float4x4 LightWorldViewProjection;\n\
};\n\
// ********************************************************************************************************\n\
// TODO: Note: nothing sets these values yet\n\
cbuffer cbPerFrameValues\n\
{\n\
    row_major float4x4  View;\n\
    row_major float4x4  Projection;\n\
};\n\
// ********************************************************************************************************\n\
PS_INPUT VSMain( VS_INPUT input )\n\
{\n\
    PS_INPUT output = (PS_INPUT)0;\n\
    output.Pos      = mul( float4( input.Pos, 1.0f), WorldViewProjection );\n\
    output.Position = mul( float4( input.Pos, 1.0f), World ).xyz;\n\
    // TODO: transform the light into object space instead of the normal into world space\n\
    output.Norm = mul( input.Norm, (float3x3)World );\n\
    output.Uv   = float2(input.Uv.x, input.Uv.y);\n\
    return output;\n\
}\n\
// ********************************************************************************************************\n\
float4 PSMain( PS_INPUT input ) : SV_Target\n\
{\n\
    float3 normal         = normalize(input.Norm);\n\
    float  nDotL          = saturate( dot( normal, -LightDirection ) );\n\
    float3 eyeDirection     = normalize(EyePosition.xyz - input.Position);\n\
    float3 HalfVector       = normalize( eyeDirection + (-LightDirection.xyz) );\n\
    float  nDotH            = saturate( dot(normal, HalfVector) );\n\
    float3 specular         = 0.3f * pow(nDotH, 50.0f );\n\
    float4 diffuseTexture = TEXTURE0.Sample( SAMPLER0, input.Uv );\n\
    float ambient = 0.05;\n\
    float3 result = (nDotL+ambient) * diffuseTexture + specular;\n\
    return float4( result, 1.0f );\n\
}\n\
\n\
// ********************************************************************************************************\n\
struct VS_INPUT_NO_TEX\n\
{\n\
    float3 Pos      : POSITION; // Projected position\n\
    float3 Norm     : NORMAL;\n\
};\n\
struct PS_INPUT_NO_TEX\n\
{\n\
    float4 Pos      : SV_POSITION;\n\
    float3 Norm     : NORMAL;\n\
    float3 Position : TEXCOORD0; // Object space position \n\
};\n\
// ********************************************************************************************************\n\
PS_INPUT_NO_TEX VSMainNoTexture( VS_INPUT_NO_TEX input )\n\
{\n\
    PS_INPUT_NO_TEX output = (PS_INPUT_NO_TEX)0;\n\
    output.Pos      = mul( float4( input.Pos, 1.0f), WorldViewProjection );\n\
    output.Position = mul( float4( input.Pos, 1.0f), World ).xyz;\n\
    // TODO: transform the light into object space instead of the normal into world space\n\
    output.Norm = mul( input.Norm, (float3x3)World );\n\
    return output;\n\
}\n\
// ********************************************************************************************************\n\
float4 PSMainNoTexture( PS_INPUT_NO_TEX input ) : SV_Target\n\
{\n\
    float3 normal       = normalize(input.Norm);\n\
    float  nDotL = saturate( dot( normal, -normalize(LightDirection.xyz) ) );\n\
    float3 eyeDirection     = normalize(EyePosition.xyz - input.Position);\n\
    float3 HalfVector       = normalize( eyeDirection + (-LightDirection.xyz) );\n\
    float  nDotH            = saturate( dot(normal, HalfVector) );\n\
    float3 specular         = 0.3f * pow(nDotH, 50.0f );\n\
    return float4( (nDotL + specular).xxx, 1.0f);\n\
}\n\
";

