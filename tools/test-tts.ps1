# 本地神经 TTS 链路端到端验证（不需要模型，用占位后端）。
#
# 做四件事：
#   ① 起一个 mock 的 tts_server.py（返回占位音）；
#   ② 让 Godot 测例连上去做 health + 合成 + WAV 解析；
#   ③ 断言全部通过；
#   ④ 收掉服务进程。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\test-tts.ps1
param(
    [string]$Godot = "D:\0.computer\1.Python\Game-chase\_tools\godot\Godot_v4.7.2-stable_win64_console.exe",
    [string]$Python = "",
    [int]$Port = 8739
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj = Split-Path -Parent $here
if ($Python -eq "") { $Python = "python" }

Write-Host ""
Write-Host "======== 本地神经 TTS 链路验证 ========"
Write-Host "· 启动占位服务（端口 $Port）"
$proc = Start-Process -FilePath $Python -PassThru -WindowStyle Hidden `
    -ArgumentList "`"$here\tts_server.py`"", "--mock", "--port", "$Port"
$url = "http://127.0.0.1:$Port"
$ok = $false
for ($i = 0; $i -lt 20; $i++) {
    Start-Sleep -Milliseconds 400
    try {
        $null = Invoke-WebRequest -Uri "$url/health" -TimeoutSec 2 -UseBasicParsing
        $ok = $true
        break
    } catch { }
}
if (-not $ok) {
    Write-Host "✗ 服务没起来"
    if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    exit 2
}
Write-Host "  health OK"

try {
    $env:ATC_TTS_URL = $url
    $out = & $Godot --headless --path $proj --script res://tests/test_tts.gd 2>&1 | Out-String
    Write-Host $out
    if ($out -match "全部通过：(\d+) 项断言") {
        Write-Host ("OK TTS 链路通过：" + $Matches[1] + " 项")
        exit 0
    }
    Write-Host "FAILED"
    exit 1
}
finally {
    if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    $env:ATC_TTS_URL = ""
}
