using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEditor;

public enum PotSize
{
    _16 = 16,
    _32 = 32,
    _64 = 64,
    _128 = 128,
    _256 = 256,
    _512 = 512,
    _1024 = 1024,
    _2048 = 2048,
    _4096 = 4096
}

public enum BRDF
{
    Phong,
    GGX
}

public class EnvMapEditor : EditorWindow
{
    [MenuItem("Window/EnvMap")]
    public static void ShowWindow()
    {
        EditorWindow.GetWindow(typeof(EnvMapEditor));
    }

    //PUBLIC FIELDS
    public Cubemap              input_cubemap;
    public RenderTextureFormat  output_format;
    public PotSize              output_size = PotSize._1024;
    public bool                 output_srgb = true;
    public BRDF                 brdf;
    public float                startAlpha;
    public float                alphaMipDrop;

    //PRIVATE FIELDS
    private string          prefiltered_name = "";
    private int             view_mip = 0;
    private int             num_mips = 0;
    private Material        view_mat;
    private RenderTexture   output_cubemap;

    private SerializedObject so;
    private SerializedProperty sp_input_cubemap;
    private SerializedProperty sp_output_format;
    private SerializedProperty sp_output_size;
    private SerializedProperty sp_output_srgb;
    private SerializedProperty sp_brdf;
    private SerializedProperty sp_startAlpha;
    private SerializedProperty sp_alphaMipDrop;

    //PRIVATE METHODS
    private void Awake()
    {
        Initialize();
    }

    private void OnFocus()
    {
        Initialize();
    }

    private void Initialize()
    {
        so = new SerializedObject(this);
        sp_input_cubemap = so.FindProperty("input_cubemap");
        sp_output_format = so.FindProperty("output_format");
        sp_output_size = so.FindProperty("output_size");
        sp_output_srgb = so.FindProperty("output_srgb");
        sp_brdf = so.FindProperty("brdf");
        sp_startAlpha = so.FindProperty("startAlpha");
        sp_alphaMipDrop = so.FindProperty("alphaMipDrop");
    }

    //Convert a RenderTextureFormat to TextureFormat
    private TextureFormat ConvertFormat(RenderTextureFormat input_format)
    {
        TextureFormat output_format = TextureFormat.RGBA32;

        switch (input_format)
        {
            case RenderTextureFormat.ARGB32:
                output_format = TextureFormat.RGBA32;
                break;

            case RenderTextureFormat.ARGBHalf:
                output_format = TextureFormat.RGBAHalf;
                break;

            case RenderTextureFormat.ARGBFloat:
                output_format = TextureFormat.RGBAFloat;
                break;

            default:
                string format_string = System.Enum.GetName(typeof(RenderTextureFormat), input_format);
                int format_int = (int)System.Enum.Parse(typeof(TextureFormat), format_string);
                output_format = (TextureFormat)format_int;
                break;
        }

        return output_format;
    }

