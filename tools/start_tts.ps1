# 启动本地神经 TTS 服务（IndexTTS2）。
#
# 游戏侧不直接跑模型：游戏是 Godot，模型是 PyTorch，中间用本地 HTTP 传 WAV。
# 这个脚本就是把那台"本地服务"拉起来，并喂给它两段参考音色
# （controller = 管制，pilot = 机组；IndexTTS2 靠参考音做音色克隆）。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\start_tts.ps1
#   powershell -ExecutionPolicy Bypass -File tools\start_tts.ps1 -NoWindow
#
# 前置：先跑过 tools\setup_indextts2.ps1（装依赖与模型）。
param(
    [string]$ModelDir = "D:\models\IndexTTS2",
    [int]$Port = 8731,
    [string]$Venv = "",
    [switch]$Cpu,
    [switch]$Mock,
    [switch]$NoWindow
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj = Split-Path -Parent $here
if ($Venv -eq "") { $Venv = Join-Path $proj ".venv-tts" }
$vpy = Join-Path $Venv "Scripts\python.exe"
if (-not (Test-Path $vpy)) { $vpy = "python" }

$server = Join-Path $here "tts_server.py"
$ctl = Join-Path $proj "assets\audio\voices\controller.wav"
$pit = Join-Path $proj "assets\audio\voices\pilot.wav"

$args = @($server, "--port", "$Port")
if ($Mock) {
    $args += "--mock"
} else {
    $args += @("--model-dir", $ModelDir)
    if ($ctl) { if (Test-Path $ctl) { $args += @("--voice-controller", $ctl) } }
    if ($pit) { if (Test-Path $pit) { $args += @("--voice-pilot", $pit) } }
    if ($Cpu) { $args += @("--device", "cpu") }
}

Write-Host "启动 TTS 服务：$vpy $($args -join ' ')"
if ($NoWindow) {
    Start-Process -FilePath $vpy -ArgumentList $args -WindowStyle Hidden
    Start-Sleep -Seconds 3
    try {
        $h = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 5 -UseBasicParsing
        Write-Host "health: $($h.Content)"
    } catch { Write-Host "服务可能还在加载模型，稍后再看 http://127.0.0.1:$Port/health" }
} else {
    & $vpy @args
}
