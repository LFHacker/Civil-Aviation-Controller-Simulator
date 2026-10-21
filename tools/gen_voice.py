"""生成语音片段库（08 §4 语音档「说」这一半）。

把 sim/voice.gd 里的短语表 + 数字 + 公司读法，逐条合成成小音频片段，
并写出 manifest.json。运行时游戏只按 Voice.compose() 的顺序播放这些片段，
不联网、不调 API、没有合成延迟。

用法（PowerShell，用 DSH 自带的 Python）：
    python tools/gen_voice.py                    # 默认 Edge 神经音色，输出到 assets/audio/phrases
    python tools/gen_voice.py --voice zh-CN-YunjianNeural
    python tools/gen_voice.py --no-radio         # 不加电台滤波，保留原始音色
    python tools/gen_voice.py --out D:\\tmp\\clips # 换个目录（试听/对比用）

⚠️ 音色来源可替换：核心是"片段 + 清单"，逻辑层只认 id。
   换成 Piper（本地、离线、开源）只需另写一个合成后端，manifest 格式不变。
"""

import argparse
import asyncio
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
VOICE_GD = os.path.join(PROJECT, "sim", "voice.gd")

# 电台链路：真塔台/机载电台是窄带（约 300~2700 Hz）+ 压限 + 底噪，
# 这一层既是"像真塔台"，也顺手抹掉了合成音色里的机械感。
RADIO_FILTER = (
    "highpass=f=320:poles=2,lowpass=f=2700:poles=2,"
    "acompressor=threshold=-20dB:ratio=5:attack=4:release=60,"
    "volume=2.4,alimiter=limit=0.9"
)

# 合成引擎会在句首句尾留大段静音（单个"洞"能到 1.4 s），
# 拼播放时会变成一顿一顿的空档 —— 必须先削掉。
# 真塔台里机组接话几乎不留缝，削干净反而更像。
TRIM_HEAD = "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.05"
TRIM_TAIL = "silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.12"


def tempo_for(pid):
    """按片段类别分别定语速。

    合成引擎念单个汉字也会补一段完整的音节包络（"幺"实测 0.64 s，
    提到 +45% 语速仍有 0.49 s）。而一条许可里有 13 个数字，
    照这个长度整句要 17 s，比真塔台的 11 s 慢出明显一截。
    atempo 变速不变调，所以数字段单独压到 1.35，其余保持自然。
    """
    if len(pid) == 2 and pid[0] == "d":
        return 1.35
    if pid.startswith("sid_") or pid.startswith("dest_"):
        return 1.05
    return 1.10


def parse_voice_gd(path):
    """从 voice.gd 抠出数字表、短语表、公司读法，避免两处维护同一份文本。"""
    src = io_read(path)
    digits = _first_list(src, "const DIGITS :=")
    phrases = dict(re.findall(r'"([A-Za-z0-9_]+)"\s*:\s*"([^"]*)"',
                              _block(src, "const FIXED_PHRASES :=")))
    airlines = _first_list(src, "const AIRLINES :=")
    names = dict(re.findall(r'"([A-Z]{3})"\s*:\s*"([^"]*)"',
                            _block(src, "const AIRLINE_TEXT :=")))
    sids = dict(re.findall(r'"([A-Za-z0-9_]+)"\s*:\s*"([^"]*)"',
                           _block(src, "const SID_TEXT :=")))
    dests = dict(re.findall(r'"([A-Za-z0-9_]+)"\s*:\s*"([^"]*)"',
                            _block(src, "const DEST_TEXT :=")))
    return digits, phrases, airlines, names, sids, dests


def _block(src, header):
    """取 header 之后第一个 {...} 或 [...] 的内容。"""
    i = src.find(header)
    if i < 0:
        return ""
    j = min([p for p in (src.find("{", i), src.find("[", i)) if p >= 0])
    close = "}" if src[j] == "{" else "]"
    k = src.find(close, j)
    return src[j:k + 1]


def _first_list(src, header):
    body = _block(src, header)
    return re.findall(r'"([^"]*)"', body)