    private void OnGUI()
    {
        //input section
        EditorGUILayout.Space();

        EditorGUILayout.PropertyField(sp_input_cubemap);

        //input texture info
        if (input_cubemap != null)
        {
            string info = input_cubemap.width.ToString() + "x" + input_cubemap.height.ToString() + " " + input_cubemap.format.ToString();
            EditorGUILayout.LabelField(info);
        }

        EditorGUILayout.Space();
        EditorGUILayout.LabelField("", GUI.skin.horizontalSlider);
        EditorGUILayout.Space();

        EditorGUILayout.PropertyField(sp_output_size);
        EditorGUILayout.PropertyField(sp_output_format);
        EditorGUILayout.PropertyField(sp_output_srgb);
        EditorGUILayout.PropertyField(sp_brdf);

        if (brdf == BRDF.Phong)
        {
            EditorGUILayout.PropertyField(sp_startAlpha);
            EditorGUILayout.PropertyField(sp_alphaMipDrop);
        }

        so.ApplyModifiedProperties();
        

        //prefilter section
        GUI.enabled = input_cubemap != null;

        if (GUILayout.Button("Prefilter"))
        {
            num_mips = Mathf.Min(6, 1 + (int)Mathf.Log((float)((int)output_size), 2));  //max 6 mipmaps

            input_cubemap.filterMode = FilterMode.Trilinear;
            input_cubemap.wrapMode = TextureWrapMode.Clamp;

            input_cubemap.SmoothEdges();

            RenderTextureDescriptor rtd = new RenderTextureDescriptor();
            rtd.autoGenerateMips = false;
            rtd.colorFormat = output_format;
            rtd.depthBufferBits = 0;
            rtd.dimension = TextureDimension.Cube;
            rtd.enableRandomWrite = false;
            rtd.height = (int)output_size;
            rtd.memoryless = RenderTextureMemoryless.None;
            rtd.msaaSamples = 1;
            rtd.shadowSamplingMode = ShadowSamplingMode.None;
            rtd.sRGB = output_srgb;
            rtd.useMipMap = true;
            rtd.volumeDepth = 1;
            rtd.width = (int)output_size;

            output_cubemap = new RenderTexture(rtd);
            output_cubemap.filterMode = FilterMode.Trilinear;
            output_cubemap.wrapMode = TextureWrapMode.Clamp;

            CommandBuffer cb = new CommandBuffer();

            Material mat = null;

            if (brdf == BRDF.Phong)
                mat = new Material(Shader.Find("PBR/EnvMapPrefilter_Phong"));
            else if (brdf == BRDF.GGX)
                mat = new Material(Shader.Find("PBR/EnvMapPrefilter_GGX"));

            mat.SetTexture("input_envmap", input_cubemap);
            mat.SetFloat("_CubeSize", rtd.width);
            mat.SetFloat("numLod", num_mips);

            float alpha = startAlpha;
            if (brdf == BRDF.GGX)
                alpha = 0.0f;

            //cycle mips and faces
            for (int mip = 0; mip < num_mips; ++mip)
            {
                if (brdf == BRDF.GGX)
                {
                    alpha = mip / (float)(num_mips - 1);
                }

                cb.SetGlobalFloat("_Lod", mip);
                cb.SetGlobalFloat("alpha", alpha);

                for (int face = 0; face < 6; ++face)
                {
                    cb.SetRenderTarget(output_cubemap, mip, (CubemapFace)face);
                    cb.SetGlobalFloat("face", face);
                    cb.DrawProcedural(Matrix4x4.identity, mat, 0, MeshTopology.Triangles, 3);
                }
                
                if (brdf == BRDF.Phong)
                {
                    alpha *= alphaMipDrop;
                }
            }
            Graphics.ExecuteCommandBuffer(cb);
            
            Object.DestroyImmediate(mat);
        }

        //this is for saving the precomputed second term of the splitted sum formula (from the UE4 pbr paper)
        if (brdf == BRDF.GGX)
        {
            if (GUILayout.Button("Save GGX BRDF"))
            {
                RenderTexture brdf_rt = new RenderTexture(512, 512, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Linear);
                brdf_rt.Create();
                Material mat = new Material(Shader.Find("PBR/EnvMapPrefilter_GGX"));

                CommandBuffer cb = new CommandBuffer();                
                cb.SetRenderTarget(brdf_rt);
                cb.DrawProcedural(Matrix4x4.identity, mat, 1, MeshTopology.Triangles, 3);

                Graphics.ExecuteCommandBuffer(cb);

                Object.DestroyImmediate(mat);

                Texture2D brdf_tex = new Texture2D(512, 512, TextureFormat.RGBAFloat, false, true);
                brdf_tex.wrapMode = TextureWrapMode.Clamp;
                RenderTexture.active = brdf_rt;
                brdf_tex.ReadPixels(new Rect(0, 0, 512, 512), 0, 0);
                brdf_tex.Apply();

                AssetDatabase.CreateAsset(brdf_tex, "Assets/ggx_brdf.asset");
            }
        }

        //save section
        GUI.enabled = true;

        EditorGUILayout.Space();
        EditorGUILayout.LabelField("", GUI.skin.horizontalSlider);
        EditorGUILayout.Space();

        so.ApplyModifiedProperties();

        EditorGUILayout.Space();

        prefiltered_name = EditorGUILayout.TextField("Prefiltered name", prefiltered_name);
        bool save_enabled = prefiltered_name != "" && output_cubemap != null;
        GUI.enabled = save_enabled;

        if (GUILayout.Button("Save"))
        {
            int current_size = (int)output_size;
            Cubemap asset_to_save = new Cubemap(current_size, ConvertFormat(output_format), true);
            asset_to_save.filterMode = FilterMode.Trilinear;
            asset_to_save.wrapMode = TextureWrapMode.Clamp;

            RenderTextureDescriptor desc = new RenderTextureDescriptor();
            desc.autoGenerateMips = false;
            desc.colorFormat = output_format;
            desc.depthBufferBits = 0;
            desc.dimension = TextureDimension.Tex2D;
            desc.enableRandomWrite = false;
            desc.msaaSamples = 1;
            desc.sRGB = output_cubemap.sRGB;
            desc.useMipMap = true;
            desc.volumeDepth = 1;            

            //cycle foreach mip level and foreach face
            for (int mip = 0; mip < num_mips; ++mip)
            {
                //need a temporary texture2d and render target
                Texture2D tmp_tex = new Texture2D(current_size, current_size, asset_to_save.format, false, output_cubemap.sRGB);
                tmp_tex.filterMode = FilterMode.Trilinear;
                tmp_tex.wrapMode = TextureWrapMode.Clamp;

                desc.width = desc.height = current_size;
                RenderTexture tmp_rt = new RenderTexture(desc);
                tmp_rt.filterMode = FilterMode.Trilinear;
                tmp_rt.wrapMode = TextureWrapMode.Clamp;
                tmp_rt.Create();

                for (int face = 0; face < 6; ++face)
                {
                    //first copy the selected face for the selected mip into the temporary render target
                    Graphics.CopyTexture(output_cubemap, face, mip, tmp_rt, 0, 0);

                    //then copy from the temporary render target to the temporary texture 2d
                    RenderTexture.active = tmp_rt;
                    tmp_tex.ReadPixels(new Rect(0, 0, current_size, current_size), 0, 0, false);

                    //then from the temporary texture to the cubemap (all of this workaround is because cubemap class doesn't provide a ReadPixels method)
                    Color[] colors = tmp_tex.GetPixels();
                    Color[] flipped = new Color[colors.Length];

                    //need to flip the y
                    for (int y = 0; y < current_size; ++y)
                    {
                        for (int x = 0; x < current_size; ++x)
                        {
                            int flipped_y = current_size - 1 - y;
                            int src_index = flipped_y * current_size + x;
                            int dest_index = y * current_size + x;
                            flipped[dest_index] = colors[src_index];
                        }
                    }

                    asset_to_save.SetPixels(flipped, (CubemapFace)face, mip);
                }

                current_size /= 2;
            }

            asset_to_save.Apply(false);

            asset_to_save.SmoothEdges(10);

            AssetDatabase.CreateAsset(asset_to_save, prefiltered_name);
        }
        
        GUI.enabled = output_cubemap != null;
        if (GUILayout.Button("Delete"))
        {
            output_cubemap.Release();
            Object.DestroyImmediate(output_cubemap);
            output_cubemap = null;            
        }

        //view section
        EditorGUILayout.Space();
        EditorGUILayout.LabelField("", GUI.skin.horizontalSlider);
        EditorGUILayout.Space();

        GUI.enabled = output_cubemap != null;
        
        if (GUILayout.Button("View"))
        {
            view_mat = new Material(Shader.Find("PBR/EnvMapShader"));
            view_mat.SetTexture("_EnvMap", output_cubemap);
            view_mat.SetFloat("_LodLevel", view_mip);

            RenderSettings.skybox = view_mat;
        }

        EditorGUI.BeginChangeCheck();

        view_mip = (int)EditorGUILayout.Slider("Mip level", view_mip, 0, num_mips);

        if (EditorGUI.EndChangeCheck())
        {
            view_mat.SetFloat("_LodLevel", view_mip);
        }

        GUI.enabled = true;

    }
}
