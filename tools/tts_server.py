"""本地神经网络 TTS 服务（IndexTTS2 后端），给 Godot 提供 HTTP 接口。

为什么是"本地 HTTP 服务"：IndexTTS2 是 PyTorch 模型，Godot 里跑不了；
成熟做法就是把它包成一个本地服务，游戏用 HTTP 要 WAV 字节回来播
（AudioStreamWAV.from_data）。不走云端、不联网、不需要 key。

协议（都很简单，方便 Godot 侧只依赖 HTTPRequest）：
  GET  /health                     → {"ok":true,"backend":"indextts2","model_loaded":true,...}
  POST /tts   JSON                 → 音频字节（audio/wav）
       {"text":"许可放行至首都",
        "speaker":"controller"      # controller / pilot，对应两段参考音色
        "emotion":{"calm":0.6,"happy":0.1},   # 名字见 EMOTIONS，0..1
        "emo_alpha":0.8,            # 情绪强度
        "speed":1.0}
  POST /tts   也可以直接给 "emo_vector":[8 个数]

IndexTTS2 的情绪向量顺序（官方 README）：
  [happy, angry, sad, afraid, disgusted, melancholic, surprised, calm]

用法：
  # 没有模型也能先把游戏链路跑通（返回占位音）：
  python tools/tts_server.py --mock
  # 真模型（需要先按 tools/setup_indextts2.ps1 装好）：
  python tools/tts_server.py --model-dir D:\\models\\IndexTTS2
"""

import argparse
import io
import json
import math
import os
import struct
import sys
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# 官方的情绪维度顺序，不要改
EMOTIONS = ["happy", "angry", "sad", "afraid",
            "disgusted", "melancholic", "surprised", "calm"]

DEFAULT_PORT = 8731


def emotion_vector(named):
    """{"angry":0.7} → 8 维向量（按官方顺序）"""
    vec = [0.0] * len(EMOTIONS)
    if not isinstance(named, dict):
        return vec
    for k, v in named.items():
        key = str(k).strip().lower()
        if key not in EMOTIONS:
            continue
        try:
            f = float(v)
        except (TypeError, ValueError):
            continue
        vec[EMOTIONS.index(key)] = max(0.0, min(1.0, f))
    return vec


def wav_bytes(pcm: bytes, rate: int = 22050, channels: int = 1,
              width: int = 2) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(width)
        w.setframerate(rate)
        w.writeframes(pcm)
    return buf.getvalue()


def silence_wav(seconds: float = 0.35, rate: int = 22050) -> bytes:
    """占位音：一小段低音量正弦，用来验证链路通不通（不是人声）。"""
    n = int(rate * seconds)
    frames = bytearray()
    for i in range(n):
        v = int(1200 * math.sin(2 * math.pi * 220 * i / rate))
        frames += struct.pack("<h", v)
    return wav_bytes(bytes(frames), rate)


class IndexTts2Backend:
    """真模型后端。第一次请求时才加载，避免服务启动就吃掉显存。"""

    name = "indextts2"

    def __init__(self, model_dir, device="auto", fp16=True):
        self.model_dir = model_dir
        self.device = device
        self.fp16 = fp16
        self._tts = None
        self._lock = threading.Lock()

    def loaded(self):
        return self._tts is not None

    def _ensure(self):
        if self._tts is not None:
            return self._tts
        with self._lock:
            if self._tts is not None:
                return self._tts
            from indextts.infer_v2 import IndexTTS2
            cfg = os.path.join(self.model_dir, "config.yaml")
            use_cuda = self.device != "cpu"
            if self.device == "auto":
                try:
                    import torch
                    use_cuda = bool(torch.cuda.is_available())
                except Exception:
                    use_cuda = False
            self._tts = IndexTTS2(cfg_path=cfg, model_dir=self.model_dir,
                                  use_fp16=bool(self.fp16 and use_cuda),
                                  use_cuda_kernel=use_cuda,
                                  use_deepspeed=False)
            return self._tts

    def synth(self, text, speaker_wav, vec, alpha, speed=1.0):
        tts = self._ensure()
        out = io.BytesIO()
        tmp = os.path.join(os.environ.get("TEMP", "."), "atc_tts_out.wav")
        kwargs = dict(spk_audio_prompt=speaker_wav, text=text,
                      output_path=tmp, verbose=False)
        if any(v > 0 for v in vec):
            kwargs["emo_vector"] = vec
            kwargs["emo_alpha"] = max(0.0, min(1.0, alpha))
        if abs(speed - 1.0) > 0.01:
            kwargs["speed"] = speed
        tts.infer(**kwargs)
        with open(tmp, "rb") as f:
            out.write(f.read())
        try:
            os.remove(tmp)
        except OSError:
            pass
        return out.getvalue()


