Shader "PBR/EnvMapPrefilter_GGX"
{
	SubShader
	{
		Tags{ "RenderType" = "Opaque" }
		LOD 100

		Pass //prefiltering pass
		{
			CGPROGRAM

			#pragma vertex vert
			#pragma fragment frag

			#pragma enable_d3d11_debug_symbols

			#include "UnityCG.cginc"
			#include "Assets/Prefiltering/Shaders/PrefilterCommon.cginc" 

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

			fixed4 frag(PS_INPUT input) : SV_Target
			{
				float3 R = normalize(input.R);// fix_cube_lookup_for_lod(normalize(input.R), _CubeSize, _Lod);
				float3 N = R;
				float3 V = R;

				float3 prefilteredColor = float3(0, 0, 0);
				float totalWeight = 0.0;

				const uint numSamples = 2048;
				for (uint i = 0; i < numSamples; ++i)
				{
					float2 Xi = Hammersley(i, numSamples);

					float3 H = ImportanceGGX(Xi, alpha, N);
					float3 L = 2 * dot(V, H) * H - V;

					float NoL = saturate(dot(N, L));
					if (NoL > 0)
					{
						float NoH = saturate(dot(N, H));
						float HoV = saturate(dot(H, V));
						float NoH2 = NoH * NoH;
						float alpha2 = alpha * alpha;
						float den = NoH2 * alpha2 + (1.0f - NoH2);
						float D = alpha2 / (PI * den * den);
						float pdf = (D * NoH / (4 * HoV)) + 0.0001f;

						float saTexel = 4.0f * PI / (6.0f * 1024 * 1024);
						float saSample = 1.0f / (numSamples * pdf + 0.00001f);
						float mipLevel = alpha == 0.0f ? 0.0f : 0.5f * log2(saSample / saTexel);

						prefilteredColor += texCUBElod(input_envmap, float4(L, mipLevel +1)).rgb * NoL;
						totalWeight += NoL;
					}
				}

				float3 final = prefilteredColor / totalWeight;
				return float4(final, 1.0);
			}

			ENDCG
		}

		Pass  //brdf pass
		{
			Cull Off
			ZTest Always

			CGPROGRAM

			#pragma vertex vert
			#pragma fragment frag

			#pragma enable_d3d11_debug_symbols

			#include "UnityCG.cginc"
			#include "Assets/Prefiltering/Shaders/PrefilterCommon.cginc"

			struct PS_INPUT
			{
				float4 Position : SV_POSITION;
				float2 UV : TEXCOORD0;
			};

			PS_INPUT vert(uint index : SV_VERTEXID)
			{
				PS_INPUT output;
				output.UV = float2((index << 1) & 2, index & 2);
				output.Position = float4(output.UV * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
				return output;
			}

			float4 frag(PS_INPUT input) : SV_Target
			{
				float NoV = input.UV.x;
				float alpha = input.UV.y;

				float3 N = float3(0, 0, 1);
				float3 V = 0;
				V.x = sqrt(1.0f - NoV * NoV);
				V.y = 0;
				V.z = NoV;

				float A = 0;
				float B = 0;

				const uint numSamples = 4096;
				for (uint i = 0; i < numSamples; ++i)
				{
					float2 Xi = Hammersley(i, numSamples);

					float3 H = ImportanceGGX(Xi, alpha, N);
					float3 L = 2 * dot(V, H) * H - V;

					float NoL = saturate(L.z);
					float NoH = saturate(H.z);
					float VoH = saturate(dot(V, H));

					if (NoL > 0)
					{
						float k = alpha * alpha * 0.5;
						float G1 = NoV / (NoV * (1 - k) + k);
						float G2 = NoL / (NoL * (1 - k) + k);
						float G = G1 * G2 * VoH / (NoH * NoV);
						float fc = pow(1 - VoH, 5);
						A += (1 - fc) * G;
						B += fc * G;
					}
				}

				return float4(float2(A, B) / numSamples, 0, 0);
			}

			ENDCG
		}
	}
}
