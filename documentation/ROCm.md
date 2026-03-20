# ROCm on Fedora

Reference guide for AMD ROCm — what it is, how this repo installs it, and how to use it for GPU compute workloads.

## Contents

- [What is ROCm](#what-is-rocm)
- [GPU compatibility](#gpu-compatibility)
- [Installation](#installation)
- [Verifying the install](#verifying-the-install)
- [Key environment variables](#key-environment-variables)
- [Fedora-specific gotchas](#fedora-specific-gotchas)
- [Ecosystem — AI and GPU tools](#ecosystem--ai-and-gpu-tools)
- [Uninstalling](#uninstalling)
- [Further reading](#further-reading)

---

## What is ROCm

ROCm (Radeon Open Compute) is AMD's open-source GPU compute platform — the equivalent of NVIDIA's CUDA. It lets you run general-purpose GPU workloads (machine learning, inference, scientific computing) on AMD hardware.

### Key components

| Component | What it does |
|---|---|
| **HIP** (Heterogeneous-computing Interface for Portability) | Programming API. Most CUDA code can be ported to HIP with minimal changes. |
| **OpenCL runtime** | Alternative compute API. Used by some older tools and benchmarks. |
| **rocm-smi** | CLI tool for monitoring GPU temperature, utilization, clocks, power draw. Think `nvidia-smi`. |
| **rocminfo** | Enumerates HSA (Heterogeneous System Architecture) agents — shows which GPUs the runtime can see. |
| **HSA runtime** | Low-level runtime that HIP and OpenCL are built on. Communicates with the kernel driver via `/dev/kfd`. |

### ROCm vs the display driver

ROCm is **not** your display driver. On Fedora, display output is handled by:

- **amdgpu** — the kernel DRM driver (always loaded for AMD GPUs)
- **Mesa** — the userspace OpenGL/Vulkan driver

ROCm adds a *compute* stack on top of the same `amdgpu` kernel driver. You can run a desktop without ROCm, and you can run ROCm without a display (headless).

The kernel interface for compute is `/dev/kfd` (Kernel Fusion Driver). Display uses `/dev/dri/cardN` and `/dev/dri/renderDN`. Both coexist.

---

## GPU compatibility

ROCm officially supports specific AMD GPU architectures. Support depends on the ASIC generation and its `gfx` target ID.

### RDNA / CDNA support matrix

| Generation | Architecture | Example GPUs | gfx target | ROCm support |
|---|---|---|---|---|
| RDNA 3 | Navi 3x | RX 7900 XTX, 7800 XT, 7700 XT, 7600 | gfx1100, gfx1101, gfx1102 | Official (6.x+) |
| RDNA 2 | Navi 2x | RX 6900 XT, 6800 XT, 6700 XT, 6600 | gfx1030, gfx1031, gfx1032 | Official |
| RDNA 1 | Navi 1x | RX 5700 XT, 5600 XT | gfx1010 | Community / override needed |
| CDNA 3 | MI300 | Instinct MI300X | gfx942 | Official (data center) |
| CDNA 2 | MI200 | Instinct MI250X | gfx90a | Official (data center) |
| Vega | GCN 5 | Vega 56/64, VII | gfx900, gfx906 | Legacy, may need overrides |

> **Note:** This repo's `lspci` detection in `bootstrap.sh` targets `Navi` and `RDNA` strings only. Older Vega or GCN cards won't trigger the discrete GPU flag.

### Finding your gfx target

```bash
# After ROCm is installed:
rocminfo | grep -i 'name:.*gfx'

# Without ROCm — check the kernel driver:
cat /sys/class/drm/card*/device/gpu_id 2>/dev/null
# Or look up your PCI ID:
lspci -nn | grep VGA
```

---

## Installation

### Option 1: This repo (`bootstrap.sh --rocm`)

```bash
./scripts/bootstrap.sh --rocm
```

**What it installs:**

| Package | Purpose |
|---|---|
| `rocm-hip-runtime` | HIP runtime libraries (what apps link against) |
| `rocm-opencl-runtime` | OpenCL runtime |
| `rocm-smi-lib` | GPU monitoring CLI (`rocm-smi`) |
| `rocminfo` | HSA agent enumeration |

**What it also does:**

- Adds your user to the `video` and `render` groups (required for `/dev/kfd` access)
- Configures the AMD GPU and ROCm repos (`/etc/yum.repos.d/amdgpu.repo` and `rocm.repo`)

**What it does NOT install:**

- ROCm dev headers or compilers (`rocm-hip-sdk`, `hipcc`) — not needed for running pre-built apps
- ROCm env vars in the shell — set these per-tool as needed (see [environment variables](#key-environment-variables))
- AI applications (Ollama, PyTorch, etc.) — see [ecosystem](#ecosystem--ai-and-gpu-tools)

**Repo URLs configured:**

```ini
# /etc/yum.repos.d/amdgpu.repo
[amdgpu]
baseurl=https://repo.radeon.com/amdgpu/latest/rhel/$releasever/main/x86_64/

# /etc/yum.repos.d/rocm.repo
[rocm]
baseurl=https://repo.radeon.com/rocm/rhel9/$releasever/main
```

Both repos are signed with `https://repo.radeon.com/rocm/rocm.gpg.key`.

### Option 2: AMD repo (full stack)

If you need the development tools (HIP compiler, math libraries, profilers):

```bash
# After the repo is configured by bootstrap.sh:
sudo dnf install -y rocm-hip-sdk    # HIP compiler + runtime + math libs
# Or the full meta-package:
sudo dnf install -y rocm            # everything
```

**AMD repo vs Fedora-packaged ROCm:**

| | AMD repo (repo.radeon.com) | Fedora-packaged |
|---|---|---|
| **Versions** | Latest ROCm releases, often ahead of Fedora | Lags behind; may be a major version behind |
| **Tested on** | RHEL/Ubuntu primarily; Fedora is not officially supported | Built for Fedora, integrates with system libs |
| **Conflicts** | Can conflict with Fedora's Mesa/libdrm packages | No conflicts, but may lack features |
| **Use when** | You need a specific ROCm version or latest features | You want minimal maintenance and system integration |

This repo uses the AMD repo because Fedora-packaged ROCm is often too far behind for AI workloads.

### Option 3: Containers (recommended for AI workloads)

Containers sidestep Fedora compatibility issues entirely. The host only needs the kernel driver (`amdgpu`) and group membership — no userspace ROCm packages required.

```bash
# Pass GPU devices into a container:
podman run --rm -it \
    --device /dev/kfd \
    --device /dev/dri \
    --group-add video \
    --group-add render \
    rocm/pytorch:latest

# Ollama in a container:
podman run -d \
    --device /dev/kfd \
    --device /dev/dri \
    --group-add video \
    --group-add render \
    -p 11434:11434 \
    -v ollama-data:/root/.ollama \
    ollama/ollama:rocm
```

**Why containers:**
- Tested base images (Ubuntu/RHEL) with known-good ROCm versions
- No risk of Mesa/libdrm conflicts with Fedora packages
- Easy to pin or upgrade ROCm versions independently
- Multiple ROCm versions can coexist (different containers)

---

## Verifying the install

After installing ROCm and **rebooting** (required for group changes):

### 1. Check group membership

```bash
groups
# Should include: video render
# If not, you haven't rebooted since bootstrap ran.
```

### 2. Check device nodes

```bash
ls -la /dev/kfd /dev/dri/render*
# /dev/kfd         — HSA kernel interface (compute)
# /dev/dri/renderDN — DRM render node
# Both should be accessible by the 'render' group.
```

### 3. Enumerate GPU agents

```bash
rocminfo | head -40
# Look for your GPU under "Agent" entries.
# The "Name:" field should show your gfx target (e.g., gfx1100).
```

### 4. Monitor GPU status

```bash
rocm-smi
# Shows temperature, utilization, clocks, memory usage, power draw.
# All zeros for utilization is normal when idle.
```

### 5. List installed ROCm packages

```bash
rpm -qa | grep -E 'rocm|hip|hsa'
# Expect: rocm-hip-runtime, rocm-opencl-runtime, rocm-smi-lib, rocminfo,
#         plus their dependencies (hsa-rocr, hip-runtime-amd, etc.)
```

### Common verification failures

| Symptom | Cause | Fix |
|---|---|---|
| `rocminfo` says "Permission denied" | Not in `video`/`render` groups | `sudo usermod -aG video,render $USER` then reboot |
| `rocminfo` shows no GPU agents | ROCm doesn't recognize your GPU | Check [gfx target](#finding-your-gfx-target); may need `HSA_OVERRIDE_GFX_VERSION` |
| `/dev/kfd` doesn't exist | `amdgpu` kernel module not loaded | `sudo modprobe amdgpu`; check `dmesg` for errors |
| `rocm-smi` command not found | Package not installed or not in PATH | `rpm -q rocm-smi-lib`; check `/opt/rocm/bin` is in PATH |

---

## Key environment variables

| Variable | Purpose | Example |
|---|---|---|
| `HSA_OVERRIDE_GFX_VERSION` | Force the runtime to treat your GPU as a different target | `HSA_OVERRIDE_GFX_VERSION=11.0.0` |
| `HIP_VISIBLE_DEVICES` | Restrict which GPUs are visible to HIP (0-indexed) | `HIP_VISIBLE_DEVICES=0` |
| `GPU_MAX_ALLOC_PERCENT` | Max percentage of VRAM a single allocation can use (default: 75) | `GPU_MAX_ALLOC_PERCENT=100` |
| `HSA_ENABLE_SDMA` | Enable/disable SDMA engines for memory copies | `HSA_ENABLE_SDMA=0` |
| `ROCM_PATH` | Override ROCm install location (default: `/opt/rocm`) | `ROCM_PATH=/opt/rocm-6.2.0` |
| `AMD_LOG_LEVEL` | HIP runtime log verbosity (0=off, 4=max) | `AMD_LOG_LEVEL=3` |

### HSA_OVERRIDE_GFX_VERSION — when and why

This variable tells the HSA runtime to treat your GPU as a different architecture. It's the most commonly needed override on consumer GPUs.

**When you need it:**
- Your GPU works for display but `rocminfo` shows no agent or ROCm apps crash with "unsupported ISA"
- You have a newer RDNA GPU that your ROCm version doesn't recognize yet
- You have an RDNA 1 or older GPU without official ROCm support

**Format:** `major.minor.stepping` — maps to the gfx target ID.

| Your GPU (gfx target) | Override value | Maps to |
|---|---|---|
| gfx1030 (RX 6800/6900) | `10.3.0` | gfx1030 (usually not needed) |
| gfx1031 (RX 6700 XT) | `10.3.0` | gfx1030 |
| gfx1032 (RX 6600) | `10.3.0` | gfx1030 |
| gfx1100 (RX 7900 XTX) | `11.0.0` | gfx1100 (usually not needed) |
| gfx1101 (RX 7800 XT) | `11.0.0` | gfx1100 |
| gfx1102 (RX 7700 XT/7600) | `11.0.0` | gfx1100 |
| gfx1010 (RX 5700 XT) | `10.1.0` | gfx1010 (experimental, may not work) |

**Risks:**
- Mismatched ISA can cause silent compute errors or crashes
- Only override to a target in the same architecture family (don't map RDNA 2 → RDNA 3)
- Test with a known-good workload after setting the override

**Usage:**

```bash
# Per-command:
HSA_OVERRIDE_GFX_VERSION=11.0.0 rocminfo

# Per-session:
export HSA_OVERRIDE_GFX_VERSION=11.0.0

# Persistent (add to your shell profile, NOT to bootstrap-env.sh):
echo 'export HSA_OVERRIDE_GFX_VERSION=11.0.0' >> ~/.bashrc
```

> **Why not bootstrap-env.sh?** The override is GPU-specific and potentially risky. It belongs in your personal shell config, not in a managed file that bootstrap.sh overwrites.

---

## Fedora-specific gotchas

### `$releasever` mismatch

The AMD repos use `$releasever` in their baseurl, but they don't publish packages for every Fedora release. If `dnf` fails with 404 errors:

```bash
# Check what releasever dnf is using:
rpm -E %fedora

# If AMD doesn't have packages for your version, pin the repo:
sudo sed -i 's/$releasever/42/' /etc/yum.repos.d/amdgpu.repo
sudo sed -i 's/$releasever/42/' /etc/yum.repos.d/rocm.repo
```

Note: the `rocm.repo` in this repo uses `rhel9/$releasever` — this is AMD's convention for RHEL-compatible repos. Fedora's `$releasever` (e.g. 42) may not match any published path. Check [repo.radeon.com](https://repo.radeon.com/rocm/) for available versions.

### Fedora is not officially supported

AMD tests ROCm on Ubuntu and RHEL. Fedora works because it shares the RHEL kernel driver and package format, but:

- New Fedora releases may break ROCm before AMD publishes updated packages
- AMD support won't help you debug Fedora-specific issues
- Community forums and the Arch wiki are often more useful than official docs

### Kernel update skew

A Fedora kernel update can break ROCm if the new kernel's `amdgpu` module is incompatible with the installed ROCm userspace. Symptoms:

- `rocminfo` stops finding your GPU after a kernel update
- `/dev/kfd` disappears

**Mitigations:**
- Check `dmesg | grep -i amdgpu` after kernel updates
- Keep the previous kernel in GRUB (`sudo grubby --info=ALL`) as a fallback
- Consider pinning the kernel version if you need ROCm stability

### SELinux denials

SELinux may block access to `/dev/kfd` or GPU memory mappings. Check:

```bash
sudo ausearch -m avc -ts recent | grep -i kfd
# or
sudo journalctl -t setroubleshoot --since "1 hour ago"
```

If you see denials, create a local policy module rather than disabling SELinux:

```bash
sudo ausearch -m avc -ts recent | audit2allow -M rocm-local
sudo semodule -i rocm-local.pp
```

### Mesa / libdrm conflicts

The AMD repo's `amdgpu` packages can conflict with Fedora's Mesa and libdrm packages. Symptoms include:

- `dnf update` failing with package conflicts
- Display issues after installing ROCm packages

If this happens:

```bash
# Check for conflicting packages:
rpm -qa | grep -E 'mesa|libdrm|amdgpu' | sort

# The nuclear option — pin Fedora's packages:
sudo dnf versionlock add mesa-* libdrm-*
```

This is another reason [containers](#option-3-containers-recommended-for-ai-workloads) are recommended for AI workloads.

---

## Ecosystem — AI and GPU tools

### Ollama

Local LLM inference server. Easiest way to run models on AMD GPUs.

```bash
# Install (standalone binary, manages its own runtime):
curl -fsSL https://ollama.com/install.sh | sh

# Verify GPU detection:
ollama list    # should work after install
# Check logs for ROCm/HIP initialization:
journalctl -u ollama | grep -i 'rocm\|hip\|gpu'

# Run a model:
ollama run llama3.1
```

Ollama bundles its own ROCm libraries — it doesn't depend on system ROCm packages. However, it still needs `/dev/kfd` access (group membership).

### llama.cpp

Lower-level inference engine. Build from source for ROCm:

```bash
# Requires rocm-hip-sdk (dev headers + compiler):
sudo dnf install -y rocm-hip-sdk

git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DGGML_HIP=ON
cmake --build build --config Release -j$(nproc)

# Verify GPU offload:
./build/bin/llama-cli -m model.gguf -ngl 99 --verbose
# Look for "hip" in the output.
```

### PyTorch (ROCm)

PyTorch publishes ROCm-specific wheels. Do **not** install the default (CUDA) build.

```bash
# Check the install matrix at pytorch.org for the correct command.
# Example for ROCm 6.2:
pip install torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/rocm6.2

# Verify:
python3 -c "import torch; print(torch.cuda.is_available())"
# Returns True — PyTorch uses the CUDA API naming even for ROCm.
python3 -c "import torch; print(torch.cuda.get_device_name(0))"
```

### vLLM

High-throughput inference server. Has ROCm support:

```bash
# Install ROCm build:
pip install vllm  # ROCm support is included if ROCm is detected

# Or use the container:
podman run --rm -it \
    --device /dev/kfd --device /dev/dri \
    --group-add video --group-add render \
    -p 8000:8000 \
    vllm/vllm-openai:latest \
    --model meta-llama/Llama-3.1-8B
```

### LACT (Linux AMDGPU Controller)

GUI/CLI tool for GPU overclocking, fan curves, and monitoring. Alternative to `rocm-smi` with a graphical interface.

```bash
# Install from COPR or build from source:
sudo dnf copr enable ilyaz/LACT -y
sudo dnf install -y lact

# Start the daemon:
sudo systemctl enable --now lactd

# Launch GUI:
lact gui
```

---

## Uninstalling

### Remove ROCm packages

```bash
sudo dnf remove rocm-hip-runtime rocm-opencl-runtime rocm-smi-lib rocminfo
# This will also remove dependencies pulled in by these packages.

# If you installed the full SDK:
sudo dnf remove 'rocm-*' 'hip-*' 'hsa-*'
```

### Remove AMD repos

```bash
sudo rm -f /etc/yum.repos.d/amdgpu.repo /etc/yum.repos.d/rocm.repo
sudo dnf clean all
```

### Clean up environment

Remove any ROCm-related exports from your shell config:

```bash
# Check for ROCm env vars:
grep -n 'HSA_\|ROCM_\|HIP_\|GPU_MAX' ~/.bashrc
# Remove the relevant lines.
```

Group membership (`video`, `render`) can be left in place — it doesn't cause issues without ROCm installed, and the display stack uses the same groups.

---

## Further reading

- [AMD ROCm documentation](https://rocm.docs.amd.com/) — official docs, installation guides, API references
- [ROCm supported GPU list](https://rocm.docs.amd.com/projects/install-on-linux/en/latest/reference/system-requirements.html) — official hardware compatibility matrix
- [PyTorch install matrix](https://pytorch.org/get-started/locally/) — select ROCm as compute platform
- [Ollama](https://ollama.com/) — local LLM runner with built-in ROCm support
- [llama.cpp ROCm build](https://github.com/ggerganov/llama.cpp/blob/master/docs/build.md) — build instructions for HIP backend
- [LACT](https://github.com/ilya-zlobintsev/LACT) — Linux AMDGPU Controller
- [Arch Wiki — AMDGPU](https://wiki.archlinux.org/title/AMDGPU) — best community reference for amdgpu kernel driver behavior (applies to Fedora too)
