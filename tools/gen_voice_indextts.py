"""用本地 IndexTTS2 服务批量生成片段库（替代 edge-tts 版本）。

为什么是"批量"而不是"实时"：本机实测一整条许可 114~117 秒、短句也要 27~29 秒
（RTX 4060 Laptop 8GB，显存顶到 7.8/8.2 GB）。游戏里没法等，所以音色与情绪
在**生成时**定死，运行时仍然播预生成片段（零延迟、不占显存）。

片段清单与 manifest 格式与 tools/gen_voice.py 完全一致，
所以游戏侧（VoiceLibrary）不需要任何改动。

用法（先把服务起起来：tools\\start_tts.ps1）：
    python tools/gen_voice_indextts.py --role controller --emotion calm:0.65
    python tools/gen_voice_indextts.py --role pilot --emotion calm:0.6
"""

import argparse
import io
import json
import os
import re
import subprocess
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
VOICE_GD = os.path.join(PROJECT, "sim", "voice.gd")

# 每个角色/片段的默认情绪。放行席是职业无线电通话，以平静为主，
# 只在特定场合加一点别的味道（别演过头）。
ROLE_EMOTION = {
    "controller": {"calm": 0.70},
    "pilot": {"calm": 0.60},
}

# 特殊片段单独调情绪——这些是"有人味"的地方
PHRASE_EMOTION = {
    "p_say_again": {"surprised": 0.30, "calm": 0.35},
    "p_incomplete": {"angry": 0.15, "calm": 0.45},
    "p_readback_ok": {"happy": 0.12, "calm": 0.55},
    "p_wait": {"calm": 0.55},
}


def read_voice_gd():
    src = io.open(VOICE_GD, "r", encoding="utf-8").read()

    def block(header):
        i = src.find(header)
        if i < 0:
            return ""
        j = min(p for p in (src.find("{", i), src.find("[", i)) if p >= 0)
        close = "}" if src[j] == "{" else "]"
        k = src.find(close, j)
        return src[j:k + 1]

    digits = re.findall(r'"([^"]*)"', block("const DIGITS :="))
    phrases = dict(re.findall(r'"([A-Za-z0-9_]+)"\s*:\s*"([^"]*)"',
                              block("const FIXED_PHRASES :=")))
    airlines = re.findall(r'"([^"]*)"', block("const AIRLINES :="))
    names = dict(re.findall(r'"([A-Z]{3})"\s*:\s*"([^"]*)"',
                            block("const AIRLINE_TEXT :=")))
    types = dict(re.findall(r'"([A-Z0-9]+)"\s*:\s*"([^"]*)"',
                            block("const TYPE_TEXT :=")))
    sids = dict(re.findall(r'"([A-Za-z0-9_]+)"\s*:\s*"([^"]*)"',
                           block("const SID_TEXT :=")))
    dests = dict(re.findall(r'"([A-Za-z0-9_]+)"\s*:\s*"([^"]*)"',
                            block("const DEST_TEXT :=")))
    return digits, phrases, airlines, names, types, sids, dests


def pieces(digits, phrases, airlines, names, types, sids, dests):
    out = []
    for i, d in enumerate(digits):
        out.append(("d%d" % i, d))
    for pid in sorted(phrases.keys()):
        out.append((pid, phrases[pid]))
    for a in airlines:
        out.append(("ap_" + a, names.get(a, a)))
    for t in sorted(types.keys()):
        out.append(("t_" + t, types[t]))
    for sid in sorted(sids.keys()):
        out.append(("sid_" + sid, sids[sid]))
    for ap in sorted(dests.keys()):
        out.append(("dest_" + ap, dests[ap]))
    return out


