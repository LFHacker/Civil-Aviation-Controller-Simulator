# 本地神经 TTS 服务（IndexTTS2）部署脚本。
#
# 装什么：一个独立虚拟环境 + PyTorch(CUDA) + IndexTTS2 代码与模型权重。
# 模型不随游戏仓库分发（几个 GB），按需下载。
#
# 用法（管理员 PowerShell 不需要，普通用户即可）：
#   powershell -ExecutionPolicy Bypass -File tools\setup_indextts2.ps1
#   powershell -ExecutionPolicy Bypass -File tools\setup_indextts2.ps1 -SkipModel
#
# 装完这样起服务：
#   .venv-tts\Scripts\python.exe tools\tts_server.py --model-dir D:\models\IndexTTS2 `
#       --voice-controller voices\controller.wav --voice-pilot voices\pilot.wav
param(
    [string]$Root = "D:\models",
    [string]$Venv = "D:\0.computer\1.Python\Game-chase\atc-tower\.venv-tts",
    [switch]$SkipModel,
    [switch]$Cpu
)

$ErrorActionPreference = "Stop"
Write-Host "== IndexTTS2 本地部署 =="

# 1. Python 3.10–3.12
$py = "py"
$ver = & $py -3 --version 2>&1
Write-Host "Python: $ver"

# 2. 虚拟环境
if (-not (Test-Path $Venv)) {
    Write-Host "· 创建虚拟环境 $Venv"
    & $py -3 -m venv $Venv
}
$vpy = Join-Path $Venv "Scripts\python.exe"
if (-not (Test-Path $vpy)) { Write-Host "虚拟环境创建失败"; exit 2 }

# 3. 依赖
Write-Host "· 升级 pip"
& $vpy -m pip install --upgrade pip wheel setuptools
if ($Cpu) {
    Write-Host "· 安装 CPU 版 torch（慢，但不需要显卡）"
    & $vpy -m pip install torch torchaudio --index-url https://download.pytorch.org/whl/cpu
} else {
    Write-Host "· 安装 CUDA 版 torch"
    & $vpy -m pip install torch torchaudio --index-url https://download.pytorch.org/whl/cu128
}
Write-Host "· 安装 IndexTTS2"
& $vpy -m pip install -U "git+https://github.com/index-tts/index-tts.git"

if (-not $SkipModel) {
    Write-Host "· 下载模型权重到 $Root\IndexTTS2（几个 GB，耐心等）"
    New-Item -ItemType Directory -Force -Path $Root | Out-Null
    & $vpy -m indextts.cli --model-dir (Join-Path $Root "IndexTTS2") --download
}

Write-Host ""
Write-Host "== 完成 =="
Write-Host "起服务："
Write-Host "  $vpy tools\tts_server.py --model-dir $(Join-Path $Root 'IndexTTS2')"
Write-Host "自检："
Write-Host "  curl http://127.0.0.1:8731/health"
