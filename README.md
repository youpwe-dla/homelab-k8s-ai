# Homelab: Kubernetes + Local AI/ML

A low-cost homelab for running Kubernetes workloads and local AI/ML models (LLMs) on my own hardware, with no cloud dependency.

**Status:** Phase 1 complete (2026-11-19). Ollama runs local LLMs on the workstation's GTX 1060 and serves its API to the home network at `http://192.168.1.240:11434`. Next: Phase 2, the Kubernetes cluster.

## Phase 1 results

| Model | Fits on GPU? | Speed (tokens/s) |
|---|---|---|
| llama3.2:3b | Yes, 100% GPU (2.6 GB) | 43.64 |
| llama3.1:8b, 4096 context | No, 25%/75% CPU/GPU (5.6 GB) | 13.70 |
| llama3.1:8b, 2048 context | No, 20%/80% CPU/GPU (5.4 GB) | 15.12 |

Takeaway: on a 6 GB card that also drives the Windows desktop, 3B–4B models run fully on the GPU; 8B models work but partly on the CPU. Full build log, problems and fixes: [docs/01-local-ai-on-windows.md](docs/01-local-ai-on-windows.md).

## Goals

- Run LLMs locally on my own GPU (Ollama), reachable from other machines on the home network.
- Build a multi-node Kubernetes cluster on used business mini PCs.
- Schedule AI/ML workloads from Kubernetes and add GPU capacity over time.
- Document everything as code and runbooks in this repo.

## Architecture

```
                    [ Home router / gigabit switch ]
        ┌──────────────┬──────────────┬──────────────┬──────────────────┐
     k8s-node-1     k8s-node-2     k8s-node-3       ai-workstation
     Lenovo M920Q   Lenovo M920Q   Lenovo M920Q     Xeon E3-1275 v5
     control plane  worker         worker           GTX 1060 6GB
     + worker                                       Ollama (port 11434)
     (planned)      (planned)      (planned)        192.168.1.240 (Wi-Fi)
                                                    (Phase 1: done)
```

Kubernetes workloads call the Ollama API on the AI workstation over the LAN. Later phases move GPU workloads into the cluster itself.

## Hardware inventory

| Host | Role | CPU | RAM | GPU | Storage | Status |
|---|---|---|---|---|---|---|
| ai-workstation | Local AI / GPU node | Intel Xeon E3-1275 v5 (4C/8T, 3.6 GHz) | 16 GB | NVIDIA GTX 1060 6GB (Pascal, CUDA compute 6.1) | 512 GB SSD + 1 TB HDD | Active |
| k8s-node-1..3 | Kubernetes nodes | Intel i5-8600T (6C) | 8 GB (upgradeable to 32 GB) | Intel UHD 630 | 256 GB NVMe | Planned (~$139 each, used) |

## Roadmap

| Phase | Scope | Status |
|---|---|---|
| 1 | Update NVIDIA driver, install Ollama on Windows, run and benchmark small LLMs, expose the API on the LAN | **Done (2026-11-19):** [docs/01-local-ai-on-windows.md](docs/01-local-ai-on-windows.md). The Spectrum router has no IP reservation; the workstation stays on DHCP (check the IP after reboots) |
| 2 | Own router (replaces the Spectrum router, keeps the modem) for fixed node IPs and a MetalLB range; buy 3x M920Q; install Ubuntu Server 24.04; build the cluster (RKE2 or kubeadm, Cilium, MetalLB, Longhorn) | Planned |
| 3 | GitOps (Argo CD) and observability (kube-prometheus-stack) | Planned |
| 4 | AI apps on Kubernetes that call the Ollama API (Open WebUI, JupyterHub, MLflow) | Planned |
| 5 | GPU upgrade (RTX 3060 12GB, if the workstation PSU supports it) and the NVIDIA GPU Operator | Planned |

## Repository layout

```
.
├── README.md                      # This file: overview, inventory, roadmap
├── docs/
│   └── 01-local-ai-on-windows.md  # Phase 1 runbook
└── scripts/
    ├── Get-SystemSpecs.ps1        # Hardware and driver inventory
    └── Test-Ollama.ps1            # Health check and benchmark for the Ollama API
```

## Quick start (Phase 1)

```powershell
# 1. Check hardware and driver
.\scripts\Get-SystemSpecs.ps1

# 2. After updating the NVIDIA driver and installing Ollama (see the runbook):
ollama run llama3.2:3b

# 3. Verify the API and measure speed
.\scripts\Test-Ollama.ps1 -Model llama3.2:3b
```

## Notes

- The GTX 1060 is a Pascal GPU. NVIDIA's 580 driver branch is the last to support it, and CUDA 13 dropped it; Ollama still supports it through its CUDA 12 runner. See the runbook for details.
- The Ollama API has no authentication. Only expose it on a trusted home network.
