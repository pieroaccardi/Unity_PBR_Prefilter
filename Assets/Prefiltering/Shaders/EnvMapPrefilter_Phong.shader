Shader "PBR/EnvMapPrefilter_Phong"
{
	SubShader
	{
		Tags{ "RenderType" = "Opaque" }
		LOD 100

		Pass
		{
			CGPROGRAM

			#pragma vertex vert
			#pragma fragment frag

			#pragma enable_d3d11_debug_symbols

			#include "UnityCG.cginc"

			struct PS_INPUT
			{
				float4 Position : SV_POSITION;
				float2 UV : TEXCOORD0;
				float3 R : TEXCOORD1;
			};

			samplerCUBE input_envmap;
			
			uint face;
			float _CubeSize;
			float _Lod;
			float numLod;
			float alpha; 

			PS_INPUT vert(uint index : SV_VERTEXID)
			{
				PS_INPUT output;
				output.UV = float2((index << 1) & 2, index & 2);
				output.Position = float4(output.UV * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);

				//reflection vector
				uint n = (uint)(face/ 2);
				uint s = face % 2;
				float sign = (s == 0) ? 1 : -1;
				switch (n)
				{
				case 0:
					output.R.x = sign;
					output.R.zy = output.UV * float2(-2 * sign, -2) - float2(-1 * sign, -1);
					break;

				case 1:
					output.R.y = sign;
					output.R.xz = output.UV * float2(2, 2 * sign) - float2(1, 1 * sign);
					break;

				case 2:
					output.R.z = sign;
					output.R.xy = output.UV * float2(2 * sign, -2) - float2(1 * sign, -1);
					break;
				}

				return output;
			}

			static const float PI = 3.1415926535897932384626433832795;

			float radicalInverse_VdC(uint bits)
			{
				bits = (bits << 16u) | (bits >> 16u);
				bits = ((bits & 0x55555555u) << 1u) | ((bits & 0xAAAAAAAAu) >> 1u);
				bits = ((bits & 0x33333333u) << 2u) | ((bits & 0xCCCCCCCCu) >> 2u);
				bits = ((bits & 0x0F0F0F0Fu) << 4u) | ((bits & 0xF0F0F0F0u) >> 4u);
				bits = ((bits & 0x00FF00FFu) << 8u) | ((bits & 0xFF00FF00u) >> 8u);

				return float(bits) * 2.3283064365386963e-10; // / 0x100000000
			}

			float2 Hammersley(uint i, uint n)
			{
				return float2((float)i / (float)n, radicalInverse_VdC(i));
			}

			float3 ImportancePhong(float2 Xi, float Roughness, float3 R)
			{
				float Phi = 2 * PI * Xi.x;
				float CosTheta = pow(Xi.y, 1.0 / (Roughness + 2));
				float SinTheta = sqrt(1 - CosTheta * CosTheta);
				float3 H;
				H.x = SinTheta * cos(Phi);
				H.y = SinTheta * sin(Phi);
				H.z = CosTheta;
				float3 UpVector = abs(R.y) < 0.999 ? float3(0, 1, 0) : float3(1, 0, 0);
				float3 TangentX = normalize(cross(R, UpVector));
				float3 TangentY = cross(R, TangentX);
				return TangentX * H.x + TangentY * H.y + R * H.z;
			}

			float3 fix_cube_lookup_for_lod(float3 v, float cube_size, float lod)
			{
				float M = max(max(abs(v.x), abs(v.y)), abs(v.z));
				float scale = 1 - exp2(lod) / cube_size;
				if (abs(v.x) != M) v.x *= scale;
				if (abs(v.y) != M) v.y *= scale;
				if (abs(v.z) != M) v.z *= scale;
				return v;
			}

			fixed4 frag(PS_INPUT input) : SV_Target
			{
				float3 R = fix_cube_lookup_for_lod(input.R, _CubeSize, _Lod);
				float3 N = R;
				float3 V = R;

				float3 prefilteredColor = float3(0, 0, 0);

				const uint numSamples = 2048;
				for (uint i = 0; i < numSamples; ++i)
				{
					float2 Xi = Hammersley(i, numSamples);

					float3 L = ImportancePhong(Xi, alpha, N);

					prefilteredColor += texCUBE(input_envmap, L).rgb;
				}

				float3 final = prefilteredColor / numSamples;
				return float4(final, 1.0);
			}

			ENDCG
		}
	}
}
