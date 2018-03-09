Shader "PBR/GGX"
{
	Properties
	{
		_Color("Color", Color) = (0, 0, 0, 1)
		_NormalMap("Normal Map", 2D) = "white" {}
		_Roughness("Roughness", Range(0, 1)) = 0
		_Metalness("Metalness", Range(0, 1)) = 0.04
		_Envmap("Envmap", Cube) = "white" {}
		_BRDF("BRDF", 2D) = "white" {}
	}
	SubShader
	{
		Tags{ "RenderType" = "Opaque" "LightMode" = "ForwardBase" }
		LOD 100

		Pass
		{
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#pragma multi_compile_fwdadd_fullshadows

			#include "UnityCG.cginc"
			#include "AutoLight.cginc"

			struct appdata
			{
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				float3 normal : NORMAL;
				float4 tangent : TANGENT;
			};

			struct v2f
			{
				float4 pos : SV_POSITION;
				float2 uv : TEXCOORD0;
				float4 world_pos : TEXCOORD1;
				float3 world_normal : TEXCOORD2;
				float4 world_tangent : TEXCOORD3;
				LIGHTING_COORDS(4, 5)
			};

			sampler2D _NormalMap;
			samplerCUBE _Envmap;
			sampler2D _BRDF;

			float4 _Color;
			float _Roughness;
			float _Metalness;

			v2f vert(appdata v)
			{
				v2f o;
				o.pos = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;

				o.world_normal = UnityObjectToWorldNormal(v.normal);
				o.world_tangent = float4(UnityObjectToWorldDir(v.tangent), v.tangent.w);

				o.world_pos = mul(unity_ObjectToWorld, v.vertex);

				TRANSFER_VERTEX_TO_FRAGMENT(o);

				return o;
			}

			fixed4 frag(v2f i) : SV_Target
			{
				//VECTORS
				float3 vertexN = normalize(i.world_normal);
				float3 T = normalize(i.world_tangent);
				float3 B = cross(vertexN, T) * i.world_tangent.w;
				float3x3 worldToTangent = float3x3(T, B, vertexN);
				float3 tangentN = UnpackNormal(tex2D(_NormalMap, i.uv));
				float3 N = mul(tangentN, worldToTangent);
				float3 V = normalize(_WorldSpaceCameraPos.xyz - i.world_pos);
				float3 R = reflect(-V, N);

				//DOTS
				float NdotV = saturate(dot(N, V));

				//INDIRECT SPECULAR
				float2 brdfUV = float2(NdotV, _Roughness);
				float2 preBRDF = tex2D(_BRDF, brdfUV).xy;

				float4 indirectSpecular = texCUBElod(_Envmap, float4(R, _Roughness * 5)) * (_Metalness * preBRDF.x + preBRDF.y);

				//INDIRECT DIFFUSE
				float atten = LIGHT_ATTENUATION(i);
				float lambert = saturate(max(0, dot(N, _WorldSpaceLightPos0)) * atten);
				float4 indirectDiffuse = texCUBElod(_Envmap, float4(N, 5)) * _Color * lambert;
				
				//FRESNEL FACTOR
				float VdotH5 = pow(1.0f - NdotV, 5);
				float F = _Metalness + (1.0f - _Metalness) * VdotH5;

				return lerp(indirectDiffuse, indirectSpecular, F);
			}

			ENDCG
		}
	}

	FallBack "Diffuse"
}
