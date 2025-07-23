#+BEGIN_SRC python
#!/usr/bin/env python3
"""
neko_agent.py — Robust ShowUI-2B Neko WebRTC GUI agent.
Usage: Provide either --ws (already have token) OR --neko-url + --username + --password for REST login.
Env vars: NEKO_URL, NEKO_USER, NEKO_PASS, NEKO_WS, etc.
"""
import os, sys, asyncio, json, signal, logging, random, uuid, contextlib
from typing import Any, Dict, List, Optional, Tuple

import os
import torch
import websockets
from aiortc import (
    RTCConfiguration, RTCIceServer, RTCPeerConnection,
    RTCSessionDescription, RTCIceCandidate, VideoStreamTrack
)
from aiortc.rtcicetransport import candidate_from_sdp
from av import VideoFrame
from PIL import Image
from transformers import Qwen2VLForConditionalGeneration, AutoProcessor
from prometheus_client import start_http_server, Counter, Histogram

logging.getLogger("aiortc").setLevel(logging.DEBUG)

# ─── Configuration ─────────────────────────────────────────────────────────────
MODEL_KEY           = "showui-2b"
REPO_ID             = "showlab/ShowUI-2B"
SIZE_SHORTEST_EDGE  = 224
SIZE_LONGEST_EDGE   = 1344
DEFAULT_WS          = os.environ.get("NEKO_WS", "wss://neko.example.com/api/ws")
DEFAULT_METRIC_PORT = int(os.environ.get("NEKO_METRICS_PORT", 9000))
MAX_STEPS           = int(os.environ.get("NEKO_MAX_STEPS", 8))
AUDIO_DEFAULT       = bool(int(os.environ.get("NEKO_AUDIO", "1")))

ALLOWED_ACTIONS = {
    "CLICK","INPUT","SELECT","HOVER","ANSWER","ENTER","SCROLL","SELECT_TEXT","COPY",
    "SWIPE","TAP"
}
frames_received    = Counter("neko_frames_received_total",    "Total video frames received")
actions_executed   = Counter("neko_actions_executed_total",   "Actions executed by type", ["action_type"])
parse_errors       = Counter("neko_parse_errors_total",       "Action parse errors")
navigation_steps   = Counter("neko_navigation_steps_total",   "Navigation step count")
inference_latency  = Histogram("neko_inference_latency_seconds","Inference latency")
reconnects         = Counter("neko_reconnects_total",         "WS reconnect attempts")
resize_duration    = Histogram("neko_resize_duration_seconds","Resize time")

logger = logging.getLogger("neko_agent")
logging.basicConfig(
    level=os.environ.get("NEKO_LOGLEVEL","INFO"),
    format='{"ts":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}'
)

