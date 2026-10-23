# -*- coding: utf-8 -*-
"""把逻辑层 dump 出来的片段序列拼成一段试听音频（mp3），用来听"游戏里到底会播什么"。

为什么单独写这个：片段库是**离线产物、不入库**，用户/评审没法进游戏听之前先听一下；
而片段序列必须来自 `tools/dump_voice_plan.gd`（同一份逻辑层输出），不能手抄，
否则试听的和实际播的不是一回事。

用法：
    # 1) 先 dump 片段序列（逻辑层唯一的真相来源）
    Godot...exe --headless --path . --script res://tools/dump_voice_plan.gd
    #    把打印出的 VOICE_PLAN_JSON:{...} 存成 plan.json

    # 2) 拼成一段试听
    python tools/make_demo_audio.py --plan plan.json \
        --order pilot_request,controller_clearance,pilot_readback \
        --out docs/audio/indextts2-demo.mp3

角色分配：名字里带 controller / handoff 的走管制音色，其余走机组音色。
"""
import argparse
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile

PROJECT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PHRASES = os.path.join(PROJECT, "assets", "audio", "phrases")

CONTROLLER_KEYS = ("controller", "handoff")


def role_of(name):
    low = name.lower()
    for k in CONTROLLER_KEYS:
        if k in low:
            return "controller"
    return "pilot"


def ffmpeg_exe():
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    cand = os.path.join(PROJECT, "tools", "ffmpeg", "ffmpeg.exe")
    if os.path.exists(cand):
        return cand
    raise SystemExit("找不到 ffmpeg：请装到 PATH，或放到 tools/ffmpeg/ffmpeg.exe")


def run(args):
    p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if p.returncode != 0:
        sys.stderr.write(p.stderr.decode("utf-8", "replace")[-2000:])
        raise SystemExit("ffmpeg 失败：%s" % " ".join(args[:6]))


def seg_wav(ff, clips, role, out_wav, tmp):
    """一个片段序列 → 一个 wav（逐片段 concat demuxer）。"""
    listfile = os.path.join(tmp, "list.txt")
    with io.open(listfile, "w", encoding="utf-8") as f:
        for cid in clips:
            p = os.path.join(PHRASES, role, cid + ".ogg")
            if not os.path.exists(p):
                raise SystemExit("缺片段：%s（%s 音色）" % (cid, role))
            f.write("file '%s'\n" % p.replace("'", "'\\''"))
    run([ff, "-y", "-f", "concat", "-safe", "0", "-i", listfile,
         "-c:a", "pcm_s16le", "-ar", "24000", "-ac", "1", out_wav])


def silence_wav(ff, out_wav, seconds=0.45):
    run([ff, "-y", "-f", "lavfi", "-i",
         "anullsrc=r=24000:cl=mono", "-t", "%.2f" % seconds,
         "-c:a", "pcm_s16le", out_wav])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", required=True, help="dump_voice_plan.gd 输出的 JSON 文件")
    ap.add_argument("--order", default="pilot_request,controller_clearance,pilot_readback",
                    help="逗号分隔的段名，顺序就是播放顺序")
    ap.add_argument("--out", required=True, help="输出 mp3 路径")
    ap.add_argument("--gap", type=float, default=0.45, help="段间静音秒数")
    args = ap.parse_args()

    with io.open(args.plan, "r", encoding="utf-8-sig") as f:
        raw = f.read().strip()
    if raw.startswith("VOICE_PLAN_JSON:"):
        raw = raw[len("VOICE_PLAN_JSON:"):]
    plan = json.loads(raw)

    names = [n.strip() for n in args.order.split(",") if n.strip()]
    for n in names:
        if n not in plan:
            raise SystemExit("计划里没有这一段：%s（有：%s）" % (n, ", ".join(plan)))

    ff = ffmpeg_exe()
    tmp = tempfile.mkdtemp(prefix="atc_demo_")
    parts = []
    try:
        sil = os.path.join(tmp, "sil.wav")
        silence_wav(ff, sil, args.gap)
        for i, n in enumerate(names):
            w = os.path.join(tmp, "seg_%02d.wav" % i)
            seg_wav(ff, plan[n], role_of(n), w, tmp)
            parts.append(w)
            parts.append(sil)
        listfile = os.path.join(tmp, "all.txt")
        with io.open(listfile, "w", encoding="utf-8") as f:
            for p in parts:
                f.write("file '%s'\n" % p.replace("'", "'\\''"))
        out = os.path.abspath(args.out)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        run([ff, "-y", "-f", "concat", "-safe", "0", "-i", listfile,
             "-c:a", "libmp3lame", "-b:a", "96k", out])
        size = os.path.getsize(out)
        print("OK %s (%.1f KB)" % (out, size / 1024.0))
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
