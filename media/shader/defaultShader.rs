[RasterizerStateDX11]
CullMode = D3D11_CULL_BACK

[SamplerDX11_1]
AddressU = D3D11_TEXTURE_ADDRESS_WRAP
AddressV = D3D11_TEXTURE_ADDRESS_WRAP

[Note: We use three textures, but only two samplers.]
[SamplerDX11_2]
ComparisonFunc = D3D11_COMPARISON_GREATER
Filter = D3D11_FILTER_COMPARISON_MIN_MAG_LINEAR_MIP_POINT
AddressU = D3D11_TEXTURE_ADDRESS_BORDER
AddressV = D3D11_TEXTURE_ADDRESS_BORDER
BorderColor0 = 0
BorderColor1 = 0
BorderColor2 = 0
BorderColor3 = 0
