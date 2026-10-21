# 发布脚本：按版本号做「只增不改」的分支与 tag
#
# 用法（PowerShell 5.1 执行策略禁止直接跑 .ps1，必须显式绕过）：
#   powershell -ExecutionPolicy Bypass -File tools\release.ps1
#   powershell -ExecutionPolicy Bypass -File tools\release.ps1 -DryRun
#
# 规则：
#   1. 版本号只有一个来源 —— core/version.gd 的 MAJOR/MINOR/PATCH
#   2. 每个版本都推一个独立分支 vX.Y.Z 和一个同名 annotated tag
#   3. 分支或 tag 已存在就**拒绝**，绝不用 -f 覆盖旧版本
#   4. 工作区必须干净，否则先提交
#   5. main 始终指向最新版本，历史版本从各自的 vX.Y.Z 分支取

param(
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Fail($msg) {
    Write-Host "[失败] $msg" -ForegroundColor Red
    exit 1
}

function Info($msg) {
    Write-Host $msg
}

# ---- 定位仓库根目录（脚本所在目录的上一级）----
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (-not (Test-Path ".git")) { Fail "当前目录不是 git 仓库：$root" }

    # ---- 1. 读版本号 ----
    $verFile = "core/version.gd"
    if (-not (Test-Path $verFile)) { Fail "找不到 $verFile" }
    $src = [IO.File]::ReadAllText((Resolve-Path $verFile), [Text.Encoding]::UTF8)

    $major = [regex]::Match($src, 'const\s+MAJOR\s*:=\s*(\d+)').Groups[1].Value
    $minor = [regex]::Match($src, 'const\s+MINOR\s*:=\s*(\d+)').Groups[1].Value
    $patch = [regex]::Match($src, 'const\s+PATCH\s*:=\s*(\d+)').Groups[1].Value
    if ($major -eq "" -or $minor -eq "" -or $patch -eq "") {
        Fail "无法从 $verFile 读出 MAJOR/MINOR/PATCH"
    }
    $ver = "$major.$minor.$patch"
    $ref = "v$ver"
    Info "版本：$ref"

    # ---- 2. 工作区必须干净 ----
    $dirty = git status --porcelain
    if ($dirty) {
        Info "工作区有未提交的改动："
        $dirty | ForEach-Object { Info "  $_" }
        Fail "请先提交，再发布（发布只搬运已提交的内容）"
    }

    # ---- 3. 分支/tag 不能已存在（核心规则：不覆盖旧版本）----
    $localBranch = git branch --list $ref
    if ($localBranch) { Fail "本地已存在分支 $ref —— 该版本已发布过，拒绝覆盖" }

    $remoteBranch = git ls-remote --heads origin "refs/heads/$ref"
    if ($remoteBranch) { Fail "远程已存在分支 $ref —— 该版本已发布过，拒绝覆盖" }

    $localTag = git tag --list $ref
    if ($localTag) { Fail "本地已存在 tag $ref —— 拒绝覆盖" }

    $remoteTag = git ls-remote --tags origin "refs/tags/$ref"
    if ($remoteTag) { Fail "远程已存在 tag $ref —— 拒绝覆盖" }

    if ($DryRun) {
        Info ""
        Info "试运行通过。真正执行时会："
        Info "  1) git push origin main"
        Info "  2) git branch $ref 并推送到 origin"
        Info "  3) git tag -a $ref 并推送"
        Info "  4) 切回 main"
        exit 0
    }

    # ---- 4. 先把 main 推上去（历史版本分支随后固定在这一版）----
    Info "推送 main ..."
    git push origin main
    if ($LASTEXITCODE -ne 0) { Fail "推送 main 失败" }

    # ---- 5. 建版本分支并推送（显式 refs/，避免与同名 tag 冲突）----
    Info "创建分支 $ref ..."
    git branch $ref
    if ($LASTEXITCODE -ne 0) { Fail "创建分支失败" }

    Info "推送分支 $ref ..."
    git push origin "refs/heads/$ref`:refs/heads/$ref"
    if ($LASTEXITCODE -ne 0) { Fail "推送分支失败" }

    # ---- 6. 打 annotated tag 并推送 ----
    Info "创建 tag $ref ..."
    git tag -a $ref -m "$ref —— 由 tools/release.ps1 生成"
    if ($LASTEXITCODE -ne 0) { Fail "创建 tag 失败" }

    Info "推送 tag $ref ..."
    git push origin "refs/tags/$ref`:refs/tags/$ref"
    if ($LASTEXITCODE -ne 0) { Fail "推送 tag 失败" }

    # ---- 7. 回到 main ----
    git checkout main | Out-Null

    Info ""
    Info "[完成] $ref 已固定。旧版本分支不会被改动。" -ForegroundColor Green
    Info "查看：https://github.com/LFHacker/Civil-Aviation-Controller-Simulator/branches"
}
finally {
    Pop-Location
}
