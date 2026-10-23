# 本地神经 TTS 服务（IndexTTS2）部署脚本 —— 踩过的坑全部固化在这里。
#
# 装什么：Python 3.11 独立虚拟环境 + PyTorch(cu128) + IndexTTS2 + 模型权重。
#
# 为什么这么多讲究（都是实测踩出来的，别"简化"）：
#   ① IndexTTS 元数据写死 python_requires >=3.10,<3.12 —— 3.12 会被 pip 拒绝。
#   ② download.pytorch.org 在这台机器上会**卡死**（进程有 CPU、临时目录 0 字节）。
#      上海交大镜像实测 ~2 MB/s，阿里云 ~170 KB/s，官方源直接挂。
#   ③ 装 indextts 的依赖链会把 CPU 版 torch 2.8.0 再装一遍，覆盖掉 CUDA 轮子，
#      并留下两个 dist-info，让 transformers 报 "Invalid version: None"。
#      所以装完必须再强装一次 cu128 轮子（--ignore-installed --no-deps）。
#   ④ 模型权重走 ModelScope（实测 3 GB / 60 秒）；HuggingFace 直连会读超时。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tools\setup_indextts2.ps1
#   powershell -ExecutionPolicy Bypass -File tools\setup_indextts2.ps1 -SkipTorch
#   powershell -ExecutionPolicy Bypass -File tools\setup_indextts2.ps1 -SkipModel
param(
    [string]$ModelDir = "D:\models\IndexTTS2",
    [string]$WheelDir = "D:\models\_wheels",
    [string]$Venv = "",
    [string]$Python311 = "C:\Users\Administrator\AppData\Local\Programs\Python\Python311\python.exe",
    [string]$Mirror = "https://mirrors.aliyun.com/pypi/simple",
    [string]$TorchIndex = "https://mirror.sjtu.edu.cn/pytorch-wheels/cu128/",
    [switch]$SkipTorch,
    [switch]$SkipModel,
    [switch]$Cpu
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj = Split-Path -Parent $here
if ($Venv -eq "") { $Venv = Join-Path $proj ".venv-tts" }
$vpy = Join-Path $Venv "Scripts\python.exe"

Write-Host "== IndexTTS2 本地部署 =="
if (-not (Test-Path $Python311)) {
    Write-Host "找不到 Python 3.11：$Python311"
    Write-Host "IndexTTS 要求 >=3.10,<3.12，请先装一个 3.11。"
    exit 2
}
if (-not (Test-Path $vpy)) {
    Write-Host "· 创建虚拟环境 $Venv（Python 3.11）"
    & $Python311 -m venv $Venv
}
& $vpy -m pip install --upgrade pip wheel setuptools | Out-Null

$ver = "2.11.0"
$tag = if ($Cpu) { "cpu" } else { "cu128" }
$wheels = @()
if (-not $SkipTorch) {
    New-Item -ItemType Directory -Force -Path $WheelDir | Out-Null
    foreach ($pkg in @("torch", "torchaudio")) {
        $name = "$pkg-$ver+$tag-cp311-cp311-win_amd64.whl"
        $path = Join-Path $WheelDir $name
        $wheels += $path
        if (Test-Path $path) { continue }
        if ($Cpu) {
            & $vpy -m pip download "$pkg==$ver" --no-deps -d $WheelDir --index-url https://download.pytorch.org/whl/cpu
        } else {
            Write-Host "· 下载 $pkg：$TorchIndex$name"
            & curl.exe -L --retry 8 -C - -o $path "$TorchIndex$name"
        }
    }
    Write-Host "· 安装 $tag torch"
    & $vpy -m pip install @wheels --index-url $Mirror --progress-bar off
}

Write-Host "· 安装 IndexTTS2（依赖链会偷偷装 CPU 版 torch，下面会纠正）"
& $vpy -m pip install "git+https://github.com/index-tts/index-tts.git" --index-url $Mirror --progress-bar off
if ($LASTEXITCODE -ne 0) {
    Write-Host "  git 安装失败，退回下载 zip 再装："
    $zip = Join-Path $WheelDir "indextts.zip"
    & curl.exe -L --max-time 300 -o $zip "https://codeload.github.com/index-tts/index-tts/zip/refs/heads/main"
    $repo = Join-Path $WheelDir "repo"
    Expand-Archive -Path $zip -DestinationPath $repo -Force
    $src = (Get-ChildItem $repo -Directory | Select-Object -First 1).FullName
    & $vpy -m pip install $src --index-url $Mirror --progress-bar off
}

if (-not $SkipTorch -and -not $Cpu -and $wheels.Count -gt 0) {
    Write-Host "· 纠正 torch：清掉被依赖装进来的 CPU 版 dist-info，再强装 cu128 轮子"
    Get-ChildItem (Join-Path $Venv "Lib\site-packages") -Filter "torch-*.dist-info" -Directory |
        Where-Object { $_.Name -notmatch $tag } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    & $vpy -m pip install --ignore-installed --no-deps @wheels --progress-bar off
}

Write-Host "· 自检"
& $vpy (Join-Path $here "py_probe.py") indextts 2>&1 | ForEach-Object { Write-Host "  $_" }

if (-not $SkipModel) {
    Write-Host "· 下载模型权重到 $ModelDir（ModelScope，实测 60 秒 3 GB）"
    & $vpy -m modelscope download --model IndexTeam/IndexTTS-2 --local_dir $ModelDir
}

Write-Host ""
Write-Host "== 完成 =="
Write-Host "起服务： powershell -ExecutionPolicy Bypass -File tools\start_tts.ps1"
Write-Host "自检：   curl http://127.0.0.1:8731/health"
