// AtcListen — 常驻的离线语音识别助手（08 §4「听」的执行端）。
//
// 为什么是独立进程：Godot 调不到 Windows 的 SAPI 识别引擎。
// 为什么常驻：识别引擎初始化要几百毫秒，每次说话起一个进程就白等了。
// 所以做成「stdin 收命令、stdout 回一行 JSON」的长驻小工具，
// 引擎只初始化一次，之后每次识别只花几十毫秒。
//
// 协议（一行一条命令，一行一条 JSON 回复）：
//   ping
//     → {"ok":true,"engine":"MS-2052-80-DESK","lang":"zh-CN"}
//   grammar <srgs 文件路径>
//     → {"ok":true,"rules":3}
//     ⚠️ 语法里每条候选的 tag 会被原样带回来，游戏靠它判「读错了哪一项」
//   recog <16k 单声道 PCM wav 路径>
//     → {"ok":true,"text":"...","tag":"qnh_wrong","confidence":0.99,"ms":94}
//     → {"ok":false,"error":"..."}  引擎没识别出东西
//   quit
//
// 编译（不需要 .NET SDK，用系统自带的 csc 即可）：
//   csc /nologo /target:exe /out:AtcListen.exe /r:System.Speech.dll AtcListen.cs
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Speech.Recognition;
using System.Text;
using System.Text.RegularExpressions;

internal static class AtcListen
{
    private static SpeechRecognitionEngine _engine;
    private static string _engineName = "";
    private static string _lang = "";
    private static readonly List<Grammar> _grammars = new List<Grammar>();

    private static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        Console.InputEncoding = Encoding.UTF8;
        // 只认中文识别器，避免拿英文引擎去听中文
        foreach (RecognizerInfo info in SpeechRecognitionEngine.InstalledRecognizers())
        {
            if (info.Culture.Name.StartsWith("zh", StringComparison.OrdinalIgnoreCase))
            {
                _engineName = info.Id;
                _lang = info.Culture.Name;
                break;
            }
        }
        if (_engineName == "")
        {
            WriteJson("{\"ok\":false,\"error\":\"没有中文识别器\"}");
            return 2;
        }
        _engine = new SpeechRecognitionEngine(new CultureInfo(_lang));
        _engine.InitialSilenceTimeout = TimeSpan.FromSeconds(30);
        _engine.EndSilenceTimeout = TimeSpan.Zero;      // 喂文件时不要提前截断
        _engine.EndSilenceTimeoutAmbiguous = TimeSpan.Zero;
        _engine.BabbleTimeout = TimeSpan.FromSeconds(30);

        string line;
        while ((line = Console.ReadLine()) != null)
        {
            line = line.Trim();
            if (line.Length == 0) continue;
            if (line == "quit") break;
            if (line == "ping")
            {
                WriteJson("{\"ok\":true,\"engine\":" + Q(_engineName) +
                          ",\"lang\":" + Q(_lang) + "}");
                continue;
            }
            if (line.StartsWith("grammar "))
            {
                LoadGrammar(line.Substring(8).Trim());
                continue;
            }
            if (line.StartsWith("recog "))
            {
                Recognize(line.Substring(6).Trim());
                continue;
            }
            WriteJson("{\"ok\":false,\"error\":" + Q("未知命令: " + line) + "}");
        }
        if (_engine != null) _engine.Dispose();
        return 0;
    }

    // grammar <srgs 路径> <规则 id 逗号分隔>
    // 每个变体是一条独立规则，逐条加载，识别结果的 RuleName 就是变体标签。
    private static void LoadGrammar(string rest)
    {
        try
        {
            int sp = rest.LastIndexOf(' ');
            string path = sp > 0 ? rest.Substring(0, sp).Trim() : rest;
            string ids = sp > 0 ? rest.Substring(sp + 1).Trim() : "";
            if (!File.Exists(path)) { WriteJson("{\"ok\":false,\"error\":" + Q("找不到语法文件") + "}"); return; }
            foreach (Grammar old in _grammars) _engine.UnloadGrammar(old);
            _grammars.Clear();
            var idList = new List<string>();
            if (ids == "")
            {
                // 没给 id 就按文件里的规则名全加载（root 之前的顺序）
                string xml = File.ReadAllText(path, Encoding.UTF8);
                foreach (Match m in Regex.Matches(xml, "<rule\\s+id=\"([^\"]+)\""))
                    idList.Add(m.Groups[1].Value);
            }
            else
            {
                foreach (string s in ids.Split(','))
                    if (s.Trim() != "") idList.Add(s.Trim());
            }
            foreach (string id in idList)
            {
                var g = new Grammar(path, id);
                _engine.LoadGrammar(g);
                _grammars.Add(g);
            }
            WriteJson("{\"ok\":true,\"rules\":" + _grammars.Count +
                      ",\"ids\":" + Q(string.Join(",", idList.ToArray())) + "}");
        }
        catch (Exception e) { WriteJson("{\"ok\":false,\"error\":" + Q(e.Message) + "}"); }
    }

    private static void Recognize(string wav)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            if (_grammars.Count == 0) { WriteJson("{\"ok\":false,\"error\":" + Q("还没加载语法") + "}"); return; }
            if (!File.Exists(wav)) { WriteJson("{\"ok\":false,\"error\":" + Q("找不到音频") + "}"); return; }
            _engine.SetInputToWaveFile(wav);
            RecognitionResult r = _engine.Recognize();
            sw.Stop();
            if (r == null) { WriteJson("{\"ok\":false,\"error\":\"没识别出内容\",\"ms\":" + sw.ElapsedMilliseconds + "}"); return; }
            string tag = r.Grammar != null && r.Grammar.RuleName != null ? r.Grammar.RuleName : "";
            WriteJson("{\"ok\":true,\"text\":" + Q(r.Text) +
                      ",\"tag\":" + Q(tag) +
                      ",\"confidence\":" + r.Confidence.ToString("0.###", CultureInfo.InvariantCulture) +
                      ",\"ms\":" + sw.ElapsedMilliseconds + "}");
        }
        catch (Exception e)
        {
            sw.Stop();
            WriteJson("{\"ok\":false,\"error\":" + Q(e.Message) + ",\"ms\":" + sw.ElapsedMilliseconds + "}");
        }
    }

    private static string Q(string s)
    {
        if (s == null) return "\"\"";
        var sb = new StringBuilder("\"");
        foreach (char c in s)
        {
            if (c == '"') sb.Append("\\\"");
            else if (c == '\\') sb.Append("\\\\");
            else if (c == '\n') sb.Append("\\n");
            else if (c == '\r') sb.Append("\\r");
            else if (c < ' ') sb.Append("\\u").Append(((int)c).ToString("x4"));
            else sb.Append(c);
        }
        return sb.Append('"').ToString();
    }

    private static void WriteJson(string json)
    {
        Console.Out.Write(json + "\n");
        Console.Out.Flush();
    }
}