ACTION_SPACES = {
    "web":   ["CLICK","INPUT","SELECT","HOVER","ANSWER","ENTER","SCROLL","SELECT_TEXT","COPY"],
    "phone": ["INPUT","SWIPE","TAP","ANSWER","ENTER"],
}
ACTION_SPACE_DESC = {
    "web": """
1. CLICK: Click an element, value=None, position=[x, y].
2. INPUT: Type a string into an element, value=string, position=[x, y].
3. SELECT: Select a value for an element, value=None, position=[x, y].
4. HOVER: Hover on an element, value=None, position=[x, y].
5. ANSWER: Answer a question, value=string, position=None.
6. ENTER: Enter, value=None, position=None.
7. SCROLL: Scroll the screen, value=direction (e.g. "down"), position=None.
8. SELECT_TEXT: Select text, value=None, position=[[x1, y1], [x2, y2]].
9. COPY: Copy text, value=string, position=None.
""",
    "phone": """
1. INPUT: Type a string into an element, value=string, position=[x, y].
2. SWIPE: Swipe the screen, value=None, position=[[x1, y1], [x2, y2]].
3. TAP: Tap on an element, value=None, position=[x, y].
4. ANSWER: Answer a question, value=string, position=None.
5. ENTER: Enter, value=None, position=None.
"""
}
_NAV_SYSTEM = (
    "You are an assistant trained to navigate the {_APP} screen. "
    "Given a task instruction, a screen observation, and an action history sequence, "
    "output the next action and wait for the next observation. "
    "Here is the action space:\n{_ACTION_SPACE}\n"
    "Format the action as a dictionary with the following keys:\n"
    "{{'action': 'ACTION_TYPE', 'value': ..., 'position': ...}}\n"
    "If value or position is not applicable, set as None. "
    "Position might be [[x1,y1],[x2,y2]] for range actions. "
    "Do NOT output extra keys or commentary."
)
# ─── Utilities ────────────────────────────────────────────────────────────────
def safe_parse_action(output_text: str, nav_mode: str="web") -> Optional[Dict[str,Any]]:
    try:
        act = json.loads(output_text)
        assert isinstance(act, dict)
        typ = act.get("action")
        if typ not in ACTION_SPACES[nav_mode]:
            logger.warning("Security: Non-whitelisted action: %r", typ)
            parse_errors.inc()
            return None
        for k in ("action","value","position"):
            assert k in act, f"Missing key {k}"
        return act
    except (json.JSONDecodeError, AssertionError) as e:
        logger.error("Parse/schema error: %s | Raw: %r", e, output_text)
        parse_errors.inc()
        return None

def clamp_xy(x:int,y:int,size:Tuple[int,int]) -> Tuple[int,int]:
    w,h = size
    return max(0,min(x,w-1)), max(0,min(y,h-1))

def resize_and_validate_image(image:Image.Image) -> Image.Image:
    import time
    ow,oh = image.size
    me = max(ow,oh)
    if me > SIZE_LONGEST_EDGE:
        scale = SIZE_LONGEST_EDGE / me
        nw,nh = int(ow*scale), int(oh*scale)
        t0 = time.monotonic()
        image = image.resize((nw,nh), Image.LANCZOS)
        resize_duration.observe(time.monotonic()-t0)
        logger.info(f"Resized {ow}×{oh}→{nw}×{nh}")
    return image

def frame_to_pil_image(frame: "VideoFrame") -> Image.Image:
    """Convert an incoming aiortc ``VideoFrame`` to a Pillow ``Image``.

    The Go backend delivers RGB frames so we mirror its logic by converting the
    frame to an ``rgb24`` ndarray before constructing the ``Image``.  ``to_image``
    from ``pyav`` can implicitly handle this, but using ``to_ndarray`` matches the
    Go pipeline where frames are encoded in raw RGB bytes.
    """

    logger.info("Decoding frame to PIL image...")
    arr = frame.to_ndarray(format="rgb24")
    img = Image.fromarray(arr, "RGB")
    logger.info("Frame decoded successfully with size %s", img.size)
    return img

# ─── WebSocket / Signaling ────────────────────────────────────────────────────
class Signaler:
    def __init__(self, url:str):
        self.url = url
        self.ws: Optional[websockets.WebSocketClientProtocol] = None

    async def connect_with_backoff(self) -> websockets.WebSocketClientProtocol:
        backoff = 1
        while True:
            try:
                self.ws = await websockets.connect(self.url,
                                                   ping_interval=20,
                                                   ping_timeout=10,
                                                   max_queue=8)
                return self.ws
            except websockets.InvalidStatusCode as e:
                logger.error("WS auth/fatal error: %s", e)
                raise
            except Exception as e:
                delay = min(backoff*2,60)
                logger.error("WS connect error: %s — retry %ss", e, delay)
                await asyncio.sleep(delay + random.uniform(0,delay*0.1))
                backoff = delay

    async def send(self, msg:Dict[str,Any]) -> None:
        await self.ws.send(json.dumps(msg))

    async def recv(self, timeout:float=30) -> Dict[str,Any]:
        async with asyncio.timeout(timeout):
            data = await self.ws.recv()
        return json.loads(data)

