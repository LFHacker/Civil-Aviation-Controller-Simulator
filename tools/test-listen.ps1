# 语音识别链路端到端验证（08 §4「听」）。
#
# 验证的不是"能不能识别中文"，而是**能不能判出机组读错了哪一项**：
#   ① 用逻辑层 VoiceGrammar.build() 生成闭集语法（正确 + 五项各错一位）；
#   ② 把每条候选念成音频（edge-tts，开发机用；游戏运行时不依赖它）；
#   ③ 交给 tools/atc-listen/AtcListen.exe 识别；
#   ④ 断言返回的规则名 == 当初生成的那条变体标签。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\test-listen.ps1
#   powershell -ExecutionPolicy Bypass -File tools\test-listen.ps1 -KeepAudio
#
# 依赖：Godot（可用 -Godot 指定）、AtcListen.exe（未编译时自动用 csc 编）、
#       生成音频需要 python + edge-tts + ffmpeg（没有就跳过，只验证语法与编译）。
param(
    [string]$Godot = "D:\0.computer\1.Python\Game-chase\_tools\godot\Godot_v4.7.2-stable_win64_console.exe",
    [string]$Python = "",
    [string]$Ffmpeg = "ffmpeg",
    [switch]$KeepAudio
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj = Split-Path -Parent $here
$work = Join-Path $env:TEMP "atc-listen-test"
New-Item -ItemType Directory -Force -Path $work | Out-Null

$fail = 0
$checks = 0
function Check([bool]$cond, [string]$name, [string]$detail = "") {
    $script:checks++
    if ($cond) { Write-Host ("    PASS  " + $name) }
    else {
        $script:fail++
        if ($detail -eq "") { Write-Host ("    FAIL  " + $name) } else { Write-Host ("    FAIL  " + $name + "  -> " + $detail) }
    }
}

Write-Host ""
Write-Host "======== 语音识别链路端到端验证 ========"

# ---- 1. 编译识别助手 ----
$exe = Join-Path $here "atc-listen\AtcListen.exe"
if (-not (Test-Path $exe)) {
    Write-Host "· 编译 AtcListen.exe"
    $csc = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    $ss = Get-ChildItem (Join-Path $env:WINDIR "Microsoft.NET\assembly\GAC_MSIL\System.Speech") -Recurse -Filter System.Speech.dll | Select-Object -First 1
    if (-not (Test-Path $csc) -or $null -eq $ss) { Write-Host "  找不到 csc 或 System.Speech.dll，无法编译"; exit 2 }
    & $csc /nologo /target:exe /out:$exe /r:$ss.FullName (Join-Path $here "atc-listen\AtcListen.cs") | Out-Null
    if (-not (Test-Path $exe)) { Write-Host "  编译失败"; exit 2 }
}
Check (Test-Path $exe) "识别助手可用"

# ---- 2. 用逻辑层生成语法 ----
Write-Host "· 生成语法（逻辑层 VoiceGrammar.build）"
$dump = & $Godot --headless --path $proj --script res://tools/dump_voice_grammar.gd -- $work 2>&1 | Out-String
$mLines = [regex]::Match($dump, "GRAMMAR_ITEMS:(\d+)")
$mTags = [regex]::Match($dump, "GRAMMAR_TAGS:([\w,]+)")
$srgs = Join-Path $work "readback.srgs"
Check ($mLines.Success -and [int]$mLines.Groups[1].Value -eq 6) "生成 6 条候选" $dump
Check (Test-Path $srgs) "语法文件已写盘"
$tags = @()
if ($mTags.Success) { $tags = $mTags.Groups[1].Value -split "," }
Check ($tags.Count -eq 6) "标签齐 ${tags}" ($tags -join ",")

# ---- 3. 生成音频（可选） ----
$audio = @{}
$canSynth = $false
if ($Python -eq "") { $Python = "python" }
try {
    & $Python -c "import edge_tts" 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $canSynth = $true }
} catch { $canSynth = $false }

$xml = [IO.File]::ReadAllText($srgs, [Text.Encoding]::UTF8)
$items = [regex]::Matches($xml, '<rule id="(\w+)" scope="public">(.*?)</rule>')
Check ($items.Count -eq 6) "语法里能解析出 6 条规则" ($items.Count)

