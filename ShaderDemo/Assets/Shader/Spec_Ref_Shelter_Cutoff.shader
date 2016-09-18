Shader "Test/Spec_Ref_Shelter_Cutoff" {
	Properties {
		_Color ("Color", Color) = (1,1,1,1)
		_MainTex ("MainTex RGB", 2D) = "white" {}
		_BumpMap ("Normal Map", 2D) = "bump" {}
		_SpecIllumBloods ("Spec Illum Bloods", 2D) = "white" {}
		_IllumColor("Illum Color", Color) = (1,0.007352948,0.007352948,1)
		_MainTex_AlphaReflRange ("(R)Alpha(G)ReflRange(B)Null", 2D) = "white" {}
		_Gloss ("Gloss", Range(0,1)) = 0.5
		_ReflectionCubeMap ("Reflection Cube Map", Cube) = "_Skybox" {}
		_ReflectionControl("Reflection Control", Float) = 1
		[HideInInspector] _Cutoff("Alpha Cutoff", Range(0,1)) = 0.5
		_RimColor("RimColor", Color) = (0,1,1,1)
		_RimPower("RimPower", Range(0.1, 8.0)) = 1.0
	}
	SubShader{
		Tags {"Queue" = "AlphaTest" "RenderType" = "TransparentCutout"}
		Pass {
			Blend SrcAlpha One
			ZWrite off
			Lighting off
			ztest greater

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"

			fixed4 _RimColor;
			half _RimPower;

			struct appdata_t {
				float4 vertex:POSITION;
				fixed4 color:COLOR;
				half4 normal:NORMAL;
			};

			struct v2f {
				float4 Pos:SV_POSITION;
				fixed4 color:COLOR;
			};

			v2f vert(appdata_t v) {
				v2f o;
				o.Pos = mul(UNITY_MATRIX_MVP, v.vertex);
				float3 viewDir = normalize(ObjSpaceViewDir(v.vertex));
				float rim = 1 - saturate(dot(viewDir, v.normal));
				o.color = _RimColor * pow(rim, _RimPower);
				return o;
			}

			half4 frag(v2f i):COLOR {
				return i.color;
			}
			ENDCG
		}

		Pass {
			Name "FORWARD"
			Tags {"LightMode" = "ForwardBase"}

			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#include "UnityCG.cginc"
			#include "AutoLight.cginc"
			#include "Lighting.cginc"
			#pragma multi_compile_fwdbase_fullshadows
			#pragma target 3.0
			uniform float4 _Color;
			uniform sampler2D _MainTex; uniform float4 _MainTex_ST;
			uniform sampler2D _BumpMap; uniform float4 _BumpMap_ST;
			uniform float _Gloss;
			uniform float4 _IllumColor;
			uniform sampler2D _MainTex_AlphaReflRange; uniform float4 _MainTex_AlphaReflRange_ST;
			uniform sampler2D _SpecIllumBloods; uniform float4 _SpecIllumBloods_ST;
			uniform samplerCUBE _ReflectionCubeMap;
			uniform float _ReflectionControl;

			struct VertexInput
			{
				float4 vertex : Position;
				float3 normal : NORMAL;
				float3 tangent : TANGENT;
				float2 texcoord0 : TEXCOORD0;
				float2 texcoord1 : TEXCOORD1;
			};

			struct VertexOutput
			{
				float4 pos : SV_POSITION;
				float2 uv0 : TEXCOORD0;
				float2 uv1 : TEXCOORD1;
				float4 posWorld : TEXCOORD2;
				float3 normalDir : TEXCOORD3;
				float3 tangentDir : TEXCOORD4;
				float3 bitangentDir : TEXCOORD5;
				LIGHTING_COORDS(6,7)
				float4 ambientOrLightmapUV : TEXCOORD8;
				UNITY_FOG_COORDS(9)
			};

			VertexOutput vert (VertexInput v)
			{
				VertexOutput o = (VertexOutput)0;
				o.uv0 = v.texcoord0;
				o.uv1 = v.texcoord1;
				#ifdef LIGHTMAP_ON
					o.ambientOrLightmapUV.xy = v.texcoord1 * unity_LightmalST.xy + unity_LightmalST.zw;
					o.ambientOrLightmapUV.zw = 0;
				#elif UINITY_SHOULD_SAMPLE_SH
				#endif
				o.normalDir = UnityObjectToWorldNormal(v.normal);
				o.tangentDir = normalize(mul(_Object2World, float4(v.tangent.xyz, 0.0)).xyz);
				//o.bitangentDir = normalize(cross(o.normalDir, o.tangentDir) * v.tangent.w);
				o.posWorld = mul(_Object2World, v.vertex);
				o.pos = mul(UNITY_MATRIX_MVP, v.vertex);
				TRANSFER_VERTEX_TO_FRAGMENT(o)
				UNITY_TRANSFER_FOG(o, o.pos);
				return o;
			}

			float4 frag (VertexOutput i) :COLOR
			{
			//CutOff:
				float4 _MainTex_AlphaReflRange_var = tex2D(_MainTex_AlphaReflRange, TRANSFORM_TEX(i.uv0, _MainTex_AlphaReflRange));
				clip(_MainTex_AlphaReflRange_var.r - 0.5);
			//Calculate World Bump Normal:
				i.normalDir = normalize(i.normalDir);
				float3x3 tangentTransform = float3x3(i.tangentDir, i.bitangentDir, i.normalDir);
				float3 normalLocal = UnpackNormal(tex2D(_BumpMap, TRANSFORM_TEX(i.uv0, _BumpMap)));
				float3 normalDirection = normalize(mul(normalLocal, tangentTransform)); //Perturbed normals

				float3 viewDirection = normalize(_WorldSpaceCameraPos.xyz - i.posWorld.xyz);
				float3 viewReflectDirection = reflect(-viewDirection, normalDirection);
				float3 lightDirection = normalize(_WorldSpaceLightPos0.xyz);
				float3 lightColor = _LightColor0.rgb;
				float3 halfDirection = normalize(viewDirection + lightDirection);
			//Lighting:
				float attenuation = LIGHT_ATTENUATION(i);
				float3 attenColor = attenuation * _LightColor0.xyz;
			//Gloss:
				float gloss = _Gloss;
				float specPow = exp2(gloss * 10.0 + 1.0);
			//GI Data:
				UnityLight light;
				light.color = lightColor;
				light.dir = lightDirection;
				light.ndotl = LambertTerm (normalDirection, light.dir);
				UnityGIInput d;
				d.light = light;
				d.worldPos = i.posWorld.xyz;
				d.worldViewDir = viewDirection;
				d.atten = attenuation;
				d.ambient = i.ambientOrLightmapUV;
				d.boxMax[0] = unity_SpecCube0_BoxMax;
				d.boxMin[0] = unity_SpecCube0_BoxMin;
				d.probePosition[0] = unity_SpecCube0_ProbePosition;
				d.probeHDR[0] = unity_SpecCube0_HDR;
				d.boxMax[1] = unity_SpecCube1_BoxMax;
				d.boxMin[1] = unity_SpecCube1_BoxMin;
				d.probePosition[1] = unity_SpecCube1_ProbePosition;
				d.probeHDR[1] = unity_SpecCube1_HDR;
				Unity_GlossyEnvironmentData ugls_en_data;
				ugls_en_data.roughness = 1.0 - gloss;
				ugls_en_data.reflUVW = viewReflectDirection;
				UnityGI gi = UnityGlobalIllumination(d, 1, normalDirection, ugls_en_data);
				lightDirection = gi.light.dir;
				lightColor = gi.light.color;
			//Specular:
				float NdotL = max(0, dot(normalDirection, lightDirection));
				float LdotH = max(0.0, dot(lightDirection, halfDirection));
				float4 mixed = tex2D(_SpecIllumBloods, TRANSFORM_TEX(i.uv0, _SpecIllumBloods));
				float3 specularColor = float3(mixed.r, mixed.r, mixed.r);
				float NdotV = max(0.0, dot(normalDirection, viewDirection));
				float NdotH = max(0.0, dot(normalDirection, halfDirection));
				float visTerm = SmithBeckmannVisibilityTerm(NdotL, NdotV, 1.0 - gloss);
				float normTerm = max(0.0, NDFBlinnPhongNormalizedTerm(NdotH, RoughnessToSpecPower(1.0 - gloss)));
				float specularPBL = max(0, (NdotL * visTerm * normTerm) * (UNITY_PI / 4));
				float3 directSpecular = 1 * pow(max(0, dot(halfDirection, normalDirection)), specPow) * specularPBL * lightColor * FresnelTerm(specularColor, LdotH);
				half grazingTerm = saturate(gloss + mixed.r);
				float3 indirectSpecular = (gi.indirect.specular);
				indirectSpecular *= FresnelLerp(specularColor, grazingTerm, NdotV);
				float3 specular = directSpecular + indirectSpecular;
			//Diffuse:
				float3 directDiffuse = NdotL * attenColor;
				float3 indirectDiffuse = _MainTex_AlphaReflRange_var.g * texCUBE(_ReflectionCubeMap, normalDirection).rgb * _ReflectionControl; // cubemap reflect color
				indirectDiffuse += gi.indirect.diffuse; // Diffuse Ambient Light
				float4 mainTex = tex2D(_MainTex, TRANSFORM_TEX(i.uv0, _MainTex));
				float4 mixed1 = tex2D(_SpecIllumBloods, TRANSFORM_TEX(i.uv1, _SpecIllumBloods));
				float3 diffuseColor = mainTex.rgb * _Color.rgb;
				diffuseColor *= 1 - mixed.r;
				float3 diffuse = (directDiffuse + indirectDiffuse) * diffuseColor;
			//Emissive:
				float3 emissive = (mixed.g * _IllumColor.rgb);
			//Final Color:
				float3 finalColor = diffuse + specular + emissive;
				fixed4 finalRGBA = fixed4(finalColor, 1);
				UNITY_APPLY_FOG(i.fogCoord, finalRGBA);
				return finalRGBA;
			}

			ENDCG
		}
	}
	FallBack "Diffuse"
}