class FrameSaver:
    """Continuously reads frames from a video track and keeps the latest image."""

    def __init__(self) -> None:
        self.image: Optional[Image.Image] = None
        self.task: Optional[asyncio.Task] = None
        self.lock = asyncio.Lock()
        self.first_frame = asyncio.Event()

    async def update(self, track: VideoStreamTrack) -> None:
        await self.stop()
        logger.info(f"FrameSaver: starting reader for track {track}")
        self.task = asyncio.create_task(self._reader(track))

    async def stop(self) -> None:
        if self.task:
            self.task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await self.task
            self.task = None
        async with self.lock:
            self.image = None

    async def _reader(self, track: VideoStreamTrack) -> None:
        try:
            while True:
                frame = await track.recv()
                img = frame_to_pil_image(frame)
                async with self.lock:
                    self.image = img
                frames_received.inc()
        except asyncio.CancelledError:
            pass
        except Exception as e:
            logger.error(f"Frame reader stopped: {e}")

    async def get(self) -> Optional[Image.Image]:
        async with self.lock:
            return self.image

class NekoAgent:
    def __init__(self, model, processor, ws_url:str,
                 nav_task:str, nav_mode:str,
                 max_steps:int=MAX_STEPS,
                 metrics_port:int=DEFAULT_METRIC_PORT,
                 audio:bool=AUDIO_DEFAULT):
        self.signaler   = Signaler(ws_url)
        self.frames     = FrameSaver()
        self.nav_task   = nav_task
        self.nav_mode   = nav_mode
        self.max_steps  = max_steps
        self.audio      = audio
        self.model      = model
        self.processor  = processor
        self.run_id     = os.environ.get("NEKO_RUN_ID") or str(uuid.uuid4())[:8]
        self.pc:Optional[RTCPeerConnection] = None
        self.shutdown   = asyncio.Event()
        self.loop       = asyncio.get_event_loop()
        self.ice_task   = None

        self.sys_prompt = _NAV_SYSTEM.format(
            _APP=self.nav_mode,
            _ACTION_SPACE=ACTION_SPACE_DESC[self.nav_mode]
        )
        start_http_server(metrics_port)

    async def run(self) -> None:
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, self.shutdown.set)
        while not self.shutdown.is_set():
            reconnects.inc()
            try:
                async with await self.signaler.connect_with_backoff() as ws:
                    self.signaler.ws = ws
                    await self._setup_webrtc()
                    self.ice_task = asyncio.create_task(self._consume_remote_ice())
                    try:
                        await self._main_loop()
                    finally:
                        self.ice_task.cancel()
                        with contextlib.suppress(asyncio.CancelledError):
                            await self.ice_task
            except Exception as e:
                logger.error(json.dumps({
                    "phase":"connect","run":self.run_id,"msg":f"WS/RTC error: {e}"
                }))
            finally:
                await self._cleanup()

    async def _setup_webrtc(self) -> None:
        # Send media request and wait for offer/provide which contains ICE servers
        req = {
            "video": {"width": 1280, "height": 720, "frameRate": 30}
        }
        if self.audio:
            req["audio"] = {}
        logger.info("Sending signal/request with payload: %r", req)
        await self.signaler.send({"event":"signal/request","payload":req})
        await self.signaler.send({"event": "session/watch", "payload": {"id": "main"}})

        offer_msg = None
        while True:
            msg = await self.signaler.recv()
            ev  = msg.get("event")
            if ev in ("signal/offer", "signal/provide"):
                offer_msg = msg
                break
            elif ev == "system/init":
                logger.info("Ignoring system/init, waiting for offer/provide with ICE servers.")
                continue

        payload = offer_msg.get("payload", offer_msg)

        # —————————————————————————
        # 1) Gather server-provided ICE servers
        ice_payload = (
            payload.get("ice")
            or payload.get("iceservers")
            or payload.get("iceServers")
            or payload.get("ice_servers")
            or []
        )
        logger.info("✅ Server ICE list: %r", ice_payload)

        # Build RTCIceServer instances from that list
        ice_servers = [
            RTCIceServer(
                urls      = srv.get("urls") or srv.get("url"),
                username  = srv.get("username"),
                credential= srv.get("credential")
            )
            for srv in ice_payload
        ]

        # —————————————————————————
        # 2) Merge in optional env-driven fallbacks
        #    (stun-only or TURN-TCP if provided)
        stun_url = os.environ.get(
            "NEKO_STUN_URL",
            "stun:stun.l.google.com:19302"
        )
        ice_servers.append(RTCIceServer(urls=[stun_url]))

        if os.environ.get("NEKO_TURN_URL"):
            ice_servers.append(RTCIceServer(
                urls      = [ os.environ["NEKO_TURN_URL"] +"?transport=tcp" ],
                username  = os.environ.get("NEKO_TURN_USER"),
                credential= os.environ.get("NEKO_TURN_PASS"),
            ))

        # —————————————————————————
        # 3) Build configuration for 'all' transports
        policy = os.environ.get("NEKO_ICE_POLICY","all")  # 'all' or 'relay'
        config = RTCConfiguration(
            iceServers         = ice_servers,
            iceTransportPolicy = policy
        )
        self.pc = RTCPeerConnection(config)

        # 4) Instrument ICE logging
        for ev in ("icegatheringstatechange",
                   "iceconnectionstatechange",
                   "connectionstatechange",
                   "signalingstatechange"):
            self.pc.on(ev, lambda e=ev: logger.info(f"{e} → {getattr(self.pc, e.replace('statechange','State'))}"))
        self.pc.on("icecandidate", lambda c: logger.debug("LOCAL ICE → %s", c))

        # --- LOG ALL RTC/ICE STATE CHANGES ---
        self.pc.on(
            "iceconnectionstatechange",
            lambda: logger.info(f"ICE connectionState → {self.pc.iceConnectionState}")
        )
        self.pc.on(
            "icegatheringstatechange",
            lambda: logger.info(f"ICE gatheringState → {self.pc.iceGatheringState}")
        )
        self.pc.on(
            "connectionstatechange",
            lambda: logger.info(f"PeerConnection state → {self.pc.connectionState}")
        )
        self.pc.on(
            "signalingstatechange",
            lambda: logger.info(f"Signaling state → {self.pc.signalingState}")
        )
        self.pc.on(
            "icecandidate",
            lambda c: logger.info(f"LOCAL ICE CANDIDATE → {c}")
        )
        self.pc.on("icecandidate", lambda c: asyncio.create_task(self._on_ice(c)))
        self.pc.on("track",       lambda t: asyncio.create_task(self._on_track(t)))

        await self.pc.setRemoteDescription(
            RTCSessionDescription(sdp=payload["sdp"], type=payload.get("type","offer"))
        )
        answer = await self.pc.createAnswer()
        await self.pc.setLocalDescription(answer)
        await self.signaler.send({
            "event":"signal/answer",
            "payload":{"sdp":self.pc.localDescription.sdp,"type":self.pc.localDescription.type}
        })

    async def _consume_remote_ice(self) -> None:
        while self.signaler.ws and not self.shutdown.is_set():
            try:
                msg = await self.signaler.recv(timeout=60)
            except asyncio.TimeoutError:
                continue
            if msg.get("event") == "signal/candidate":
                p    = msg["payload"]
                cand = p.get("candidate")
                if not cand or not self.pc:
                    continue

                # Optional: force only TCP candidates if UDP is blocked
                raw   = cand.split(":",1)[1] if cand.startswith("candidate:") else cand
                parsed= candidate_from_sdp(raw)
                if os.environ.get("NEKO_FORCE_TCP","0")=="1":
                    if parsed.protocol.lower()!="tcp":
                        logger.debug("Skipping non-TCP candidate: %s", parsed)
                        continue

                ice = RTCIceCandidate(
                    candidate     = cand,
                    sdpMid        = p.get("sdpMid"),
                    sdpMLineIndex = p.get("sdpMLineIndex"),
                )
                try:
                    await self.pc.addIceCandidate(ice)
                    logger.info("✅ Added ICE candidate (%s)", parsed.protocol)
                except Exception as e:
                    logger.warning("⚠️ addIceCandidate failed: %s", e)
            elif msg.get("event") == "signal/close":
                break

    async def _main_loop(self) -> None:
        history: List[Dict[str,Any]] = []
        step = 0
        while not self.shutdown.is_set() and step < self.max_steps:
            navigation_steps.inc()
            img = await self.frames.get()
            if img is None:
                await asyncio.sleep(0.01)
                continue
            img = resize_and_validate_image(img)
            act = await self._navigate_once(img, history, step)
            if not act or act.get("action") == "ANSWER":
                break
            history.append(act)
            step += 1
        logger.info(json.dumps({"phase":"complete","run":self.run_id,"steps":step}))

    async def _navigate_once(self, img:Image.Image, history:List[Dict[str,Any]], step:int) -> Optional[Dict[str,Any]]:
        content = [
            {"type":"text","text":self.sys_prompt},
            {"type":"text","text":f"Task: {self.nav_task}"},
        ]
        if history:
            content.append({"type":"text","text":f"Action history: {json.dumps(history)}"})
        content.append({"type":"image","image":img,
                        "size":{"shortest_edge":SIZE_SHORTEST_EDGE,"longest_edge":SIZE_LONGEST_EDGE}})
        msgs = [{"role":"user","content":content}]
        text   = self.processor.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True)
        inputs = self.processor(text=[text], images=[img], videos=None,
                                padding=True, return_tensors="pt").to(self.model.device)
        future = self.loop.run_in_executor(None, lambda: self.model.generate(**inputs, max_new_tokens=128))
        try:
            with inference_latency.time():
                gen = await asyncio.wait_for(future, timeout=30.0)
        except asyncio.TimeoutError:
            future.cancel()
            logger.error(json.dumps({"phase":"inference","run":self.run_id,"step":step,"msg":"timeout"}))
            parse_errors.inc()
            return None
        out_ids     = [o[len(i):] for o,i in zip(gen, inputs.input_ids)]
        raw_output  = self.processor.batch_decode(out_ids, skip_special_tokens=True, clean_up_tokenization_spaces=False)[0].strip()
        logger.info(json.dumps({"phase":"navigate","run":self.run_id,"step":step,"raw":raw_output}))
        act = safe_parse_action(raw_output, nav_mode=self.nav_mode)
        typ = act["action"] if act and act["action"] in ALLOWED_ACTIONS else "UNSUPPORTED"
        actions_executed.labels(action_type=typ).inc()
        logger.info(json.dumps({"phase":"navigate","run":self.run_id,"step":step,"action":act}))
        if act:
            await self._execute_action(act, img.size)
        return act

    async def _execute_action(self, action:Dict[str,Any], size:Tuple[int,int]) -> None:
        typ,val,pos = action.get("action"), action.get("value"), action.get("position")
        def xy(pt):
            x,y = int(pt[0]*size[0]), int(pt[1]*size[1])
            return clamp_xy(x,y,size)
        if typ in ("CLICK","TAP","SELECT","HOVER") and isinstance(pos,list) and len(pos)==2:
            x,y = xy(pos)
            await self.signaler.send({"event":"control/move","payload":{"x":x,"y":y}})
            if typ in ("CLICK","TAP"):
                await self.signaler.send({"event":"control/click","payload":{"button":"left","state":"down"}})
                await self.signaler.send({"event":"control/click","payload":{"button":"left","state":"up"}})
        elif typ=="INPUT" and val and isinstance(pos,list) and len(pos)==2:
            x,y = xy(pos)
            await self.signaler.send({"event":"control/move","payload":{"x":x,"y":y}})
            await self.signaler.send({"event":"control/click","payload":{"button":"left","state":"down"}})
            await self.signaler.send({"event":"control/click","payload":{"button":"left","state":"up"}})
            for ch in str(val):
                await self.signaler.send({"event":"control/key","payload":{"key":ch,"code":ord(ch),"state":"down"}})
                await self.signaler.send({"event":"control/key","payload":{"key":ch,"code":ord(ch),"state":"up"}})
        elif typ=="ENTER":
            for s in ({"key":"Enter","code":13,"state":"down"},{"key":"Enter","code":13,"state":"up"}):
                await self.signaler.send({"event":"control/key","payload":s})
        elif typ=="SCROLL" and val:
            await self.signaler.send({"event":"control/scroll","payload":{"direction":val}})
        elif typ=="SWIPE" and isinstance(pos,list) and len(pos)==2:
            (x1,y1),(x2,y2) = xy(pos[0]),xy(pos[1])
            await self.signaler.send({"event":"control/move","payload":{"x":x1,"y":y1}})
            await self.signaler.send({"event":"control/mouse","payload":{"button":"left","state":"down"}})
            await self.signaler.send({"event":"control/move","payload":{"x":x2,"y":y2}})
            await self.signaler.send({"event":"control/mouse","payload":{"button":"left","state":"up"}})
        elif typ=="SELECT_TEXT" and isinstance(pos,list) and len(pos)==2:
            (x1,y1),(x2,y2) = xy(pos[0]),xy(pos[1])
            await self.signaler.send({"event":"control/move","payload":{"x":x1,"y":y1}})
            await self.signaler.send({"event":"control/click","payload":{"button":"left","state":"down"}})
            await self.signaler.send({"event":"control/move","payload":{"x":x2,"y":y2}})
            await self.signaler.send({"event":"control/click","payload":{"button":"left","state":"up"}})
        elif typ=="COPY":
            logger.info("[COPY] to clipboard: %r", val)
            for k in (("Control",17),("c",67)):
                await self.signaler.send({"event":"control/key","payload":{"key":k[0],"code":k[1],"state":"down"}})
                await self.signaler.send({"event":"control/key","payload":{"key":k[0],"code":k[1],"state":"up"}})
        elif typ=="ANSWER":
            logger.info("[ANSWER] %r", val)
        else:
            logger.warning("Unsupported action: %r", action)

    async def _on_ice(self, cand):
        if not cand or not self.signaler.ws:
            return
        logger.info("SENDING local ICE candidate → %s", cand)
        await self.signaler.send({
            "event": "signal/candidate",
            "payload": {
                "candidate": cand.candidate,
                "sdpMid": cand.sdpMid,
                "sdpMLineIndex": cand.sdpMLineIndex
            }
        })

    async def _cleanup(self) -> None:
        if self.pc:
            await self.pc.close()
            for s in self.pc.getSenders():
                await s.track.stop()
            self.pc = None
        if self.signaler.ws:
            await self.signaler.ws.close()
        await self.frames.stop()

    async def _on_track(self, track):
        logger.info(f"RTC: Received track: kind={track.kind}, id={track.id}")
        if track.kind == "video":
            await self.frames.update(track)
        else:
            logger.info(f"RTC: Ignoring non-video track: kind={track.kind}")

