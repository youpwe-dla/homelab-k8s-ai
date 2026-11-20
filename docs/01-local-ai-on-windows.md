# Phase 1: Local AI on the Windows workstation

**Author:** Manny Bate ([@youpwe-dla](https://github.com/youpwe-dla)) · **Built:** 2026-11-19 to 2026-11-20

Run open LLMs locally on the existing workstation's NVIDIA GTX 1060 6GB with [Ollama](https://ollama.com), and expose the API to the home network so later Kubernetes workloads can use it.

**Host:** `ai-workstation` (role name; Windows hostname `DESKTOP-TLPE94P`) · Windows 10 Home x64 (build 19045) · Intel Xeon E3-1275 v5 (4C/8T) · 16 GB RAM · NVIDIA GTX 1060 6GB · 512 GB SSD + 1 TB HDD

## Contents

1. [Record the baseline](#1-record-the-baseline)
2. [Update the NVIDIA driver](#2-update-the-nvidia-driver)
3. [Install Ollama](#3-install-ollama)
4. [Run a first model and confirm it uses the GPU](#4-run-a-first-model-and-confirm-it-uses-the-gpu)
5. [Benchmark](#5-benchmark)
6. [Expose the API on the home network](#6-expose-the-api-on-the-home-network)
7. [Troubleshooting](#7-troubleshooting)
8. [Build log](#8-build-log): what actually happened, including problems and fixes
9. [Results log](#9-results-log)

---

## Background: why the driver matters

The GTX 1060 is a **Pascal** GPU (CUDA compute capability 6.1).

- NVIDIA's **580 driver branch is the last** to support Maxwell, Pascal and Volta GPUs. Newer branches will not install on this card.
- **CUDA 13 dropped Pascal.** Ollama still ships a CUDA 12 runner alongside the CUDA 13 one and picks the right one automatically, so stock Ollama works on this card.
- Ollama requires **driver 570 or newer** for compute 5.0 to 6.2 cards.

The baseline driver on this machine was **566.03**, too old, so it must be updated first.

> **Reading the Windows driver version:** Windows reports NVIDIA drivers as `32.0.15.6603`. The NVIDIA version is the last five digits with a dot before the final two: `…15.6603` → `56603` → `566.03`. A 580-series driver appears as something like `32.0.15.80xx` (e.g. 580.88 → `32.0.15.8088`).

## 1. Record the baseline

From the repo root in PowerShell:

```powershell
# Allow local scripts to run in this session only
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

.\scripts\Get-SystemSpecs.ps1 -OutFile .\docs\specs-before.md
```

Baseline (2026-11-19), collected with the equivalent manual commands (`Get-CimInstance Win32_Processor`, `Win32_ComputerSystem`, `Win32_VideoController`, `nvidia-smi`, `Get-PhysicalDisk`). The script automates the same queries:

| Item | Value |
|---|---|
| CPU | Intel(R) Xeon(R) CPU E3-1275 v5 @ 3.60GHz, 4 cores |
| RAM | 16 GB |
| GPU | NVIDIA GeForce GTX 1060 6GB, 6144 MiB |
| Driver | 32.0.15.6603 (NVIDIA 566.03) |
| Disks | Patriot P210 512GB SSD (477 GB), ST1000DM010 HDD (932 GB) |

## 2. Update the NVIDIA driver

1. Go to the [NVIDIA driver download page](https://www.nvidia.com/en-us/drivers/).
2. Select **GeForce → GeForce 10 Series → GeForce GTX 1060 → your Windows version**, then search.
3. Download the newest driver offered. For a GTX 10-series card this is a **580.xx** release. Either the Game Ready or the Studio driver works.
4. Run the installer and choose **Custom (Advanced) → Perform a clean installation**.
5. **Restart** Windows.
6. Verify:

```powershell
nvidia-smi
```

Expected: `Driver Version: 580.xx`. The header may also show `CUDA Version: 13.0`. That is only the highest CUDA version the driver supports; Ollama still uses its CUDA 12 runner on this card.

**Result (2026-11-19):** installed **580.97** (graphics driver and HD Audio only; NVIDIA App not installed; clean installation).

| Item | Before | After |
|---|---|---|
| Driver | 566.03 | **580.97** |
| CUDA (max supported by driver) | n/a | 13.0 |
| VRAM in use at idle | n/a | 688 MiB of 6144 MiB (Windows desktop, browsers) |

> **VRAM note:** this GPU also drives the desktop, so about 0.7 GB is already in use by Windows and open apps, leaving about 5.4 GB for models. Close browsers before loading 8B models.

## 3. Install Ollama

Install with winget (or download the installer from [ollama.com/download](https://ollama.com/download)):

```powershell
winget install Ollama.Ollama
```

This is the form that worked on this machine (see the [Build log](#8-build-log)). If it can't find the package, try `winget install --id Ollama.Ollama -e --source winget`, or download `OllamaSetup.exe` from [ollama.com/download/windows](https://ollama.com/download/windows).

> With `-e` (exact match) the package ID is **case-sensitive**: `Ollama.Ollama` works, `ollama.ollama` returns "No package found". The first winget run may also ask you to accept the `msstore` source agreements. Use `winget search ollama` to confirm the ID; install **Ollama** (`Ollama.Ollama`), not `Ollama.Ollama.Portable` or the third-party apps tagged `ollama`.

Close and reopen PowerShell, then verify:

```powershell
ollama --version
```

Ollama runs as a background app (llama icon in the system tray) and serves its API at `http://localhost:11434`.

On first launch the Ollama app shows a welcome screen: click **Continue**. Signing in is optional and only needed for Ollama's cloud models. **This lab uses local models only.** Avoid model tags containing `cloud`, which run on Ollama's servers instead of your GPU.

**Optional, model storage location:** models are stored under `%USERPROFILE%\.ollama\models` by default. Keep them on the SSD. To move them, set a user environment variable and restart Ollama:

```powershell
setx OLLAMA_MODELS "D:\ollama\models"
```

## 4. Run a first model and confirm it uses the GPU

Start with a small model that fits comfortably in 6 GB of VRAM:

```powershell
ollama run llama3.2:3b
```

Type a question, then `/bye` to exit. In a second PowerShell window, while a model is loaded:

```powershell
ollama ps
```

Check the **PROCESSOR** column:

- `100% GPU`: the whole model is in VRAM. On this machine `llama3.2:3b` loads as 2.6 GB at 100% GPU with a 4096-token context.
- A split such as `40%/60% CPU/GPU`: the model or its context is too big for 6 GB and part of it runs on the CPU, which is much slower. Use a smaller model or a shorter context.

Also confirm with `nvidia-smi` that `ollama` appears in the process list and VRAM use has gone up.

### Models that suit a 6 GB card

| Model | Command | Approx. size | Notes |
|---|---|---|---|
| Llama 3.2 3B | `ollama run llama3.2:3b` | ~2 GB | Fast; good first test |
| Qwen 3 4B | `ollama run qwen3:4b` | ~2.5 GB | Strong for its size (not yet tested here) |
| Llama 3.1 8B (Q4) | `ollama run llama3.1:8b` | ~4.9 GB | Best quality of the three; on this machine it spills 20–25% to the CPU (see below) |

Check exact tags and sizes in the [Ollama model library](https://ollama.com/library) before pulling.

If an 8B model spills to the CPU, shrink the context window inside the chat session:

```
/set parameter num_ctx 2048
```

**Measured on this machine:** `llama3.1:8b` still spilled at 2048 context (5.4 GB, 20%/80% CPU/GPU, 15.12 tokens/s), because this GPU also drives the Windows desktop and background apps hold ~0.7 GB of VRAM. On a 6 GB card that runs the display, treat 3B-class models as the "fits fully" tier (4B expected to fit, not yet tested) and 8B as "works, but partly on CPU".

## 5. Benchmark

Get per-response timings with `--verbose`:

```powershell
ollama run llama3.2:3b --verbose "Explain what Kubernetes does in three sentences."
```

The **eval rate** line (tokens/s) is the generation speed. Ignore the **prompt eval rate** on repeat runs: Ollama caches the prompt, so only a few new tokens are processed and the rate looks artificially low.

The repo script calls the API and reports the same timings:

```powershell
.\scripts\Test-Ollama.ps1 -Model llama3.2:3b
.\scripts\Test-Ollama.ps1 -Model llama3.1:8b
```

Record the results in the [Results log](#9-results-log).

## 6. Expose the API on the home network

By default Ollama listens only on `localhost`. To let the Kubernetes nodes (Phase 2+) call it:

1. Make Ollama listen on all interfaces:

   ```powershell
   setx OLLAMA_HOST "0.0.0.0:11434"
   ```

2. **Quit Ollama** from the system tray icon and start it again from the Start menu, so it picks up the variable.

3. Allow the port through Windows Firewall, **local subnet only**. Run in an **Administrator** PowerShell:

   ```powershell
   New-NetFirewallRule -DisplayName "Ollama API (LAN only)" `
     -Direction Inbound -Protocol TCP -LocalPort 11434 `
     -RemoteAddress LocalSubnet -Action Allow
   ```

4. Find this machine's IP address:

   ```powershell
   Get-NetIPAddress -AddressFamily IPv4 |
     Where-Object { $_.InterfaceAlias -notmatch 'Loopback|vEthernet' } |
     Select-Object InterfaceAlias, IPAddress
   ```

5. Give it a fixed address: create a **DHCP reservation** in the router for this PC, so the address doesn't change.

   **Spectrum routers** can't be configured by logging in to the router. Use the **My Spectrum app**: Services → Router → Advanced Settings → Port Forwarding & IP Reservations → select the PC → turn on **Reserve IP Address**. Spectrum reserves the address the device has now; you can't type a different one. Do **not** add a port assignment, which would expose Ollama to the internet.

   **On this lab's Spectrum router the reservation option was not available** in either the website or the app (see the [Build log](#8-build-log)). The workstation stays on DHCP for now; a dedicated router is planned for Phase 2.

6. Test from another device on the network:

   ```bash
   curl http://<workstation-ip>:11434/api/tags
   ```

   or from this machine with the repo script:

   ```powershell
   .\scripts\Test-Ollama.ps1 -BaseUrl http://<workstation-ip>:11434 -Model llama3.2:3b
   ```

> **Security:** the Ollama API has **no authentication**. Anyone who can reach port 11434 can use it. Keep the firewall rule scoped to `LocalSubnet`, never port-forward 11434 on the router, and put an authenticating proxy in front of it if it ever needs wider access.

To undo: `Remove-NetFirewallRule -DisplayName "Ollama API (LAN only)"` and `setx OLLAMA_HOST "127.0.0.1:11434"`, then restart Ollama.

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `ollama ps` shows `100% CPU` | Driver too old, or GPU not detected | Confirm `nvidia-smi` shows a 580.xx driver; update Ollama; restart |
| A model runs partly on CPU (`x%/y% CPU/GPU`) | Model or context too large for 6 GB | Use a smaller model or quantization; `/set parameter num_ctx 2048` |
| NVIDIA installer refuses a newer driver | Card not supported after the 580 branch | Install the newest **580.xx** release for GTX 10 series |
| `netstat` still shows `127.0.0.1:11434` after setting `OLLAMA_HOST` | Ollama didn't restart with the new variable (a background process kept running), or the app's own network setting is off | Check `[Environment]::GetEnvironmentVariable('OLLAMA_HOST','User')`; stop all Ollama processes (`Get-Process -Name 'ollama*' \| Stop-Process -Force`); start Ollama from the Start menu; or turn on **Settings → Expose Ollama to the network** in the app |
| `curl` from another machine times out | Firewall or listen address | Check the firewall rule exists; confirm `OLLAMA_HOST` is set and Ollama was restarted; `netstat -ano \| findstr 11434` should show `0.0.0.0:11434` |
| `winget install` says "No package found matching input criteria" | With `-e` the ID is case-sensitive (`Ollama.Ollama`, not `ollama.ollama`), or the winget source is stale | `winget install --id Ollama.Ollama -e --source winget`; or `winget source update` then `winget search ollama`; or use the installer from ollama.com/download/windows |
| `winget search ollama` finds the package but `winget install` still says "No package found" | winget client quirk with `--id`/`-e`/`--source` | `winget install Ollama.Ollama` (no flags), or download and run the installer: `Invoke-WebRequest -Uri https://ollama.com/download/OllamaSetup.exe -OutFile "$env:USERPROFILE\Downloads\OllamaSetup.exe"` then `Start-Process "$env:USERPROFILE\Downloads\OllamaSetup.exe"` |
| `New-NetFirewallRule : Access is denied` | Command run in a non-admin PowerShell | Right-click PowerShell → **Run as administrator** (prompt shows `C:\Windows\system32>`) and run it there |
| `ollama` not found after install | PATH not refreshed in the window that was open during install | Close and reopen PowerShell, or reload PATH in place: `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')` |
| Very slow first response | Model loading into VRAM | Normal on first call; later calls are faster while the model stays loaded |

## 8. Build log

What actually happened during the Phase 1 build, in order, including problems and fixes.

| Date | Step | What happened | Fix / result |
|---|---|---|---|
| 2026-11-19 | Baseline | Xeon E3-1275 v5, 16 GB RAM, GTX 1060 6GB, driver 566.03 | Driver below Ollama's 570 minimum for Pascal cards: update required |
| 2026-11-19 | Driver download | nvidia.com manual search (GeForce 10 Series, GTX 1060) offered **580.97** | Correct branch: 580 is the last to support Pascal |
| 2026-11-19 | Driver install | Installer offered "Driver + NVIDIA App" or "Driver only" | Chose **driver only**; Custom → clean installation; kept HD Audio; PhysX already current |
| 2026-11-19 | Driver verify | `nvidia-smi`: driver 580.97, CUDA 13.0, 688 MiB of 6144 MiB in use at idle | Success. About 5.4 GB VRAM free for models |
| 2026-11-19 | Ollama install (attempt 1) | `winget install --id ollama.ollama -e` → accepted `msstore` source agreements → "No package found matching input criteria" (twice) | Likely cause: `-e` makes the ID case-sensitive |
| 2026-11-19 | Ollama install (attempt 2) | `winget source update`, then `winget search ollama` listed **Ollama** `Ollama.Ollama` **0.40.16** | Install with `winget install --id Ollama.Ollama -e --source winget` |
| 2026-11-19 | Ollama install (attempt 3) | Install command still returned "No package found matching input criteria", although `winget search` found the package; `ollama --version` → "not recognized" (nothing installed) | Retry without strict flags (`winget install Ollama.Ollama`), or use the official installer `OllamaSetup.exe` from ollama.com/download/windows |
| 2026-11-19 | Ollama install (attempt 4) | `winget install Ollama.Ollama` (no flags): found 0.40.16, downloaded the 1.73 GB installer, hash verified, "Successfully installed". `ollama --version` in the **same** window → "not recognized" | **Success.** The open window had the old PATH: open a new PowerShell window, or reload PATH in place (see Troubleshooting) |
| 2026-11-19 | Ollama first launch | The Ollama desktop app opened a "Welcome to Ollama!" screen | Clicked Continue; no sign-in needed for local models. Models tagged `cloud` run on Ollama's servers, not locally, so they are avoided in this lab |
| 2026-11-19 | Ollama verify | Reloaded PATH in the open window, then `ollama --version` → `ollama version is 0.40.16` | **Success.** Ollama 0.40.16 installed and on PATH |
| 2026-11-19 | First model pull | `ollama run llama3.2:3b` → 2.0 GB download at ~14 MB/s, sha256 verified, "success". The terminal printed many repeated "pulling manifest" lines before the progress bar | **Success.** The repeated lines are cosmetic (progress redraw in Windows PowerShell) |
| 2026-11-19 | First prompt | Asked "Explain what Kubernetes does in three sentences" and got a correct three-sentence answer | **Success.** Local LLM working |
| 2026-11-19 | GPU check | `ollama ps`: `llama3.2:3b`, size 2.6 GB, **PROCESSOR 100% GPU**, context 4096, runner `llamacpp`, unloads 5 minutes after last use | **Success.** The model runs entirely on the GTX 1060 |
| 2026-11-19 | Benchmark 3B | `ollama run llama3.2:3b --verbose "Explain what Kubernetes does in three sentences."` → eval rate **43.64 tokens/s** (102 tokens in 2.34 s), total 2.58 s. Prompt: 34 tokens, 28 served from cache, so the prompt rate (26 tokens/s) only reflects 6 new tokens | **Success.** Fast enough for interactive chat |
| 2026-11-19 | 8B model pull | `ollama run llama3.1:8b --verbose ...` → 4.9 GB download at ~7.6 MB/s (about 10 min). Meanwhile `ollama ps` still showed only `llama3.2:3b` (100% GPU), counting down to unload | Download completed (4.9 GB, sha256 verified). The 3B model unloaded after its 5-minute timer, freeing VRAM |
| 2026-11-19 | Benchmark 8B | Correct three-sentence answer. Eval rate **13.70 tokens/s** (108 tokens in 7.88 s), load 5.37 s, total 13.72 s. `ollama ps`: `llama3.1:8b`, size **5.6 GB**, **PROCESSOR 25%/75% CPU/GPU**, context 4096 | **Partial spill.** 5.6 GB needed vs ~5.4 GB free (the desktop uses ~0.7 GB), so 25% runs on the CPU and generation is about 3x slower than the 3B. Next: retry with `num_ctx 2048` and browsers closed |
| 2026-11-19 | 8B retry, smaller context | No browser windows open, but `nvidia-smi` still lists background GPU users (Edge WebView2, Copilot, Phone Link, NordVPN, NVIDIA Share, Windows shell and other desktop apps). In `ollama run llama3.1:8b --verbose`: `/set parameter num_ctx 2048`. Result: size **5.4 GB**, **20%/80% CPU/GPU**, eval rate **15.12 tokens/s**. `nvidia-smi` with the model loaded: 4745 MiB of 6144 MiB used, GPU at 50 °C | **Improved slightly, still spills.** An 8B Q4 model does not fit fully in 6 GB on a GPU that also drives the Windows desktop. Decision: use 3B-class models for speed (4B to be tested) and 8B (~15 tokens/s) when quality matters; a 12 GB GPU (RTX 3060) removes the limit |
| 2026-11-19 | Network: listen address | `setx OLLAMA_HOST "0.0.0.0:11434"`, quit Ollama from the tray, reopened it (opens to the app's "Apps" integrations page) | Ollama restarted |
| 2026-11-19 | Network: firewall (attempt 1) | `New-NetFirewallRule ...` in a normal PowerShell window → "Access is denied" (Windows System Error 5) | Must run in **Administrator** PowerShell: the admin window's prompt shows `C:\Windows\system32>`, a normal one shows `C:\Users\<name>>` |
| 2026-11-19 | Network: firewall (attempt 2) | Same command in an Administrator PowerShell (ISE) → rule "Ollama API (LAN only)" created: Enabled True, Direction Inbound, Action Allow, Profile Any, PrimaryStatus OK | **Success.** Scoped to `LocalSubnet`, so only devices on the home network can connect |
| 2026-11-19 | Network: verify | `netstat -ano \| findstr 11434` → `127.0.0.1:11434 LISTENING` (PID 4328): still localhost only. LAN IP is **Wi-Fi 192.168.1.240** (Ethernet shows a 169.254.x.x self-assigned address, so it isn't in use; NordVPN adapters present, NordLynx 10.5.0.2) | **Not yet exposed.** `OLLAMA_HOST` was not picked up: verify the variable, fully stop all Ollama processes, restart. Also check the app's "Expose Ollama to the network" setting |
| 2026-11-19 | Network: fix | `OLLAMA_HOST` was saved correctly (`0.0.0.0:11434`). Stopped all Ollama processes (`Get-Process -Name 'ollama*' \| Stop-Process -Force`). Typing `ollama` alone opened Ollama's interactive menu instead of starting the server: exited with Ctrl+C, then started **Ollama from the Start menu** | Start-menu launch reads the saved variable; a PowerShell window opened before `setx` does not |
| 2026-11-19 | Network: verify (2) | `netstat -ano \| findstr 11434` → **`0.0.0.0:11434 LISTENING`** and `[::]:11434 LISTENING` (PID 11392) | **Success.** Ollama now accepts connections from the network (IPv4 and IPv6) |
| 2026-11-19 | Network: LAN test | Phone on the same Wi-Fi opened `http://192.168.1.240:11434` → **"Ollama is running"** | **Success. Phase 1 complete:** the local LLM API is reachable from other devices on the home network. The browser marks the page "not secure" (plain HTTP, expected on a LAN) and may offer to download a 17-byte `document.txt`, which is the same plain-text response; no need to save it |
| 2026-11-19 | Network: API test | `Invoke-RestMethod http://192.168.1.240:11434/api/tags` listed `llama3.1:8b` (4,920,753,328 bytes) and `llama3.2:3b` (2,019,393,189 bytes) | **Success.** The REST API answers on the LAN address |
| 2026-11-20 | Fixed IP: find device | Router is **Spectrum-managed** (no direct admin login). Spectrum website → Your WiFi Network → device Details: Device Name "Windows", Hostname `DESKTOP-TLPE94P`, IP `192.168.1.240`. The website has no reservation option | Reserve the IP in the **My Spectrum app**: Services → Router → Advanced Settings → Port Forwarding & IP Reservations → select device → Reserve IP Address. Spectrum can only reserve the device's current address. **No port forwarding:** the Ollama API has no authentication |
| 2026-11-20 | Fixed IP: Spectrum app | **No IP reservation option** in the Spectrum website or the My Spectrum app for this router model | Open issue. Options: (a) keep DHCP, since Spectrum usually re-issues the same address to the same device; verify after reboots; (b) static IP set in Windows; (c) own router in Phase 2, which is needed anyway for Kubernetes LoadBalancer IPs (MetalLB) |
| 2026-11-20 | Fixed IP: decision | Chose **(b) static IP in Windows** for the Wi-Fi adapter, keeping the current address 192.168.1.240. Known risk: the Spectrum router doesn't know about it and could hand the same address to another device | In progress. Collect current gateway and DNS first |
| 2026-11-20 | Fixed IP: current settings | `Format-List` on `Get-NetIPConfiguration` printed raw CIM objects instead of values. Re-queried with `$c.IPv4DefaultGateway.NextHop` and `$c.DNSServer ... .ServerAddresses` → **Gateway 192.168.1.1**, **DNS 192.168.1.1** | Values for the static config: IP 192.168.1.240/24, gateway 192.168.1.1, DNS 192.168.1.1 + 1.1.1.1 |
| 2026-11-20 | Fixed IP: final decision | Decided **not** to set a static IP in Windows (avoids an address conflict with the Spectrum router's DHCP). Reverted to **option (a)**: keep DHCP and check the address after reboots with `(Get-NetIPConfiguration -InterfaceAlias "Wi-Fi").IPv4Address.IPAddress` | **Closed for Phase 1.** Long-term fix: own router in Phase 2 (fixed node IPs and a MetalLB address range). The static values above are kept for reference |
| 2026-11-20 | Scripts verified | `Get-SystemSpecs.ps1` (after `Set-ExecutionPolicy -Scope Process Bypass`) reported Windows 10 Home build 19045, Xeon E3-1275 v5 4C/8T, 16 GB, GTX 1060 6GB with driver `32.0.15.8097` correctly converted to **580.97**, both disks, Ollama 0.40.16. `Test-Ollama.ps1 -Model llama3.2:3b`: API reachable, 2 models listed, load 14.33 s (cold start), prompt 34 tokens at 232.2 tokens/s, **86 output tokens at 45.4 tokens/s**, total 16.45 s, `ollama ps` 100% GPU | **Success.** Both repo scripts run as published on Windows PowerShell 5.1 |

## 9. Results log

| Date | Model | Quantization | Context | Processor (`ollama ps`) | Eval rate (tokens/s) | Notes |
|---|---|---|---|---|---|---|
| 2026-11-20 | llama3.2:3b | default (Q4) | 4096 | 100% GPU (2.6 GB loaded) | **45.4** | Measured with `Test-Ollama.ps1`; cold start (load 14.33 s); 86 output tokens; prompt 232.2 tokens/s |
| 2026-11-19 | llama3.2:3b | default (Q4) | 4096 | 100% GPU (2.6 GB loaded) | **43.64** | 102 output tokens in 2.34 s; total 2.58 s; model already loaded (load 3.7 ms); answers correct |
| 2026-11-19 | llama3.1:8b | default (Q4) | 4096 | 25%/75% CPU/GPU (5.6 GB loaded) | **13.70** | Spills to CPU; 108 tokens in 7.88 s; load 5.37 s |
| 2026-11-19 | llama3.1:8b | default (Q4) | 2048 | 20%/80% CPU/GPU (5.4 GB loaded) | **15.12** | Still spills; 97 tokens in 6.42 s; load 6.33 s. About 10% faster than with 4096 context |
| | qwen3:4b | default (Q4) | default | | | Not yet tested |

## Next: Phase 2

Build the Kubernetes cluster on three Lenovo M920Q mini PCs, then point cluster workloads (Open WebUI, notebooks) at `http://<workstation-ip>:11434`. See the roadmap in the [README](../README.md).

## References

- [Ollama hardware support (GPU)](https://docs.ollama.com/gpu)
- [Ollama FAQ: exposing Ollama on the network, model location](https://docs.ollama.com/faq)
- [NVIDIA driver downloads](https://www.nvidia.com/en-us/drivers/)
- [Pascal GPUs after CUDA 13 (LocalAIMaster)](https://localaimaster.com/blog/pascal-gpus-after-cuda-13)
- [Which LLM on a GTX 1060 6GB (BestLLMfor)](https://bestllmfor.com/guide/llm-gtx-1060/)
