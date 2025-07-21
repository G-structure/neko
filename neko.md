# Neko
## 1. What Neko Is (Concept & Origin)
Neko (often styled **n.eko**) is an open‑source, self‑hosted *virtual* browser / remote desktop environment: you run a containerized Linux desktop with a preinstalled browser (Firefox, Chromium, etc.) on your own infrastructure; Neko streams the interactive desktop (video, audio, input) to remote clients via WebRTC, so multiple participants can watch and even take control in real time.  [GitHub](https://github.com/m1k1o/neko) [neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction) [heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html)

The project was started by its author after the shutdown of Rabb.it; needing a reliable way to watch anime remotely with friends over limited bandwidth + unstable Discord streaming, he built a WebRTC‑based Dockerized environment so everyone could share a single browser session. This collaborative genesis still shapes Neko’s multi‑user design (shared control queue, watch‑party friendliness).  [oai_citation:19‡GitHub](https://github.com/m1k1o/neko) [oai_citation:20‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html)

Neko targets privacy, isolation, and portability: browsing happens in the container, not on the viewer’s device; host fingerprints/cookies stay server‑side; nothing persistent need touch the client unless you configure it. This “shielded browser” model is highlighted in both the docs and independent coverage (Heise), which also frames Neko as a lightweight VPN alternative for accessing internal resources without distributing full desktop access.  [oai_citation:21‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction) [oai_citation:22‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html) [oai_citation:23‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/)

## 2. Primary Use Cases
- **Collaborative browsing & watch parties:** All participants see the same live browser; host control can be passed; synchronized media playback works well because WebRTC streams the rendered video/audio from the container.  [oai_citation:24‡GitHub](https://github.com/m1k1o/neko) [oai_citation:25‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction) [oai_citation:26‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/)
- **Interactive presentations, workshops, remote support:** Presenter drives a shared browser/desktop; participants can be granted temporary control for demos or troubleshooting. Heise specifically calls out company trainings and support scenarios.  [oai_citation:27‡GitHub](https://github.com/m1k1o/neko) [oai_citation:28‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html) [oai_citation:29‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/)
- **Privacy / throwaway browsing / firewall bypass:** Because traffic originates from the Neko host, users can browse sites blocked locally (subject to policy/ethics); community reports note using Neko to get around locked‑down work networks.  [oai_citation:30‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html) [oai_citation:31‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/) [oai_citation:32‡Reddit](https://www.reddit.com/r/selfhosted/comments/1ffz78l/neko_selfhosted_browser/)
- **Web dev & cross‑browser testing in controlled envs:** Spin up specific browser versions (incl. Waterfox, Tor, Chromium variants) to test sites without polluting local machines.  [oai_citation:33‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction) [oai_citation:34‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/installation/docker-images) [oai_citation:35‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html)
- **Remote application streaming beyond browsers:** Official images include full desktop environments (KDE, Xfce), Remmina (RDP/VNC client), VLC, and more; you can install arbitrary Linux GUI apps, turning Neko into a general remote app delivery layer.  [oai_citation:36‡GitHub](https://github.com/m1k1o/neko) [oai_citation:37‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/installation/docker-images) [oai_citation:38‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html)
- **Embedding into other web properties / programmatic rooms:** Docs and community guides show URL query param auth for frictionless embedding; REST API + Neko Rooms enable dynamic, ephemeral shareable sessions.  [oai_citation:39‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq) [oai_citation:40‡GitHub](https://github.com/m1k1o/neko/releases) [oai_citation:41‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/)
## 3. High‑Level Architecture
At a high level, a Neko deployment comprises:
- **Server container(s):** Run the Linux desktop + target browser/application; capture Xorg display frames + PulseAudio; encode via GStreamer; feed into WebRTC pipeline (Pion stack).  [oai_citation:42‡GitHub](https://github.com/m1k1o/neko) [oai_citation:43‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:44‡GitHub](https://github.com/m1k1o/neko/releases)
- **Signaling / control plane:** HTTP + WebSocket endpoints manage sessions, auth, and host‑control; periodic ping/heartbeat maintain liveness (esp. behind proxies).  [oai_citation:45‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:46‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:47‡GitHub](https://github.com/m1k1o/neko/releases)
- **WebRTC media plane:** ICE negotiation (STUN/TURN) to establish peer link(s); selectable port strategy (ephemeral range vs. UDP/TCP mux single port); optional Coturn relay for NAT‑restricted environments.  [oai_citation:48‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:49‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:50‡GitHub](https://github.com/m1k1o/neko)
- **Client UI (served over HTTPS):** Browser front‑end page that renders the stream in a canvas/video element, sends input events (mouse/keyboard), displays participant cursors, chat/plugins, and exposes host‑control queue.  [oai_citation:51‡GitHub](https://github.com/m1k1o/neko) [oai_citation:52‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction) [oai_citation:53‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)
- **Optional ecosystem services:** REST API, Prometheus metrics exporter, plugin hooks (chat, file upload), and higher‑level orchestration projects (Neko Rooms / Apps / VPN).  [oai_citation:54‡GitHub](https://github.com/m1k1o/neko/releases) [oai_citation:55‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:56‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction)
## 4. Feature Inventory (v3 era)
- **Multi‑user concurrent session w/ host handoff + inactive cursors:** Participants can join; privileges (watch / host / share media / clipboard) governed per‑member profile.  [oai_citation:57‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:58‡GitHub](https://github.com/m1k1o/neko) [oai_citation:59‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction)
- **Audio + video streaming w/ low latency:** WebRTC transport from container to clients; GStreamer capture; optional simulcast & stream selector to adjust quality.  [oai_citation:60‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:61‡GitHub](https://github.com/m1k1o/neko/releases) [oai_citation:62‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction)
- **GPU acceleration modes (Intel/Nvidia flavors) & CPU builds:** Select appropriate image flavor to offload encoding & improve responsiveness; GPU support maturity varies—docs caution focus currently on CPU images.  [oai_citation:63‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/installation/docker-images) [oai_citation:64‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html) [oai_citation:65‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction)
- **Granular auth/authorization (admin vs user; fine‑grained caps):** Role bits include can_login, can_connect, can_watch, can_host, can_share_media, can_access_clipboard, etc.; supports multiuser password split, file‑backed users, in‑memory object sets, and no‑auth (dev only).  [oai_citation:66‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:67‡GitHub](https://github.com/m1k1o/neko/releases)
- **REST API + API token (admin programmatic control) & batch HTTP:** Added in v3; enables external orchestration, dynamic user provisioning, and admin operations without interactive login; API token should be short‑lived in ephemeral rooms.  [oai_citation:68‡GitHub](https://github.com/m1k1o/neko/releases) [oai_citation:69‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication)
- **Prometheus metrics & pprof profiling:** Expose runtime health / performance metrics; integrate into observability stacks; profiling hooks assist tuning.  [oai_citation:70‡GitHub](https://github.com/m1k1o/neko/releases) [oai_citation:71‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)
- **Desktop quality‑of‑life:** Clipboard reworked via xclip; drag‑and‑drop & file chooser upload; touchscreen input driver; dynamic resolution via xrandr; cursor image events.  [oai_citation:72‡GitHub](https://github.com/m1k1o/neko/releases) [oai_citation:73‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)
- **Capture fallback + webcam/mic passthrough (experimental):** Screencast fallback path when WebRTC capture problematic; optional user media upstream.  [oai_citation:74‡GitHub](https://github.com/m1k1o/neko/releases) [oai_citation:75‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)
- **Plugin system (chat, file upload, user‑scoped plugin config map).**  [oai_citation:76‡GitHub](https://github.com/m1k1o/neko/releases) [oai_citation:77‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:78‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)
## 5. Supported Browsers / Apps / Desktops
Neko ships many tagged images; availability varies by architecture and GPU flavor. Current matrix (AMD64 strongest support): Firefox, Waterfox, Tor Browser; Chromium family incl. Google Chrome, Microsoft Edge, Brave, Vivaldi, Opera; plus Ungoogled Chromium. Additional desktop/media apps: KDE, Xfce, Remmina, VLC. ARM support exists for subsets (e.g., Brave & Vivaldi on ARM64; some lack DRM).  [oai_citation:79‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/installation/docker-images) [oai_citation:80‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html) [oai_citation:81‡GitHub](https://github.com/m1k1o/neko/releases)

Community packages (Umbrel) surface a streamlined install for home servers; Umbrel metadata shows current packaged version (3.0.4 at capture) and highlights collaboration + tunneling access patterns.  [oai_citation:82‡apps.umbrel.com](https://apps.umbrel.com/app/neko) [oai_citation:83‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/installation/docker-images)
## 6. Deployment Overview (Minimal to Advanced)
### 6.1 Quick Minimal Docker Run
Pull an image (e.g., Firefox flavor) and run mapping HTTP + WebRTC ports; provide screen size and user/admin passwords via env vars; share memory sized for modern browsers (e.g., 2GB). Community example docker‑compose (FOSS Engineer) shows mapping `8888:8080` plus `52000-52100/udp` EPR range and `NEKO_MEMBER_MULTIUSER_*` passwords.  [oai_citation:84‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/) [oai_citation:85‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:86‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)
### 6.2 Choosing Registry & Tags
Prefer GitHub Container Registry (GHCR) for stable, flavor‑specific version tags; Docker Hub hosts latest dev (amd64) convenience builds. Semantic versioning (MAJOR.MINOR.PATCH) supported; `latest` for most recent stable—pin explicit tags for reproducibility.  [oai_citation:87‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/installation/docker-images) [oai_citation:88‡Docker Hub](https://hub.docker.com/r/m1k1o/neko)
### 6.3 Selecting Flavors (CPU vs GPU)
Image suffix selects hardware accel stack: `nvidia-*` for CUDA GPUs (AMD64), `intel-*` for VA‑API/QuickSync paths, or base CPU images. Docs caution GPU support may lag; verify in your environment.  [oai_citation:89‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/installation/docker-images) [oai_citation:90‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html)
### 6.4 Architecture Match & Resource Planning
Images published for linux/amd64, arm64, arm/v7; not every browser builds on all arches; some Chromium‑derived variants require ≥2GB RAM (Heise). Check the docs availability matrix before pulling.  [oai_citation:91‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/installation/docker-images) [oai_citation:92‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html)
### 6.5 Persistent State (Data Volumes)
While Neko can be run “throwaway,” you may bind‑mount config, member files, and persistent browser profiles to retain bookmarks, extensions (if policy permits), and user lists; docs show file/member providers referencing host paths (e.g., `/opt/neko/members.json`).  [oai_citation:93‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:94‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq) [oai_citation:95‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/installation/docker-images)
## 7. Networking & WebRTC Ports
### 7.1 Why Ports Matter
WebRTC media does **not** traverse your HTTP reverse proxy; you must expose the negotiated media ports (or provide a TURN relay). If you only open 443 you will fail unless multiplexing or relay is used.  [oai_citation:96‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:97‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:98‡Reddit](https://www.reddit.com/r/nginxproxymanager/comments/ut8zyu/help_with_setting_up_reverse_proxy_custom_headers/)
### 7.2 Ephemeral UDP Port Range (EPR)
Configure `NEKO_WEBRTC_EPR` (e.g., `59000-59100`) and expose identical host:container UDP range; don’t remap—ICE candidates must match reachable ports.  [oai_citation:99‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)
### 7.3 UDP/TCP Multiplexing
Alternatively specify single `udpmux` / `tcpmux` ports when firewall pinholes are scarce; open both protocols for fallback where UDP blocked.  [oai_citation:100‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)
### 7.4 Public vs NAT’d IPs
Set `nat1to1` when advertising a different reachable address (NAT hairpin caveats); or provide an IP retrieval URL to auto‑detect public address; otherwise ICE may hand out unroutable candidates.  [oai_citation:101‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)
### 7.5 TURN Integration
Provide STUN/TURN server JSON (frontend/back‑end separation) via env vars; example Coturn compose snippet in docs; TURN recommended when clients sit behind strict NAT/firewalls.  [oai_citation:102‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:103‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction)
### 7.6 Real‑World Gotchas
Community reverse‑proxy thread shows mis‑set X‑Forwarded headers and missing additional port exposures leading to 502s; verifying correct WebRTC ports resolved issues for some users.  [oai_citation:104‡Reddit](https://www.reddit.com/r/nginxproxymanager/comments/ut8zyu/help_with_setting_up_reverse_proxy_custom_headers/) [oai_citation:105‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)
## 8. Reverse Proxy Patterns (HTTP Plane)
### 8.1 Enable Proxy Trust
Set `server.proxy=true` so Neko honors `X-Forwarded-*` headers (important for logging, CSRF, cookie domain/path). Docs warn to adjust WebSocket timeouts because Neko pings every ~10s and expects client heartbeat ~120s.  [oai_citation:106‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:107‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)
### 8.2 Traefik v2 Example
Label‑driven routing to backend `8080`; integrate TLS cert resolver; ensure UDP media ports separately exposed.  [oai_citation:108‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:109‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)
### 8.3 Nginx Example & Header Hygiene
Minimal conf proxies HTTP + WebSocket upgrade; you may add X‑Forwarded‑For/Proto, cache bypass, and long read timeouts—legacy v2 docs show extended header set; community notes correcting `X-Forwarded-Proto` spelling vs “Protocol.”  [oai_citation:110‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:111‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v2/reverse-proxy) [oai_citation:112‡Reddit](https://www.reddit.com/r/nginxproxymanager/comments/ut8zyu/help_with_setting_up_reverse_proxy_custom_headers/)
### 8.4 Apache, Caddy, HAProxy Templates
Docs provide working snippets incl. WebSocket rewrite for Apache; one‑liner `reverse_proxy` for Caddy w/ auto HTTPS; HAProxy ACL routing recipe w/ timeout tuning guidance.  [oai_citation:113‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:114‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v2/reverse-proxy)
## 9. Authentication & Authorization
### 9.1 Member vs Session Providers
Auth split: *Member Provider* validates credentials + returns capability profile; *Session Provider* persists session state (memory/file). Single member provider active at a time.  [oai_citation:115‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication)
### 9.2 Capability Flags (Granular Rights)
Per‑user profile booleans drive UI & backend enforcement: admin status; login/API; connect vs watch; host control; share media; clipboard access; send inactive cursor; see inactive cursors; plugin‑specific keys.  [oai_citation:116‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:117‡GitHub](https://github.com/m1k1o/neko/releases)
### 9.3 Provider Types
- **Multiuser:** Two shared passwords (admin/user) generate ephemeral usernames; mirrors legacy v2 behavior.
- **File:** Persistent JSON map of users → hashed (optional) passwords + profiles.
- **Object:** In‑memory static list; no dup logins.
- **No‑Auth:** Open guest access (testing only—danger).  [oai_citation:118‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication)
### 9.4 API User Token
Separate non‑interactive admin identity for HTTP API calls; cannot join media; recommend ephemeral/rotated tokens (avoid long‑lived static in exposed rooms).  [oai_citation:119‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:120‡GitHub](https://github.com/m1k1o/neko/releases)
### 9.5 Cookie Controls
Session cookie name, expiry, secure, httpOnly, domain/path configurable; disabling cookies falls back to token in client local storage—less secure (XSS risk). Keep cookies enabled for production.  [oai_citation:121‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication)
## 10. Security Considerations
-  **Surface reduction via containerization:** Browsing occurs inside an isolated container; you can discard state or run read‑only images for throwaway sessions; community privacy guides emphasize non‑retention setups.  [oai_citation:122‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/) [oai_citation:123‡GitHub](https://github.com/m1k1o/neko)
- **Transport security & certs:** Terminate TLS at your reverse proxy (Traefik/Caddy/Certbot etc.); ensure WebSocket upgrades & long timeouts; see official reverse proxy examples.  [oai_citation:124‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:125‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v2/reverse-proxy)
- **Auth hardening:** Use strong unique admin/user passwords (or file/object providers w/ hashed credentials); avoid enabling no‑auth in public deployments; scope API tokens tightly.  [oai_citation:126‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:127‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)
- **Cookie vs token leakage:** Leaving cookies enabled (secure, httpOnly) prevents script access to session; disabling pushes token into JS‑accessible storage increasing exfiltration risk.  [oai_citation:128‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication)
- **Firewalling media ports:** Only expose required UDP/TCP ranges; where possible, restrict source IPs or require authenticated TURN; community reports of leaving ports closed manifest as connection failures rather than leaks—but mis‑config can open broad EPR ranges; plan network policy.  [oai_citation:129‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:130‡Reddit](https://www.reddit.com/r/nginxproxymanager/comments/ut8zyu/help_with_setting_up_reverse_proxy_custom_headers/)
- **Extension install policy:** Browser policies in images may block arbitrary extension installs; you must explicitly allow if you need them—reduces attack surface by default.  [oai_citation:131‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq) [oai_citation:132‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/installation/docker-images)
## 11. Performance & Tuning
- **Screen resolution & frame rate:** `NEKO_DESKTOP_SCREEN` / `NEKO_SCREEN` env controls virtual display mode (e.g., 1920x1080@30); higher rates = more bandwidth/CPU/GPU; choose based on clients & uplink.  [oai_citation:133‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/) [oai_citation:134‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)
- **Shared memory size:** Modern Chromium‑family browsers need large `/dev/shm`; examples allocate `shm_size: 2gb`; undersizing leads to crashes.  [oai_citation:135‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/) [oai_citation:136‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)
- **Bandwidth estimator (experimental adaptive bitrate):** Optional server‑side estimator can downgrade/upgrade encodes based on measured throughput; disabled by default; numerous thresholds/backoffs tunable.  [oai_citation:137‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:138‡GitHub](https://github.com/m1k1o/neko/releases)
- **Hardware accel vs CPU encode tradeoffs:** GPU flavors reduce encode latency but add driver complexity; docs call out limited support maturity; Heise notes Neko can leverage Intel/Nvidia accelerated builds.  [oai_citation:139‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/installation/docker-images) [oai_citation:140‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html)
- **Resource guidance for Chromium variants:** Heise reports ≥2GB RAM allocation recommended when running Chromium‑based browsers in containers; plan host sizing accordingly.  [oai_citation:141‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html) [oai_citation:142‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/installation/docker-images)
## 12. Administration & Operations
- **Logging & Debugging:** Enable debug logging via `log.level=debug` or env `NEKO_DEBUG=1`; GStreamer verbosity via `GST_DEBUG`; Pion debug by `PION_LOG_DEBUG=all`; inspect docker logs and browser dev console.  [oai_citation:143‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq) [oai_citation:144‡GitHub](https://github.com/m1k1o/neko/releases)
- **Metrics & Profiling:** Prometheus metrics endpoint + pprof instrumentation introduced in v3 support operational monitoring and performance investigation.  [oai_citation:145‡GitHub](https://github.com/m1k1o/neko/releases) [oai_citation:146‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)
- **Upgrades / Migration from v2:** Config modularization in v3; backward compatibility shims but deprecated; consult v3 docs + legacy reverse proxy header diffs when migrating.  [oai_citation:147‡GitHub](https://github.com/m1k1o/neko/releases) [oai_citation:148‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v2/reverse-proxy) [oai_citation:149‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup)
- **Embedding Auto‑Login:** For kiosk/iframe use, append `?usr=<user>&pwd=<pwd>` to URL to bypass login prompt for viewers—use carefully; combine w/ restricted capability profile.  [oai_citation:150‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq) [oai_citation:151‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication)
- **Clipboard Behavior:** When accessed over HTTPS in supported host browsers (Chromium family), Neko hides its own clipboard button, deferring to native Clipboard API integration; not a bug.  [oai_citation:152‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq) [oai_citation:153‡GitHub](https://github.com/m1k1o/neko/releases)
## 13. Ecosystem Projects
- **Neko Rooms:** Multi‑room orchestration wrapper that spins up independent Neko instances (ephemeral or persistent) with simplified onboarding (scripts, HTTPS via Let’s Encrypt, Traefik/NGINX automation); useful when you need per‑group isolation.  [oai_citation:154‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:155‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/) [oai_citation:156‡Reddit](https://www.reddit.com/r/selfhosted/comments/1ffz78l/neko_selfhosted_browser/)
- **Neko Apps:** Library of containerized app bundles beyond browsers—expands use cases to general remote Linux app streaming; complements Rooms for scaling out multi‑app catalogs.  [oai_citation:157‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/) [oai_citation:158‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction)
- **Neko VPN (experimental):** Mentioned in docs nav as companion project enabling tunneled access paths; explore if you need integrated network overlay to reach internal apps through Neko.  [oai_citation:159‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction) [oai_citation:160‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup)
- **Umbrel Packaging:** Curated home‑server integration; one‑click install, Umbrel tunneling for remote reachability, version tracking; good for homelab / non‑Docker‑experts.  [oai_citation:161‡apps.umbrel.com](https://apps.umbrel.com/app/neko) [oai_citation:162‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction)
## 14. Comparison Touchpoints
- **vs. Kasm Workspaces:** Heise positions Neko as the lightweight alternative—Kasm provides full multi‑tenant workspace management & security layers but is heavier; Neko is simpler, container‑first, optimized for *shared* live sessions rather than individual isolated desktops (though you can run per‑user instances).  [oai_citation:163‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html) [oai_citation:164‡GitHub](https://github.com/m1k1o/neko)
- **vs. Hyperbeam API (hosted embeddable co‑browse):** Neko offers a similar embeddable shared browser experience but is self‑hosted, giving you data control & on‑prem compliance; Heise explicitly calls out analogous embedding.  [oai_citation:165‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html) [oai_citation:166‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)
- **vs. Generic Remote Desktop (VNC/NoVNC/Guacamole):** WebRTC yields smoother video + audio sync and lower interactive latency compared to image‑diff or poll‑based remotes; community commentary and docs emphasize superior streaming for media/watch usage.  [oai_citation:167‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/) [oai_citation:168‡GitHub](https://github.com/m1k1o/neko)
## 15. Practical Config Snippets
```yaml
version: "3.4"
services:
neko:
  image: "ghcr.io/m1k1o/neko/firefox:latest"   # pick flavor/tag
  restart: unless-stopped
  shm_size: 2gb
  ports:
    - "8080:8080"                       # HTTP / signaling
    - "59000-59100:59000-59100/udp"     # WebRTC EPR
  environment:
    NEKO_DESKTOP_SCREEN: 1920x1080@30
    NEKO_MEMBER_MULTIUSER_ADMIN_PASSWORD: ${NEKO_ADMIN:?err}
    NEKO_MEMBER_MULTIUSER_USER_PASSWORD: ${NEKO_USER:?err}
    NEKO_WEBRTC_EPR: 59000-59100
    NEKO_WEBRTC_ICELITE: 1
    NEKO_DEBUG: 0
    # optionally front/back STUN/TURN JSON:
    # NEKO_WEBRTC_ICESERVERS_FRONTEND: '[{"urls":["stun:stun.l.google.com:19302"]}]'
    # NEKO_WEBRTC_ICESERVERS_BACKEND:  '[]'
volumes:
# mount for persistent member/session files if using file provider
# - ./data:/opt/neko
```
[oai_citation:169‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/) [oai_citation:170‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:171‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)

```nginx
server {
listen 443 ssl http2;
server_name neko.example.com;

location / {
  proxy_pass http://127.0.0.1:8080;
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "upgrade";
  proxy_set_header Host $host;
  proxy_set_header X-Real-IP $remote_addr;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_cache_bypass $http_upgrade;
}
}
```
[oai_citation:172‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:173‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v2/reverse-proxy) [oai_citation:174‡Reddit](https://www.reddit.com/r/nginxproxymanager/comments/ut8zyu/help_with_setting_up_reverse_proxy_custom_headers/)

```yaml
# Minimal member provider switch to file‑backed users with hashed passwords
member:
provider: file
file:
  path: "/opt/neko/members.json"
  hash: true
session:
file: "/opt/neko/sessions.json"
session:
api_token: "<short-lived-random-hex>"
```
[oai_citation:175‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:176‡GitHub](https://github.com/m1k1o/neko/releases)
## 16. Operational Runbook Checklist
- **Preflight:** Pick image flavor + arch; allocate ≥2GB RAM (Chromium); set shm_size; open media ports (EPR or mux); decide auth provider; create strong creds.  [oai_citation:177‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/installation/docker-images) [oai_citation:178‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html) [oai_citation:179‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication)
- **Launch:** Compose up; confirm logs show listening on 8080 + WebRTC ports; test LAN client first; verify ICE candidates reachable (browser dev console).  [oai_citation:180‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:181‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)
- **Secure:** Put behind TLS proxy; enable proxy trust; restrict ports/firewall; rotate API tokens; store hashed passwords.  [oai_citation:182‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:183‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:184‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)
- **Scale / Multi‑tenant:** Use Neko Rooms or orchestration (k8s, compose bundles) to spin per‑team instances; leverage REST API + metrics for automation & autoscaling triggers.  [oai_citation:185‡GitHub](https://github.com/m1k1o/neko/releases) [oai_citation:186‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:187‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/)
- **Troubleshoot:** Turn on debug envs; inspect GStreamer logs for encode issues; validate reverse proxy headers; check that WebRTC ports aren’t blocked (common 502 confusion).  [oai_citation:188‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq) [oai_citation:189‡Reddit](https://www.reddit.com/r/nginxproxymanager/comments/ut8zyu/help_with_setting_up_reverse_proxy_custom_headers/) [oai_citation:190‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)
## 17. Roadmap Glimpses & Future Directions
Recent release notes hint at additional session backends (Redis/Postgres), richer plugin ecosystem, and potential RDP/VNC relay modes where Neko acts as a WebRTC gateway rather than running the browser locally. Heise reports interest in direct protocol relay; docs flag “in the future” for expanded session providers.  [oai_citation:191‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html) [oai_citation:192‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:193‡GitHub](https://github.com/m1k1o/neko/releases)
## 18. Community Lore / Field Notes
Homelabbers use Neko to co‑watch media, punch through restrictive corporate firewalls (when Neko host has outbound freedom), and expose full Linux desktops (KDE) to lightweight tablets. These anecdotes underscore why low‑latency WebRTC streaming and easy multi‑user control were prioritized.  [oai_citation:194‡Reddit](https://www.reddit.com/r/selfhosted/comments/1ffz78l/neko_selfhosted_browser/) [oai_citation:195‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/) [oai_citation:196‡GitHub](https://github.com/m1k1o/neko)

Reverse‑proxy misconfig (wrong header name, missing EPR exposure) is a recurring community stumbling block; always validate both HTTP and media planes.  [oai_citation:197‡Reddit](https://www.reddit.com/r/nginxproxymanager/comments/ut8zyu/help_with_setting_up_reverse_proxy_custom_headers/) [oai_citation:198‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:199‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)
# Neko Browser + Playwright/CDP Integration Deep Dive
Neko (“n.eko”) is an open‑source, self‑hosted *virtual browser* that streams a full Linux desktop (not just a headless DOM) over WebRTC so multiple remote users can view and *interactively* control the same session in real time. It targets collaborative browsing, watch parties, remote support, embedded browser surfaces, and hardened “throwaway” cloud browsing where nothing persists locally.  [oai_citation:16‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction) [oai_citation:17‡GitHub](https://github.com/m1k1o/neko) [oai_citation:18‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html)

Unlike simple remote‑automation containers, Neko can run *any* Linux GUI application—browsers (Firefox, Chromium, Brave, Vivaldi, Waterfox, Tor, etc.), media players like VLC, full desktop environments (XFCE, KDE), and bespoke tools—because it captures an Xorg display and streams audio/video frames to clients via WebRTC. This breadth makes it viable for shared debugging sessions, interactive presentations, and as a privacy “jump box” into otherwise restricted networks.  [oai_citation:19‡GitHub](https://github.com/m1k1o/neko) [oai_citation:20‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html) [oai_citation:21‡Umbrel App Store](https://apps.umbrel.com/app/neko)

**Multi‑user collaboration** is first‑class: user roles, admin elevation, shared cursor visibility, host (keyboard/mouse) control arbitration, clipboard access, media sharing, and plugin‑scoped per‑user settings are governed by Neko’s v3 authentication system (Member + Session providers). This replaces v2’s simple dual‑password model and lets you express richer authorization matrices or plug in external identity sources.  [oai_citation:22‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:23‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/introduction)
### Versioning: v3 vs v2 & Legacy Mode
Neko v3 reorganized configuration into modular namespaces (server, member, session, webrtc, desktop, capture, plugins, etc.) and introduced providers; however, v3 retains *backward compatibility* with v2 environment variables when `NEKO_LEGACY=true` is set (and some legacy features auto‑detected). A migration table maps every major v2 var to its v3 equivalent (e.g., `NEKO_SCREEN`→`NEKO_DESKTOP_SCREEN`; `NEKO_PASSWORD`→`NEKO_MEMBER_MULTIUSER_USER_PASSWORD`; `NEKO_NAT1TO1`→`NEKO_WEBRTC_NAT1TO1`). This is critical when modernizing older compose files (like the snippet you shared) to avoid silent fallbacks and dual‑stream cursor quirks.  [oai_citation:24‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/migration-from-v2) [oai_citation:25‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication)

Heise’s Neko 3.0 coverage underscores why migrating matters: new browser flavors (Waterfox, additional Chromium builds, ARM variants), GPU‑accelerated options, screencast fallback, plugin ecosystem growth, and structural config changes—all shipping under a maintained Apache‑2.0 project—mean staying current pays dividends in stability and capability.  [oai_citation:26‡heise online](https://www.heise.de/en/news/Virtual-browser-environment-Use-Firefox-Chrome-Co-in-Docker-with-Neko-3-0-10337659.html) [oai_citation:27‡GitHub](https://github.com/m1k1o/neko)

Community quick‑start guides still widely circulate v2 envs (e.g., `NEKO_SCREEN`, `NEKO_PASSWORD`, `NEKO_ICELITE`, `NEKO_EPR`), which “work” only because legacy support remains—but they obscure v3 tuning knobs and can yield performance or auth surprises (e.g., no granular per‑user policy). Use the migration mapping to upgrade; I’ll show a patched compose below.  [oai_citation:28‡fossengineer.com](https://fossengineer.com/selfhosting-neko-browser/) [oai_citation:29‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/migration-from-v2)
### Authentication Model (v3)
Authentication splits into **Member Provider** (who are you? what can you do?) and **Session Provider** (state & tokens). The *multiuser* provider emulates v2’s “user password” + “admin password” flow; you enable it via `NEKO_MEMBER_PROVIDER=multiuser`, then supply `NEKO_MEMBER_MULTIUSER_USER_PASSWORD` and `NEKO_MEMBER_MULTIUSER_ADMIN_PASSWORD`, optionally overriding default per‑role capability profiles (host, watch, clipboard, etc.). For tighter control, switch to *file* or *object* providers to define fixed accounts, hashed passwords, and granular profiles; or *noauth* for unsecured demo setups (never production). Session storage can persist to file; API access can be separately tokenized (`NEKO_SESSION_API_TOKEN`).  [oai_citation:30‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication)

When exposing Neko programmatically (embedding in an app, auto‑provisioning rooms, LLM agents), consider disabling cookies or providing short‑lived API tokens; but weigh increased XSS risk if tokens leak into client JS when cookies are off. v3 exposes cookie flags (`secure`, `http_only`, domain/path scoping) so you can harden deployment behind TLS.  [oai_citation:31‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication)
### WebRTC Transport Essentials
For smooth low‑latency A/V + input streaming you *must* correctly expose Neko’s WebRTC ports. Three main patterns:

1. **Ephemeral UDP Port Range (EPR)** — Specify a contiguous range (e.g., `56000-56100`) via `NEKO_WEBRTC_EPR` and map the exact same range host:container *without remap*. Each new participant consumes ports; size range accordingly.  [oai_citation:32‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)
2. **UDP/TCP Multiplexing** — Collapse to a single well‑known port (e.g., `59000`) as `NEKO_WEBRTC_UDPMUX` / `NEKO_WEBRTC_TCPMUX` for NAT‑challenged environments; trade throughput.  [oai_citation:33‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)
3. **ICE Servers** — Provide STUN/TURN front/back split: `NEKO_WEBRTC_ICESERVERS_FRONTEND` (what clients see) and `..._BACKEND` (what the server dials internally); JSON‑encoded arrays. Required when clients are off‑LAN and UDP paths are blocked.  [oai_citation:34‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)

If you run behind NAT, set `NEKO_WEBRTC_NAT1TO1` to the public (hairpin‑reachable) address; otherwise clients may ICE‑candidate a private IP and fail to connect. Automatic public IP fetch is available but you can override with `NEKO_WEBRTC_IP_RETRIEVAL_URL`.  [oai_citation:35‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:36‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/migration-from-v2)

**Do not rely on your HTTP reverse proxy to relay WebRTC media.** Nginx/Traefik only front the signaling/control (HTTP(S)/WS) on port 8080; actual RTP/DTLS flows use the ports you expose above and must be reachable end‑to‑end or via TURN.  [oai_citation:37‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:38‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup)

### Reverse Proxy & Timeouts
When fronting Neko with nginx/Traefik/etc., enable proxy trust in server config (`server.proxy=true` / `NEKO_SERVER_PROXY=1` in v3) so real client IPs from `X-Forwarded-*` are honored. Neko sends WS pings ~10s; clients heartbeat ~120s—so bump proxy read timeouts accordingly or users drop during long idle automation runs. Official nginx sample shows required `Upgrade`/`Connection` headers for WebSocket upgrade; community Nginx Proxy Manager threads confirm these plus extended `proxy_read_timeout` and forwarded IP headers to avoid 502s and broken control channels.  [oai_citation:39‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:40‡Reddit](https://www.reddit.com/r/nginxproxymanager/comments/ut8zyu/help_with_setting_up_reverse_proxy_custom_headers/)
### Container Security / Chromium Sandboxing
Chromium inside containers often needs elevated namespaces to run its sandbox; many headless automation images either add `--no-sandbox` (reduced isolation) or grant `--cap-add=SYS_ADMIN` and supporting kernel flags so Chrome’s sandbox works. Puppeteer’s Docker docs call out the SYS_ADMIN requirement for their hardened image; Neko’s own v2 troubleshooting notes that forgetting SYS_ADMIN yields a black screen in Chromium variants—evidence the capability remains relevant. Decide: secure host kernel + allow SYS_ADMIN (preferred for full sandbox) *or* run `--no-sandbox` and accept risk; the sample supervisord snippet you posted already includes `--no-sandbox`, so SYS_ADMIN is belt‑and‑suspenders but still recommended for stability in GPU/namespace operations.  [oai_citation:41‡pptr.dev](https://pptr.dev/guides/docker) [oai_citation:42‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v2/troubleshooting)
### Enabling Chrome DevTools Protocol (CDP) in Neko for Playwright
Your goal: let humans drive the streamed Neko Chromium UI *and* attach automation via Playwright. Playwright supports attaching to any existing Chromium instance that exposes a DevTools endpoint via `chromium.connectOverCDP(endpointURL)`, where `endpointURL` can be the HTTP JSON version URL or direct WS endpoint; the returned `browser` exposes existing contexts/pages. Lower fidelity than full Playwright protocol, but ideal for “co‑drive” scenarios.  [oai_citation:43‡Playwright](https://playwright.dev/docs/api/class-browsertype) [oai_citation:44‡GitHub](https://github.com/m1k1o/neko/issues/391)

Once connected, you can open a raw **CDPSession** per page/context to send protocol commands (e.g., `Runtime.evaluate`, `Animation.enable`), mirroring the manual WebSocket probes in your `test.js`. This is useful for diagnostics, performance metrics, and low‑level tweaks Playwright doesn’t expose natively.  [oai_citation:45‡Playwright](https://playwright.dev/docs/api/class-cdpsession) [oai_citation:46‡Playwright](https://playwright.dev/docs/api/class-browsertype)
#### Remote Debugging Flags & Port Forward Pattern
Modern Chromium removed unrestricted `--remote-debugging-address=0.0.0.0` for security; recommended practice is bind the DevTools socket to localhost within the container (e.g., `--remote-debugging-port=9223`), then selectively forward or reverse‑proxy to an external port (e.g., 9222) with an auth / ACL layer (nginx, socat, SSH tunnel). Your nginx‑cdp sidecar implements precisely this 9222→9223 pass‑through with WebSocket upgrade and long timeouts—aligning with guidance from the Dockerized Chromium remote debugging discussion.  [oai_citation:47‡Stack Overflow](https://stackoverflow.com/questions/58428213/how-to-access-remote-debugging-page-for-dockerized-chromium-launch-by-puppeteer) [oai_citation:48‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup)
### Review of Your `web-agent/neko-with-playwright` Compose Snippet
You posted a two‑service stack: `neko` (using `m1k1o/neko:chromium`) and an `nginx-cdp` sidecar in service network_mode sharing; supervisord launches Chromium with CDP flags and disables sandbox/gpu; nginx maps host 9222 to internal 9223 to front DevTools with WS keepalive/timeouts. Ports published: 52000→8080(tcp?) and 9222 (tcp). Issues & improvements:

- **1. Legacy Env Vars** – You’re mixing v2 (`NEKO_SCREEN`, `NEKO_PASSWORD*`, `NEKO_ICELITE`, `NEKO_NAT1TO1`) in a v3 world; while legacy support exists, you lose granular control and risk double cursor streams (cursor once in video, once separate) plus awkward auth extension later. Upgrade to v3 vars (`NEKO_DESKTOP_SCREEN`, `NEKO_MEMBER_PROVIDER=multiuser`, `NEKO_MEMBER_MULTIUSER_*`, `NEKO_WEBRTC_ICELITE`, `NEKO_WEBRTC_NAT1TO1`).  [oai_citation:49‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/migration-from-v2) [oai_citation:50‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:51‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)

- **2. Missing WebRTC Ports** – No UDP EPR or mux port is exposed, so remote WebRTC will fail off‑box unless clients are on the container host network and fallback mechanisms kick in. Add either an EPR range mapping and `NEKO_WEBRTC_EPR` or UDPMUX/TCPMUX single‑port mapping.  [oai_citation:52‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:53‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup)

- **3. Public vs Private Subnet** – Your custom Docker subnet `17.100.0.0/16` collides with publicly routed Apple allocations (17.0.0.0/8 owned by Apple); choose RFC1918 (e.g., `172.31.0.0/16` or `10.67.0.0/16`) to avoid confusing clients seeing ICE candidates referencing real vs container ranges. Proper NAT1TO1 matters when advertising ICE addresses.  [oai_citation:54‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:55‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup)

- **4. Proxy Headers & Timeouts** – Good start; ensure `proxy_read_timeout` ≥ Neko heartbeat (≥120s) and that `NEKO_SERVER_PROXY=1` (or config) is set so Neko trusts forwarded IPs; align with official reverse proxy doc + community NPM thread.  [oai_citation:56‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:57‡Reddit](https://www.reddit.com/r/nginxproxymanager/comments/ut8zyu/help_with_setting_up_reverse_proxy_custom_headers/)

- **5. Chromium Capability / Sandbox** – You added `cap_add: SYS_ADMIN` (good) *and* `--no-sandbox` (less secure). Consider removing `--no-sandbox` once you confirm kernel support; Neko experiences black screens without SYS_ADMIN in Chromium images; Puppeteer’s hardened image docs reinforce giving SYS_ADMIN if you want sandbox.  [oai_citation:58‡pptr.dev](https://pptr.dev/guides/docker) [oai_citation:59‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v2/troubleshooting)

- **6. Password Hygiene** – Hard‑coding `neko` / `admin` is fine for testing but never production; switch to secrets or `.env` injection; multiuser provider makes it easy.  [oai_citation:60‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:61‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup)

- **7. NAT Hairpin & ICE Lite** – You set `NEKO_ICELITE=0` (full ICE) and NAT1TO1 to container IP; if you actually need WAN access supply your public IP or domain; ICE Lite mode is only appropriate when server has public reflexive; official doc warns not to mix with external ICE servers.  [oai_citation:62‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc)

- **8. Debug Logging** – When diagnosing CDP or WebRTC handshake, enable `NEKO_DEBUG=1` and optional `GST_DEBUG` per FAQ; huge time saver.  [oai_citation:63‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)
### Hardened & Modernized Compose Example (v3 Vars, CDP Enabled)
Below is an updated `docker-compose.yml` (org‑mode src). Key changes:
- Switched to GHCR explicit version tag (pin for reproducibility).
- RFC1918 subnet.
- Proper WebRTC EPR exposure.
- v3 auth vars.
- Proxy flag so Neko trusts sidecar.
- Optional API token for automation mgmt.
- Chromium started with localhost‑bound remote debugging; nginx sidecar terminates TLS (optional) & ACLs; you can env‑inject allowed upstream (e.g., ngrok tunnel).
- Dropped `--no-sandbox` (commented) to prefer secure sandbox; toggle per your threat model.
- Added healthcheck & log volumes.

```yaml
version: "3.8"

x-neko-env: &neko-env
NEKO_DESKTOP_SCREEN: 1920x1080@30
NEKO_MEMBER_PROVIDER: multiuser
NEKO_MEMBER_MULTIUSER_USER_PASSWORD: ${NEKO_USER_PASSWORD:-neko}
NEKO_MEMBER_MULTIUSER_ADMIN_PASSWORD: ${NEKO_ADMIN_PASSWORD:-admin}
NEKO_WEBRTC_EPR: 56000-56100          # match ports below
NEKO_WEBRTC_ICELITE: "false"          # full ICE unless static public IP
NEKO_WEBRTC_NAT1TO1: ${NEKO_PUBLIC_IP:-auto}  # set literal IP or leave unset to auto-detect
NEKO_SERVER_PROXY: "true"             # trust reverse proxy headers
NEKO_SESSION_API_TOKEN: ${NEKO_API_TOKEN:-}   # optional; blank disables
NEKO_DEBUG: ${NEKO_DEBUG:-0}

services:
neko:
  image: ghcr.io/m1k1o/neko/chromium:3.0.4
  container_name: neko
  restart: unless-stopped
  shm_size: 2gb
  networks:
    proxy:
      ipv4_address: 172.31.0.3
  ports:
    - "8080:8080/tcp"                 # web / signaling
    - "56000-56100:56000-56100/udp"   # WebRTC EPR (must match env)
  environment:
    <<: *neko-env
  cap_add:
    - SYS_ADMIN                       # required if not using --no-sandbox
  volumes:
    - neko-data:/var/lib/neko         # persistent config / sessions (bind as needed)
    - neko-logs:/var/log/neko
  configs:
    - source: supervisord_chromium
      target: /etc/neko/supervisord/chromium.conf

nginx-cdp:
  image: nginx:alpine
  container_name: neko-cdp
  network_mode: "service:neko"        # join same net & PID
  depends_on:
    - neko
  environment:
    # restrict which hosts may speak CDP (use allowlist or auth)
    ALLOWED_CDP_ORIGIN: ${ALLOWED_CDP_ORIGIN:-127.0.0.1}
  configs:
    - source: nginx_cdp_conf
      target: /etc/nginx/conf.d/cdp.conf
  ports:
    - "9222:9222/tcp"                 # exposed CDP endpoint proxied to 9223 in container

networks:
proxy:
  ipam:
    config:
      - subnet: 172.31.0.0/16

volumes:
neko-data:
neko-logs:

configs:
supervisord_chromium:
  content: |
    [program:chromium]
    environment=HOME="/home/%(ENV_USER)s",USER="%(ENV_USER)s",DISPLAY="%(ENV_DISPLAY)s"
    command=/usr/bin/chromium \
      --remote-debugging-port=9223 \
      --remote-debugging-address=127.0.0.1 \
      --remote-allow-origins="*" \
      --disable-web-security \
      --disable-features=VizDisplayCompositor \
      --disable-extensions \
      # --no-sandbox \  # uncomment only if you drop SYS_ADMIN
      --disable-dev-shm-usage \
      --enable-automation \
      --disable-background-timer-throttling \
      --disable-backgrounding-occluded-windows \
      --disable-renderer-backgrounding \
      --force-devtools-available \
      --disable-features=TranslateUI \
      --disable-ipc-flooding-protection \
      --enable-blink-features=IdleDetection \
      --headless=new \
      --disable-gpu
    stopsignal=INT
    autorestart=true
    priority=800
    user=%(ENV_USER)s
    stdout_logfile=/var/log/neko/chromium.log
    stdout_logfile_maxbytes=100MB
    stdout_logfile_backups=10
    redirect_stderr=true

    [program:openbox]
    environment=HOME="/home/%(ENV_USER)s",USER="%(ENV_USER)s",DISPLAY="%(ENV_DISPLAY)s"
    command=/usr/bin/openbox --config-file /etc/neko/openbox.xml
    autorestart=true
    priority=300
    user=%(ENV_USER)s
    stdout_logfile=/var/log/neko/openbox.log
    stdout_logfile_maxbytes=100MB
    stdout_logfile_backups=10
    redirect_stderr=true

nginx_cdp_conf:
  content: |
    map $http_upgrade $connection_upgrade {
      default upgrade;
      ''      close;
    }

    upstream chrome {
      server 127.0.0.1:9223;
      keepalive 32;
    }

    server {
      listen 9222;

      # Optional IP allowlist (simple example); extend w/ auth / mTLS as needed
      allow 127.0.0.1;
      allow ::1;
      # env-subst ALLOWED_CDP_ORIGIN could template additional allow lines
      deny all;

      location / {
        proxy_pass http://chrome;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $connection_upgrade;

        proxy_set_header Host $host:$server_port;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_connect_timeout 7200s;
        proxy_cache off;
        proxy_buffering off;
        proxy_max_temp_file_size 0;
        proxy_request_buffering off;

        proxy_set_header Sec-WebSocket-Extensions $http_sec_websocket_extensions;
        proxy_set_header Sec-WebSocket-Key $http_sec_websocket_key;
        proxy_set_header Sec-WebSocket-Version $http_sec_websocket_version;

        proxy_socket_keepalive on;
        keepalive_timeout 300s;
        keepalive_requests 1000;
      }
    }
```
[oai_citation:64‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/migration-from-v2) [oai_citation:65‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:66‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:67‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:68‡Stack Overflow](https://stackoverflow.com/questions/58428213/how-to-access-remote-debugging-page-for-dockerized-chromium-launch-by-puppeteer) [oai_citation:69‡pptr.dev](https://pptr.dev/guides/docker) [oai_citation:70‡Reddit](https://www.reddit.com/r/nginxproxymanager/comments/ut8zyu/help_with_setting_up_reverse_proxy_custom_headers/)
### Minimal `.env` Illustration (override at deploy)
```dotenv
NEKO_USER_PASSWORD=supersecretuser
NEKO_ADMIN_PASSWORD=supersecretadmin
NEKO_PUBLIC_IP=203.0.113.45        # example; or set DNS name in upstream LB/TURN
NEKO_API_TOKEN=$(openssl rand -hex 32)
NEKO_DEBUG=1
ALLOWED_CDP_ORIGIN=10.0.0.0/8      # example ACL range for automation runners
```
[oai_citation:71‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:72‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:73‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)
### Playwright Attach Script (Improved)
Key best practices: discover the *browser* WebSocket endpoint from `/json/version`; create a context if none returned (some builds start w/ zero pages when headless new); gracefully handle targets; optionally filter to the Neko desktop window by URL. Example:

```js
// attach-neko.js
const { chromium } = require('playwright');

(async () => {
const cdpHttp = process.env.NEKO_CDP_URL || 'http://localhost:9222';

// Attach to existing Chromium exposed by Neko's CDP proxy.
const browser = await chromium.connectOverCDP(cdpHttp);

// In many cases Neko's running Chromium already has a default context.
// If none, create one.
const [defaultContext] = browser.contexts().length
  ? browser.contexts()
  : [await browser.newContext()];

// Reuse first existing page or open a new one.
const page = defaultContext.pages()[0] || await defaultContext.newPage();

await page.goto('https://example.com');
console.log('Neko page title:', await page.title());

// Get raw CDP session if you want low-level control.
const client = await page.context().newCDPSession(page);
const version = await client.send('Browser.getVersion').catch(() => null);
console.log('CDP Browser Version:', version);

// Keep browser open for human co-driving; do NOT close().
})();
```
[oai_citation:74‡Playwright](https://playwright.dev/docs/api/class-browsertype) [oai_citation:75‡Playwright](https://playwright.dev/docs/api/class-cdpsession) [oai_citation:76‡GitHub](https://github.com/m1k1o/neko/issues/391)
### Diagnostic CDP Ping Script (Refined from Your `test.js` / `test4.js`)
Below is a leaner diagnostic that:
1. Fetches `/json/version`;
2. Opens WebSocket;
3. Discovers targets;
4. Attaches to first non‑extension page;
5. Evaluates an expression;
6. Logs failures cleanly.

```js
// cdp-diagnostics.js
const WebSocket = require('ws');
const fetch = (...args) => import('node-fetch').then(({default: f}) => f(...args));

(async () => {
const base = process.env.NEKO_CDP_URL || 'http://localhost:9222';
const version = await (await fetch(`${base}/json/version`)).json();
const wsUrl = version.webSocketDebuggerUrl;

const ws = new WebSocket(wsUrl, { perMessageDeflate: false });
let id = 0;

function send(method, params, sessionId) {
ws.send(JSON.stringify({ id: ++id, method, params, sessionId }));
}

ws.on('open', () => {
console.log('CDP connected');
send('Target.setDiscoverTargets', { discover: true });
});

let firstSession;
ws.on('message', data => {
const msg = JSON.parse(data);
if (msg.method === 'Target.targetCreated') {
const t = msg.params.targetInfo;
if (t.type === 'page' && !t.url.startsWith('chrome-extension://')) {
send('Target.attachToTarget', { targetId: t.targetId, flatten: true });
}
} else if (msg.method === 'Target.attachedToTarget' && !firstSession) {
firstSession = msg.params.sessionId;
send('Runtime.enable', {}, firstSession);
send('Runtime.evaluate', { expression: '1+1' }, firstSession);
} else if (msg.id && msg.result) {
console.log('Result', msg.id, msg.result);
} else if (msg.error) {
console.error('CDP Error', msg.error);
}
});
})();
```
[oai_citation:77‡Stack Overflow](https://stackoverflow.com/questions/58428213/how-to-access-remote-debugging-page-for-dockerized-chromium-launch-by-puppeteer) [oai_citation:78‡Playwright](https://playwright.dev/docs/api/class-cdpsession) [oai_citation:79‡Playwright](https://playwright.dev/docs/api/class-browsertype)
### Operational Checklist for Playwright‑Augmented Neko
| Check | Why | How to Verify |
| --- | --- | --- |
| Chromium started with `--remote-debugging-port` (localhost) | Required for CDP attach; safer than 0.0.0.0 | `curl http://<host>:9222/json/version` returns JSON |
| CDP proxy ACL in place | Prevent hostile takeover of your shared session | restrict IPs or auth in nginx; test from unauthorized host fails |
| WebRTC ports reachable | Avoid black screens / frozen video | `webrtc-internals` in client; `docker logs` ICE candidate errors |
| SYS_ADMIN vs `--no-sandbox` decision documented | Security posture clarity | Confirm container start flags; run `chrome://sandbox` |
| Multiuser passwords rotated | Prevent drive‑by admin | Use secrets; verify login roles mapping |
| Proxy timeout > heartbeat | Prevent surprise disconnects during long automation | Nginx `proxy_read_timeout >= 120s` |
| Debug logging toggled for incident response | Rapid triage | `NEKO_DEBUG=1`, `GST_DEBUG=3` when needed |
[oai_citation:80‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:81‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:82‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:83‡pptr.dev](https://pptr.dev/guides/docker) [oai_citation:84‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v2/troubleshooting)
### Example Hybrid Workflow: Humans Steer, Agents Assist
A common pattern in agentic stacks:
1. Human opens Neko in browser, logs in as admin (multiuser).
2. Automation runner (Playwright script / LLM agent) attaches over CDP using service account limited by firewall.
3. Agent performs scripted setup (login, nav, cookie seeding) *then relinquishes*; human sees results instantly.
4. If human taking over triggers UI state changes, agent can poll via CDP events (Target/Runtime) to resume.

This model avoids re‑launching browsers and preserves session continuity Neko already streams to participants.  [oai_citation:85‡Playwright](https://playwright.dev/docs/api/class-browsertype) [oai_citation:86‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/authentication) [oai_citation:87‡GitHub](https://github.com/m1k1o/neko/issues/391)
### Deployment Channels & Ecosystem
You can deploy via raw Docker/Compose, room orchestration stacks (neko‑rooms), homelab bundles (Umbrel App Store), or community charts/templates; packaging often pre‑wires reverse proxy + TLS but may lag in env var updates—review and update to v3 syntax after install.  [oai_citation:88‡Umbrel App Store](https://apps.umbrel.com/app/neko) [oai_citation:89‡GitHub](https://github.com/m1k1o/neko) [oai_citation:90‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/migration-from-v2)

### Troubleshooting Quick Hits
- **Black screen (cursor only) in Chromium flavor** → missing SYS_ADMIN or mis‑sandbox; confirm capability or drop sandbox flag.  [oai_citation:91‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v2/troubleshooting) [oai_citation:92‡pptr.dev](https://pptr.dev/guides/docker)

- **WebRTC connect stalls / DTLS not started** → exposed UDP mismatch or firewall block; check EPR mapping & NAT1TO1; review server logs at debug level.  [oai_citation:93‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/configuration/webrtc) [oai_citation:94‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/faq)

- **Users disconnect behind proxy** → heartbeat vs proxy timeout mismatch; ensure `proxy_read_timeout` >120s and `server.proxy` enabled.  [oai_citation:95‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup) [oai_citation:96‡Reddit](https://www.reddit.com/r/nginxproxymanager/comments/ut8zyu/help_with_setting_up_reverse_proxy_custom_headers/)

- **CDP connect refused** → nginx sidecar not up or ACL blocking; verify `/json/version` at 9222 and upstream 9223 reachable in container.  [oai_citation:97‡Stack Overflow](https://stackoverflow.com/questions/58428213/how-to-access-remote-debugging-page-for-dockerized-chromium-launch-by-puppeteer) [oai_citation:98‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/reverse-proxy-setup)

- **Legacy envs ignored** → upgrade to v3 names or set `NEKO_LEGACY=true` explicitly; review migration matrix.  [oai_citation:99‡neko.m1k1o.net](https://neko.m1k1o.net/docs/v3/migration-from-v2)
# Neko v3 WebRTC & WebSocket Control: Frame/State, Keyboard, Mouse (Cited)
**TL;DR:**
- All browser control in Neko v3 is mediated over a single `/api/ws` WebSocket after session authentication.
- Browser frames are *not* delivered directly over the WS as video; rather, the WS carries *control*, *signaling*, *events*, and input (mouse/keyboard) JSON, with media frames (video, audio) negotiated via WebRTC ICE as a peer connection.
- Full workflow: REST login → WS upgrade (`/api/ws`) → system/init → WebRTC signal/request → ICE handshake → frames sent to client, controls sent from client.
## 1. Authenticate (REST, Cookie, Token, Password)
| Mode | REST Call | Response | WS Upgrade Auth |
| --- | --- | --- | --- |
| Cookie (default) | `POST /api/login {username, password}` | `Set-Cookie: NEKO_SESSION` | Cookie auto-sent |
| Token (stateless) | `POST /api/login` for `{token}` | Opaque JWT/Bearer | `?token=...` or Bearer header |
| Legacy (query) | (multiuser only) skip REST, `?password=` | — | ?password in query triggers v2 |
## 2. WebSocket Upgrade URL (With/Without Path Prefix)
- Mainline: `wss://host[:port]/api/ws?token=<TOKEN>`
- With path-prefix: e.g. `wss://proxy.example.com/neko/api/ws?token=...`
- Alt: cookies or `Authorization: Bearer ...` supported.
- Legacy `/ws` endpoint: only if enabled or in legacy mode.
## 3. Connection Lifecycle
1. **Upgrade:** Gorilla WS server handles `/api/ws`, performs token/cookie/Bearer/session check.
2. **Init:** Server pushes `system/init` (JSON: session id, settings, role).
3. **Heartbeat:** Server/client both ping (WS and app-level JSON); must reply or disconnect in 10-20s.
4. **All interaction now flows over the socket:** control events (keyboard/mouse), signaling (ICE, SDP), system/broadcast, errors.
5. **All client state (host, cursor, input, session, etc.) is managed by events.**
## 4. How Media (Frames) and Control Flow
### Media
- **Video and audio frames** do **not** go over the WebSocket; they are WebRTC media streams (negotiated via signaling on WS).
- To *initiate* frame streaming, send:
  `{"event":"signal/request","payload":{"video":{},"audio":{}}}`
- Server replies with ICE candidates/SDP; client opens WebRTC peer connection.
- Browser’s actual frames (video, audio) arrive via WebRTC MediaStream.
- ### Input: Keyboard/Mouse
- Input is sent **from client to server** as JSON events:
	- `{"event":"control/move","payload":{"x":123,"y":456}}` — cursor
	- `{"event":"control/click","payload":{"button":"left","state":"down"}}` (also `up`)
	- `{"event":"control/key","payload":{"key":"a","code":65,"state":"down"}}` (also `up`)
- These are parsed and injected to the X server (XTest or evdev) running the browser desktop.
- Host arbitration: only one participant at a time has “host” (mouse/keyboard); others are view-only, but may request control (send `control/request_host`).
## 5. Minimal JS Client Example
```typescript
import fetch from 'node-fetch';
import WebSocket from 'ws';

// Step 1: Auth
const { token } = await fetch('https://neko.example.com/api/login', {
method: 'POST',
headers: { 'content-type': 'application/json' },
body: JSON.stringify({ username: 'alice', password: 'secret' })
}).then(r => r.json());

// Step 2: WebSocket
const ws = new WebSocket(`wss://neko.example.com/api/ws?token=${token}`);

// Step 3: Signal to start media (video/audio)
ws.on('open', () => {
ws.send(JSON.stringify({ event: 'signal/request', payload: { video: {}, audio: {} } }));
// Optionally: request host/input
ws.send(JSON.stringify({ event: 'control/request_host' }));
// Example: send keypress "a"
ws.send(JSON.stringify({ event: 'control/key', payload: { key: "a", code: 65, state: "down" } }));
// Example: move mouse to x=400,y=200
ws.send(JSON.stringify({ event: 'control/move', payload: { x: 400, y: 200 } }));
// Example: mouse click left
ws.send(JSON.stringify({ event: 'control/click', payload: { button: "left", state: "down" } }));
});

// Step 4: Media frames come via WebRTC, not WS
// (client listens on the peerconnection, renders in canvas/video)
```
## 6. WebSocket Event Format (All)
```typescript
{
"event": "event/type",   // e.g., control/move, signal/offer, system/init
"payload": { ... }
}
```
- See `pkg/types/websocket.go` for full registry of events (control, signal, system, broadcast, etc.).
## 7. Staying Alive, Handling Disconnect
- **Server disconnects** if:
	- WS Pong not received in 10s.
	- App-level heartbeat not received in 20s.
	- Multiple WS connections from same session: most recent overrides.
- **Reconnection:** If enabled, peer is replaced.
- **Debug:** Use `websocat` for smoke-test (see CLI example).
## 8. Proxying & Pitfalls
| Symptom | Cause | Fix |
| --- | --- | --- |
| "unable to connect to server" | Proxy missing WS upgrade | Proxy must pass WS Upgrade headers |
| Disconnect after 10s | No cookie/token or heartbeat | Pass session, send heartbeats |
| WSS but no media | UDP ports blocked, STUN/TURN bad | Open UDP range, configure TURN |
| "origin not allowed" | CORS / server.cors block | Add client origin to server.cors |
| Multi-WS with one token | Session multiplex, latest wins | Expected; session/* broadcast |
## 9. Full Protocol Recap
1. **Login** (REST/cookie/token).
2. **Connect WebSocket** `/api/ws?token=...`.
3. **Wait for `system/init`** (session, host, settings).
4. **Send `signal/request`** (video/audio).
5. **Negotiate WebRTC** (SDP offer/answer/candidates via WS `signal/*` events).
6. **Frames delivered** via WebRTC MediaStream; control is bidirectional over WS.
7. **Input**: Send JSON events (`control/move`, `control/click`, `control/key`).
8. **All session events** (host control, errors, etc.) as JSON on WS.
## 10. References and Further Reading
- [Neko GitHub](https://github.com/m1k1o/neko)
- [Neko v3 Docs: Configuration](https://neko.m1k1o.net/docs/v3/configuration)
- [WS/Session Auth Source](https://raw.githubusercontent.com/m1k1o/neko/master/server/internal/api/session.go)
- [WebSocket Manager/Types](https://raw.githubusercontent.com/m1k1o/neko/master/server/internal/websocket/manager.go)
- [WS Event Types](https://raw.githubusercontent.com/m1k1o/neko/master/server/pkg/types/websocket.go)
- [Release Notes](https://neko.m1k1o.net/docs/v3/release-notes)
- [CLI/Community Debug](https://github.com/m1k1o/neko/issues/371)