def synth(base_url, text, role, emotion):
    payload = json.dumps({
        "text": text,
        "speaker": role,
        "emotion": emotion,
        "emo_alpha": 0.8,
    }, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(base_url.rstrip("/") + "/tts", data=payload,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as r:
        return r.read()


def to_ogg(wav_bytes, dst, radio_filter=True):
    tmp = dst + ".tmp.wav"
    with open(tmp, "wb") as f:
        f.write(wav_bytes)
    chain = []
    if radio_filter:
        # 轻一点的电台链路：神经 TTS 本身已经自然，滤波只负责"像无线电"
        chain.append("highpass=f=200:poles=2,lowpass=f=3400:poles=2,"
                     "acompressor=threshold=-20dB:ratio=4:attack=5:release=80,"
                     "volume=1.3,alimiter=limit=0.92")
    else:
        chain.append("loudnorm=I=-16:TP=-1.5")
    exe = os.environ.get("FFMPEG", "ffmpeg")
    subprocess.run([exe, "-y", "-loglevel", "error", "-i", tmp,
                    "-af", ",".join(chain), "-ar", "22050", "-ac", "1",
                    "-c:a", "libvorbis", "-q:a", "3", dst], check=True)
    os.remove(tmp)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8731")
    ap.add_argument("--role", default="controller")
    ap.add_argument("--out", default="")
    ap.add_argument("--emotion", default="", help="覆盖默认，如 calm:0.7,angry:0.1")
    ap.add_argument("--no-radio", action="store_true")
    ap.add_argument("--only", default="", help="只做指定 id（逗号分隔，调试用）")
    ap.add_argument("--resume", action="store_true", help="已存在的片段跳过")
    ap.add_argument("--manifest-only", action="store_true",
                    help="不合成，只按磁盘上已有的 .ogg 重建 manifest（修清单用）")
    args = ap.parse_args()

    out = args.out or os.path.join(PROJECT, "assets", "audio", "phrases", args.role)
    os.makedirs(out, exist_ok=True)

    base_emotion = dict(ROLE_EMOTION.get(args.role, {"calm": 0.6}))
    if args.emotion:
        base_emotion = {}
        for part in args.emotion.split(","):
            k, _, v = part.partition(":")
            if k:
                base_emotion[k.strip()] = float(v or 1.0)

    digits, phrases, airlines, names, types, sids, dests = read_voice_gd()
    items = pieces(digits, phrases, airlines, names, types, sids, dests)
    if args.only:
        keep = set(args.only.split(","))
        items = [it for it in items if it[0] in keep]

    # 清单**总是**先读出来再合并，不能只在 --resume 时读：
    # 否则 `--only t_B738` 这种补生成会把整份清单覆盖成只有 1–4 条
    # （真的发生过：补了 4 条机型片段，53 条的清单被写成 4 条）。
    manifest = {}
    mpath = os.path.join(out, "manifest.json")
    if os.path.exists(mpath):
        try:
            manifest = json.load(io.open(mpath, "r", encoding="utf-8"))
        except Exception:
            manifest = {}
    manifest.pop("_meta", None)

    # 只修清单：按片段表 + 磁盘上已有的 .ogg 重建，不合成、不联网
    if args.manifest_only:
        fixed = 0
        for pid, text in items:
            ogg = os.path.join(out, pid + ".ogg")
            if not os.path.exists(ogg) or os.path.getsize(ogg) < 512:
                continue
            manifest[pid] = {"file": pid + ".ogg", "text": text,
                             "sec": round(probe_seconds(ogg), 3),
                             "bytes": os.path.getsize(ogg),
                             "emotion": dict(PHRASE_EMOTION.get(pid, base_emotion))}
            fixed += 1
        manifest["_meta"] = {"engine": "indextts2", "role": args.role,
                             "emotion": base_emotion, "count": len(manifest),
                             "radio_filter": not args.no_radio}
        with open(mpath, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
        print("清单重建：%d 条 → %s" % (fixed, mpath))
        return 0

    total = len(items)
    t_all = time.time()
    for n, (pid, text) in enumerate(items, 1):
        ogg = os.path.join(out, pid + ".ogg")
        if args.resume and os.path.exists(ogg):
            print("  [%d/%d] %-16s 已存在，跳过" % (n, total, pid))
            continue
        emo = dict(PHRASE_EMOTION.get(pid, base_emotion))
        t0 = time.time()
        try:
            wav = synth(args.url, text, args.role, emo)
        except Exception as e:
            print("  [%d/%d] %-16s 失败：%s" % (n, total, pid, e))
            continue
        to_ogg(wav, ogg, not args.no_radio)
        dur = probe_seconds(ogg)
        manifest[pid] = {"file": pid + ".ogg", "text": text,
                         "sec": round(dur, 3), "bytes": os.path.getsize(ogg),
                         "emotion": emo}
        print("  [%d/%d] %-16s %-12s %5.1fs  %.2fs音频  %.0fs"
              % (n, total, pid, text[:12], time.time() - t0, dur, time.time() - t_all))
        with open(mpath, "w", encoding="utf-8") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)

    manifest["_meta"] = {"engine": "indextts2", "role": args.role,
                         "emotion": base_emotion, "count": len(manifest),
                         "radio_filter": not args.no_radio}
    with open(mpath, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
    print("")
    print("完成：%d 条 → %s（总耗时 %.0f 秒）"
          % (len(manifest) - 1, out, time.time() - t_all))
    return 0


def probe_seconds(path):
    exe = os.environ.get("FFPROBE", "ffprobe")
    try:
        return float(subprocess.run(
            [exe, "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nk=1:nw=1", path],
            check=True, capture_output=True, text=True).stdout.strip())
    except Exception:
        return 0.0


if __name__ == "__main__":
    sys.exit(main())
