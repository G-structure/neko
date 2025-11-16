# Installation Snippet for README

Add this section to your main README.md:

---

## Installation

### macOS

Install Neko agent on macOS with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/m1k1o/neko/master/scripts/install-agent-macos.sh | sh
```

<details>
<summary>Alternative: Build from source</summary>

```bash
curl -fsSL https://raw.githubusercontent.com/m1k1o/neko/master/scripts/install-agent-macos.sh | sh -s -- --build-from-source
```
</details>

See the [macOS installation guide](./INSTALL_MACOS.md) for detailed instructions.

### Linux

For Linux installation with systemd:

```bash
./scripts/install-agent.sh
```

See the [agent documentation](./AGENT.md) for more details.

### Docker

For Docker-based deployment:

```bash
docker run -d \
  --name neko \
  -p 8080:8080 \
  -p 52000-52100:52000-52100/udp \
  -e NEKO_DESKTOP_SCREEN=1920x1080@30 \
  m1k1o/neko:firefox
```

See [Docker images](./webpage/docs/installation/docker-images.md) for available variants.

---
