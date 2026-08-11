# Android tailnet same-Wi-Fi verification

- **Date:** 2026-08-11
- **Server:** Surface Laptop 7, Windows 11 ARM64, WSL2 Ubuntu ARM64, single-node K3s
- **Client:** enrolled Android browser
- **Windows Tailscale client:** 1.98.9
- **Network:** Android and Windows on the same Wi-Fi
- **Scope:** temporary client-path validation, not a persistent ingress design

## Purpose

Verify that an enrolled Android device can use the fixed Gateway Web UI through
the private tailnet without exposing the ClusterIP inference Service or
`llama-server`. This check covers the Android browser and tailnet path. It does
not claim access from a different network.

## Preconditions

The inference and Gateway Deployments were both Ready. Windows reached the
Gateway through a localhost-only operator port-forward:

    wsl -d Ubuntu-24.04 -- kubectl -n edge-llm port-forward \
      service/inference-gateway 18080:8080 --address 127.0.0.1

`http://127.0.0.1:18080/health` returned:

    {"status":"ok"}

Windows and Android were enrolled in the same tailnet. A Tailscale peer ping
from Windows to Android completed directly in 11 ms while both used the same
Wi-Fi. The exact device IPs are environment-specific and are not stored in the
repository.

## Temporary validation relay

Tailscale Serve HTTPS could not be used because the Windows client failed to
provision its Let's Encrypt certificate. For this test only, an Administrator
PowerShell session added a Windows portproxy bound to the Windows Tailscale IP
and an inbound Firewall rule restricted to the tested Android Tailscale IP:

    $windowsTailscaleIp = tailscale ip -4
    $androidTailscaleIp = "<ANDROID_TAILSCALE_IP>"

    netsh interface portproxy add v4tov4 `
      listenaddress=$windowsTailscaleIp listenport=18080 `
      connectaddress=127.0.0.1 connectport=18080

    New-NetFirewallRule `
      -DisplayName "Edge LLM Android temporary" `
      -Direction Inbound -Action Allow -Protocol TCP `
      -LocalAddress $windowsTailscaleIp -LocalPort 18080 `
      -RemoteAddress $androidTailscaleIp -Profile Any

The Android browser used `http://<WINDOWS_TAILSCALE_IP>:18080/`. The
application protocol was HTTP and therefore did not provide browser-level TLS;
the device path remained inside Tailscale's encrypted overlay. This is an
explicit lab trade-off, not a production security design.

## Observed result

The following checks passed from the Android browser:

1. The Edge LLM Chat document loaded through the Windows Tailscale IP.
2. The UI health indicator reported `利用可能`.
3. `GET /health` returned `{"status":"ok"}`.
4. A normal chat request streamed a model response.
5. A longer generation could be stopped from the UI.

The browser screenshot showed the fixed Gateway UI and model replies. No model
switch or generation settings were exposed. The Android client reached the
Gateway only; the inference Service remained ClusterIP-only.

## HTTPS Serve failure

Before the temporary relay, Windows Tailscale Serve was configured as a
tailnet-only HTTPS reverse proxy to `http://127.0.0.1:18080`. Its configuration
and peer routing were present, but TLS handshakes stopped after ClientHello.
Gateway health on localhost remained normal.

An explicit certificate request returned HTTP 500 with a Let's Encrypt ACME
order in `invalid` state. One controlled retry created a different order and
failed with the same state. A Tailscale diagnostic report was generated and its
shareable identifier is retained outside the repository. Repeated certificate
requests were stopped to avoid unnecessary CA traffic or rate-limit risk. No
failed Serve configuration is retained as a project deployment path.

## Cleanup

The temporary Windows settings were removed from an Administrator PowerShell
session after evidence capture:

    $windowsTailscaleIp = tailscale ip -4

    netsh interface portproxy delete v4tov4 `
      listenaddress=$windowsTailscaleIp listenport=18080

    Remove-NetFirewallRule -DisplayName "Edge LLM Android temporary"

Verify cleanup and the unaffected local path:

    netsh interface portproxy show all
    Get-NetFirewallRule -DisplayName "Edge LLM Android temporary" `
      -ErrorAction SilentlyContinue
    curl.exe http://127.0.0.1:18080/health

After cleanup, the portproxy listing was empty and the named Firewall rule was
absent. `http://127.0.0.1:18080/health` continued to return
`{"status":"ok"}`.

## Remaining boundary

This result does not verify a client on another Wi-Fi, mobile network, or other
off-LAN path. It also does not validate an external PC API client, tailnet
policy changes, involuntary network loss, persistent startup, or HTTPS
termination. Those remain explicit follow-up work.