# ─── Entrypoint ───────────────────────────────────────────────────────────────
async def main() -> None:
    import argparse
    p = argparse.ArgumentParser("neko_agent")
    p.add_argument("--ws",         default=os.environ.get("NEKO_WS",None),
                   help="WebSocket URL (wss://…?token=…); alternative to REST")
    p.add_argument("--task",       default=os.environ.get("NEKO_TASK","Search the weather"),
                   help="Navigation task")
    p.add_argument("--mode",       default=os.environ.get("NEKO_MODE","web"),
                   choices=list(ACTION_SPACES.keys()),
                   help="Navigation mode: web or phone")
    p.add_argument("--max-steps",  type=int, default=MAX_STEPS,
                   help="Max navigation steps per run")
    p.add_argument("--metrics-port",type=int,default=DEFAULT_METRIC_PORT,
                   help="Prometheus metrics port")
    p.add_argument("--loglevel",   default=os.environ.get("NEKO_LOGLEVEL","INFO"),
                   help="Logging level")
    p.add_argument("--no-audio",   dest="audio", action="store_false",
                   help="Disable audio stream")
    p.add_argument("--neko-url",   default=os.environ.get("NEKO_URL",None),
                   help="Base HTTP URL (https://host[:port]) for REST login")
    p.add_argument("--username",   default=os.environ.get("NEKO_USER",None),
                   help="REST login username")
    p.add_argument("--password",   default=os.environ.get("NEKO_PASS",None),
                   help="REST login password")
    p.set_defaults(audio=AUDIO_DEFAULT)
    args = p.parse_args()
    logging.getLogger().setLevel(args.loglevel.upper())

    logger.info(json.dumps({"phase":"setup","run":"startup","msg":"Loading model/processor"}))
    device,dtype = "cpu",torch.float32
    if torch.cuda.is_available():
        device,dtype = "cuda",torch.bfloat16
    elif torch.backends.mps.is_available():
        os.environ["PYTORCH_ENABLE_MPS_FALLBACK"]="1"
        try:
            _ = torch.zeros(1,dtype=torch.bfloat16,device="mps")
            dtype = torch.bfloat16
        except:
            dtype = torch.float32
        device="mps"
        offload_folder = os.environ.get("OFFLOAD_FOLDER", "./offload")
        os.makedirs(offload_folder, exist_ok=True)

        model = Qwen2VLForConditionalGeneration.from_pretrained(
            REPO_ID,
            torch_dtype=dtype,
            device_map="auto",
            offload_folder=offload_folder,    # ← where to spill weights
            offload_state_dict=True,          # ← offload the state_dict too
        ).eval()

        processor = AutoProcessor.from_pretrained(
            REPO_ID,
            size={"shortest_edge": SIZE_SHORTEST_EDGE, "longest_edge": SIZE_LONGEST_EDGE},
            trust_remote_code=True
        )

    ws_url = args.ws
    if not ws_url or ws_url==DEFAULT_WS:
        if not (args.neko_url and args.username and args.password):
            p.error("Need --ws or all of --neko-url, --username, --password")
        if any(a.startswith("--password") or a.startswith("--username") for a in sys.argv):
            print("[WARN] Use env vars for secrets.",file=sys.stderr)
        try:
            import requests
        except ImportError:
            print("ERROR: pip install requests",file=sys.stderr); sys.exit(1)
        login = args.neko_url.rstrip("/")+"/api/login"
        try:
            r = requests.post(login, json={"username":args.username,"password":args.password}, timeout=10)
            r.raise_for_status()
            tok = r.json().get("token")
            if not tok: raise RuntimeError("no token")
        except Exception as e:
            print(f"REST login failed: {e}",file=sys.stderr); sys.exit(1)
        host = args.neko_url.split("://",1)[-1].rstrip("/")
        scheme = "wss" if args.neko_url.startswith("https") else "ws"
        ws_url = f"{scheme}://{host}/api/ws?token={tok}"
        print(f"[INFO] REST login OK, WS={ws_url}",file=sys.stderr)
    elif any((args.neko_url,args.username,args.password)):
        print("[WARN] --ws provided, ignoring REST args",file=sys.stderr)

    agent = NekoAgent(
        model=model,
        processor=processor,
        ws_url=ws_url,
        nav_task=args.task,
        nav_mode=args.mode,
        max_steps=args.max_steps,
        metrics_port=args.metrics_port,
        audio=args.audio,
    )
    await agent.run()

if __name__ == "__main__":
    asyncio.run(main())