class MockBackend:
    """占位后端：不加载模型，返回一小段音。用于跑通游戏侧链路与自动化测试。"""

    name = "mock"

    def loaded(self):
        return True

    def synth(self, text, speaker_wav, vec, alpha, speed=1.0):
        # 按字数给时长，方便肉眼确认"请求确实到了"
        return silence_wav(min(2.0, 0.2 + 0.04 * len(text or "")))


class Handler(BaseHTTPRequestHandler):
    backend = None
    voices = {}

    def log_message(self, fmt, *args):  # 安静点，别刷屏
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/health"):
            self._json({"ok": True, "backend": self.backend.name,
                        "model_loaded": bool(self.backend.loaded()),
                        "emotions": EMOTIONS,
                        "voices": sorted(self.voices.keys())})
            return
        self._json({"ok": False, "error": "not found"}, 404)

    def do_POST(self):
        if not self.path.startswith("/tts"):
            self._json({"ok": False, "error": "not found"}, 404)
            return
        try:
            n = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(n) or b"{}")
        except Exception as e:
            self._json({"ok": False, "error": "bad json: %s" % e}, 400)
            return
        text = str(payload.get("text", "")).strip()
        if not text:
            self._json({"ok": False, "error": "text 为空"}, 400)
            return
        role = str(payload.get("speaker", "controller"))
        speaker_wav = self.voices.get(role) or self.voices.get("controller") or ""
        if payload.get("emo_vector"):
            try:
                vec = [float(x) for x in payload["emo_vector"]][:8]
                vec += [0.0] * (8 - len(vec))
            except Exception:
                vec = [0.0] * 8
        else:
            vec = emotion_vector(payload.get("emotion", {}))
        alpha = float(payload.get("emo_alpha", 1.0))
        speed = float(payload.get("speed", 1.0))
        t0 = time.time()
        try:
            data = self.backend.synth(text, speaker_wav, vec, alpha, speed)
        except Exception as e:
            self._json({"ok": False, "error": "合成失败: %s" % e}, 500)
            return
        self.send_response(200)
        self.send_header("Content-Type", "audio/wav")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("X-Synth-Ms", str(int((time.time() - t0) * 1000)))
        self.end_headers()
        self.wfile.write(data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=DEFAULT_PORT)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--mock", action="store_true", help="不加载模型，返回占位音")
    ap.add_argument("--model-dir", default=os.environ.get("INDEXTTS2_DIR", ""))
    ap.add_argument("--device", default="auto", choices=["auto", "cuda", "cpu"])
    ap.add_argument("--no-fp16", action="store_true")
    ap.add_argument("--voice-controller", default="")
    ap.add_argument("--voice-pilot", default="")
    args = ap.parse_args()

    if args.mock:
        Handler.backend = MockBackend()
    else:
        if not args.model_dir:
            print("缺少 --model-dir（或环境变量 INDEXTTS2_DIR）", file=sys.stderr)
            return 2
        Handler.backend = IndexTts2Backend(args.model_dir, args.device,
                                           not args.no_fp16)
    Handler.voices = {"controller": args.voice_controller,
                      "pilot": args.voice_pilot}

    srv = ThreadingHTTPServer((args.host, args.port), Handler)
    print("TTS 服务已启动 http://%s:%d  后端=%s  音色=%s"
          % (args.host, args.port, Handler.backend.name,
             {k: (os.path.basename(v) if v else "") for k, v in Handler.voices.items()}))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
