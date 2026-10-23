"""下载 IndexTTS-2 权重（供 setup_indextts2.ps1 调用）。

不要写成 PowerShell 的 `python -c "..."`：PS 5.1 遇到内联脚本里的括号会解析失败。
"""
import sys

from huggingface_hub import snapshot_download

target = sys.argv[1] if len(sys.argv) > 1 else r"D:\models\IndexTTS2"
path = snapshot_download(repo_id="IndexTeam/IndexTTS-2", local_dir=target)
print("MODEL_DIR=" + path)