if ($canSynth) {
    Write-Host "· 合成音频并识别"
    foreach ($m in $items) {
        $tag = $m.Groups[1].Value
        $text = $m.Groups[2].Value
        $mp3 = Join-Path $work ("e2e_" + $tag + ".mp3")
        $wav = Join-Path $work ("e2e_" + $tag + ".wav")
        & $Python -m edge_tts --voice zh-CN-YunxiNeural --rate=+10% --text $text --write-media $mp3 2>&1 | Out-Null
        & $Ffmpeg -y -loglevel error -i $mp3 -ar 16000 -ac 1 -c:a pcm_s16le $wav
        $audio[$tag] = $wav
    }
} else {
    Write-Host "  跳过音频合成：没有可用的 edge-tts（只验证语法与助手）"
}

# ---- 4. 跑识别 ----
# ⚠️ 命令必须逐条单独拼成字符串：把 "grammar 路径" 与标签写成数组元素里的拼接表达式时，
# PowerShell 会把它拆成两条命令发过去（踩过），后面所有结果就整体错位一行。
$grammarCmd = "grammar {0} {1}" -f $srgs, ($tags -join ",")
$cmds = @("ping")
$cmds += $grammarCmd
foreach ($t in $tags) { if ($audio.ContainsKey($t)) { $cmds += ("recog " + $audio[$t]) } }
$cmds += "quit"
$lines = $cmds | & $exe 2>&1
$i = 0
foreach ($line in $lines) {
    Write-Host ("    " + $line)
    $i++
}
Check ($i -ge 2) "助手有回应（ping + grammar）" ($lines -join " / ")
if ($lines.Count -ge 2) {
    Check ($lines[0] -match '"ok":true') "识别引擎就绪" $lines[0]
    Check ($lines[1] -match '"rules":6') "6 条规则全部加载" $lines[1]
}

if ($audio.Count -gt 0) {
    # 第 3 行起是识别结果，顺序与 $tags 一致
    for ($k = 0; $k -lt $tags.Count; $k++) {
        $tag = $tags[$k]
        $idx = 2 + $k
        if ($idx -ge $lines.Count) { Check $false ("识别 " + $tag) "缺回应"; continue }
        $obj = $lines[$idx]
        $mTag = [regex]::Match($obj, '"tag":"(\w+)"')
        $mMs = [regex]::Match($obj, '"ms":(\d+)')
        $mCf = [regex]::Match($obj, '"confidence":([\d.]+)')
        $got = if ($mTag.Success) { $mTag.Groups[1].Value } else { "" }
        Check ($got -eq $tag) ("识别出 " + $tag) $obj
        if ($mMs.Success) { Check ([int]$mMs.Groups[1].Value -lt 500) ($tag + " 耗时 " + $mMs.Groups[1].Value + "ms（<500ms）") }
        if ($mCf.Success) { Check ([double]$mCf.Groups[1].Value -ge 0.8) ($tag + " 置信度 " + $mCf.Groups[1].Value) }
    }
}

if (-not $KeepAudio) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }

# ---- 5. 接缝：识别出来的文本，逻辑层能不能解析 ----
# 这一步单独验，因为"识别对了"和"解析对了"是两件事：
# 识别器可能回中文数字、全角标点，逻辑层必须能接住（VoiceMode.normalize）。
Write-Host "· 识别文本 → 逻辑层解析"
$okLine = $lines | Where-Object { $_ -match '"tag":"v_ok"' } | Select-Object -First 1
if ($okLine -ne $null) {
    $mText = [regex]::Match($okLine, '"text":"([^"]+)"')
    if ($mText.Success) {
        $recognized = $mText.Groups[1].Value
        $parsed = & $Godot --headless --path $proj --script res://tools/parse_voice_text.gd -- $recognized 2>&1 | Out-String
        $mj = [regex]::Match($parsed, "PARSE_JSON:(\{.*\})")
        Check ($mj.Success) "逻辑层拿到识别文本" $parsed
        if ($mj.Success) {
            $o = $mj.Groups[1].Value | ConvertFrom-Json
            Check ($o.kind -eq "clearance") "判为放行许可通话" $o.kind
            Check ($o.slots.limit -eq "ZSPD") "认出放行界限" $o.slots.limit
            Check ($o.slots.sid -eq "SASAN 5B") "认出离场程序" $o.slots.sid
            Check ([int]$o.slots.alt -eq 6000) "认出初始高度" $o.slots.alt
            Check ([string]$o.slots.squawk -eq "4215") "认出应答机" $o.slots.squawk
        }
    } else { Check $false "识别结果里有文本" $okLine }
} else { Check $false "找到 v_ok 的识别结果" "没跑音频时跳过" }

Write-Host ""
Write-Host "----------------------------------------"
if ($fail -eq 0) { Write-Host ("OK 全部通过：" + $checks + " 项") }
else { Write-Host ("FAILED " + $fail + " / " + $checks + " 项失败") }
exit $(if ($fail -eq 0) { 0 } else { 1 })
