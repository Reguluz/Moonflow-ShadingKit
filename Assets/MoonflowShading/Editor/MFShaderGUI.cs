using System.Collections;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;

public class MFShaderGUI : ShaderGUI
{
    private string keywords;
    public override void OnGUI(MaterialEditor materialEditor, MaterialProperty[] properties)
    {
        Material targetMat = materialEditor.target as Material;
        MakeKeywordList(targetMat.shaderKeywords);
        base.OnGUI(materialEditor, properties);
    }

    public override void OnMaterialPreviewGUI(MaterialEditor materialEditor, Rect r, GUIStyle background)
    {
        base.OnMaterialPreviewGUI(materialEditor, r, background);
    }

    private void MakeKeywordList(string[] keywordArr)
    {
        keywords = "";
        for (int i = 0; i < keywordArr.Length; i++)
        {
            keywords += keywordArr[i] + " ";
            if (i != keywordArr.Length - 1)
            {
                keywords += " | ";
            }
        }
        using (new EditorGUILayout.VerticalScope("box"))
        {
            EditorGUILayout.LabelField("Current Keywords：");
            EditorGUILayout.SelectableLabel(keywords, EditorStyles.textField, GUILayout.Height(EditorGUIUtility.singleLineHeight));
        }
    }
}