def io_read(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def pieces(digits, phrases, airlines, names, sids, dests):
    """返回 [(片段 id, 要念的文本)]，顺序固定，便于比对。"""
    out = []
    for i, d in enumerate(digits):
        out.append(("d%d" % i, d))
    for pid in sorted(phrases.keys()):
        out.append((pid, phrases[pid]))
    for a in airlines:
        out.append(("ap_" + a, names.get(a, a)))
    for sid in sorted(sids.keys()):
        out.append(("sid_" + sid, sids[sid]))
    for ap in sorted(dests.keys()):
        out.append(("dest_" + ap, dests[ap]))
    return out


async def synth(text, voice, rate, out_mp3):
    import edge_tts
    com = edge_tts.Communicate(text, voice, rate=rate)
    await com.save(out_mp3)


def ffmpeg(*args):
    exe = os.environ.get("FFMPEG", "ffmpeg")
    subprocess.run([exe, "-y", "-loglevel", "error"] + list(args), check=True)


def to_ogg(src, dst, radio, tempo):
    # 先削头尾静音（areverse 两次实现"削尾"），再走电台链路。
    # 电台是窄带（≤2700 Hz），16 kHz 采样足够，24 kbps 也够，比默认小一半多。
    chain = [TRIM_HEAD, "areverse", TRIM_TAIL, "areverse"]
    if radio:
        chain.append(RADIO_FILTER)
    chain.append("atempo=%g" % tempo)   # 真塔台语速偏快
    chain.append("apad=pad_dur=0.03")
    args = ["-i", src, "-af", ",".join(chain),
            "-ar", "16000", "-ac", "1",
            "-c:a", "libvorbis", "-b:a", "32k", dst]
    ffmpeg(*args)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--voice", default="zh-CN-YunxiNeural")
    ap.add_argument("--rate", default="+8%")
    ap.add_argument("--out", default=os.path.join(PROJECT, "assets", "audio", "phrases"))
    ap.add_argument("--no-radio", action="store_true")
    ap.add_argument("--only", default="", help="只生成指定 id（调试用，逗号分隔）")
    args = ap.parse_args()

    digits, phrases, airlines, names, sids, dests = parse_voice_gd(VOICE_GD)
    if len(digits) != 10:
        print("✗ 数字表解析失败：%r" % digits)
        return 2
    if not phrases:
        print("✗ 短语表解析失败")
        return 2

    items = pieces(digits, phrases, airlines, names, sids, dests)
    if args.only:
        keep = set(args.only.split(","))
        items = [it for it in items if it[0] in keep]

    os.makedirs(args.out, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix="voiceseg_")
    manifest = {}
    total_bytes = 0
    total_sec = 0.0

    async def run():
        nonlocal total_bytes, total_sec
        for pid, text in items:
            mp3 = os.path.join(tmp, pid + ".mp3")
            ogg = os.path.join(args.out, pid + ".ogg")
            await synth(text, args.voice, args.rate, mp3)
            to_ogg(mp3, ogg, not args.no_radio, tempo_for(pid))
            size = os.path.getsize(ogg)
            dur = probe_seconds(ogg)
            total_bytes += size
            total_sec += dur
            manifest[pid] = {"file": pid + ".ogg", "text": text,
                             "sec": round(dur, 3), "bytes": size}
            print("  %-16s %-14s %5.2fs %6dB" % (pid, text, dur, size))

    asyncio.run(run())

    manifest["_meta"] = {"voice": args.voice, "rate": args.rate,
                         "radio": not args.no_radio, "count": len(items),
                         "bytes": total_bytes, "sec": round(total_sec, 2)}
    with open(os.path.join(args.out, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)

    print("")
    print("片段 %d 条，合计 %d s / %d KB → %s"
          % (len(items), round(total_sec), total_bytes // 1024, args.out))
    return 0


def probe_seconds(path):
    exe = os.environ.get("FFPROBE", "ffprobe")
    try:
        out = subprocess.run(
            [exe, "-v", "error", "-show_entries", "format=duration",
             "-of", "default=nk=1:nw=1", path],
            check=True, capture_output=True, text=True).stdout.strip()
        return float(out)
    except Exception:
        return 0.0


if __name__ == "__main__":
    sys.exit(main())
