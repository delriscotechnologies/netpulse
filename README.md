<h1 align="center">Netpulse</h1>

<p align="center">
  A compact, read-only TCP connection monitor for Windows.
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> &middot;
  <a href="#modes">Modes</a> &middot;
  <a href="#output">Output</a> &middot;
  <a href="#how-it-works">How It Works</a> &middot;
  <a href="#scope-and-safeguards">Scope</a> &middot;
  <a href="SECURITY.md">Security</a>
</p>

---

Netpulse turns the local Windows TCP table into a clear process-level view. It shows established connections, their owning processes, remote-address scope, and the Authenticode status of each available executable.

Run it once for a snapshot or keep it open to see connections appear and disappear. It does not scan the network, contact external services, modify the firewall, stop processes, or store connection history.

> Connection output can reveal local process names and network addresses. Review it before sharing screenshots or terminal transcripts.

## Quick Start

Netpulse requires Windows PowerShell 5.1 or later and the built-in `NetTCPIP` and `Microsoft.PowerShell.Security` modules. Administrator rights are not required.

Clone the repository and take one snapshot:

```powershell
git clone https://github.com/delriscotechnologies/netpulse.git
cd netpulse
.\netpulse.ps1
```

If the execution policy blocks local scripts, review the source first and use a process-only bypass that does not change the user or machine policy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\netpulse.ps1
```

## Modes

| Command | Behavior |
| --- | --- |
| `.\netpulse.ps1` | Display the current established TCP connections and exit |
| `.\netpulse.ps1 -Watch` | Compare samples every five seconds and report changes |

Watch mode marks new connections as `OPENED` and missing connections as `CLOSED`. Press `Ctrl+C` to stop it.

## Output

The terminal report stays intentionally small:

```text
 _ __   ___| |_ _ __  _   _| |___  ___
| '_ \ / _ \ __| '_ \| | | | / __|/ _ \
| | | |  __/ |_| |_) | |_| | \__ \  __/
|_| |_|\___|\__| .__/ \__,_|_|___/\___|
               |_|
LOCAL TCP CONNECTION MONITOR
Del Risco Technologies  |  v1.0.0
-----------------------------------------
 Mode           : SNAPSHOT
 Connections    : 12
-----------------------------------------
```

| Field | Meaning |
| --- | --- |
| `Process` | Local process name, or `Unknown` when it is unavailable |
| `PID` | Owning process identifier reported by Windows |
| `Local` | Local address and port |
| `Remote` | Remote address and port |
| `Scope` | `Loopback`, `Private`, `LinkLocal`, `Public`, `Special`, or `Unknown` |
| `Signature` | Authenticode status reported by Windows |

`Scope` is a coarse address category, not a trust decision. A valid signature does not prove software is safe, and an unsigned executable is not automatically malicious.

## How It Works

Each sample follows four steps:

1. Read the local Windows TCP connection table and retain established connections.
2. Map each connection to its owning PID and process name.
3. Classify the remote address and check the executable's Authenticode status when its path is available.
4. Sort the result into a compact terminal table.

Watch mode keeps the previous sample in memory and compares connection keys made from the PID, local endpoint, and remote endpoint. It writes only the differences and creates no history file.

## Scope and Safeguards

Netpulse is deliberately limited:

- established TCP connections on the current computer only
- no UDP endpoints or listening TCP ports
- no packet capture, DNS resolution, geolocation, or traffic inspection
- no network scanning or external requests
- no process, firewall, registry, or system configuration changes
- no exported reports, telemetry, configuration files, or persistent history
- protected or short-lived process details may appear as `Unknown`
- connections that open and close between five-second samples can be missed

This repository does not yet include automated tests or CI. Validate the script on a non-production Windows system before relying on its output.

Netpulse provides local connection context; it is not an intrusion-detection system and does not assign threat scores.

See [SECURITY.md](SECURITY.md) for the trust boundary, privacy guidance, and vulnerability-reporting process.

## License

Netpulse source code is available under the [MIT License](LICENSE).
