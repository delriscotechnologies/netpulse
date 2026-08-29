<h1 align="center">Netpulse</h1>

<p align="center">
  A compact, read-only TCP connection monitor for Windows.
</p>

---

Netpulse shows established local TCP connections, their owning processes, remote-address scope, and Authenticode status.

Run it once for a snapshot or use watch mode to see connections open and close.

## Install

You need Windows and PowerShell. Administrator rights are not required.

```powershell
git clone https://github.com/delriscotechnologies/netpulse.git
cd netpulse
.\netpulse.ps1
```

## What it does

1. Reads established TCP connections on the local computer.
2. Maps connections to their owning process and PID.
3. Classifies the remote address scope.
4. Checks Authenticode status when the executable path is available.
5. Optionally watches for opened and closed connections.

## Output

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
 Connections    : 4
-----------------------------------------

Process   PID   Local                 Remote                 Scope   Signature
-------   ---   -----                 ------                 -----   ---------
chrome    8420  192.168.1.25:52143    203.0.113.10:443       Public  Valid
code      9116  192.168.1.25:52201    198.51.100.24:443      Public  Valid
svchost   1540  192.168.1.25:49722    203.0.113.53:443       Public  Valid
discord   6312  192.168.1.25:52180    198.51.100.80:443      Public  Valid
```

| Field | Description |
| --- | --- |
| Process | Owning process name |
| PID | Process identifier |
| Local | Local address and port |
| Remote | Remote address and port |
| Scope | Remote address category |
| Signature | Authenticode status |

## Demo

Take one snapshot:

```powershell
.\netpulse.ps1
```

Watch for changes:

```powershell
.\netpulse.ps1 -Watch
```

Press Ctrl+C to stop watch mode.

## Scope and limits

- Established TCP connections on the current computer only.
- No UDP monitoring, packet capture, DNS resolution, geolocation, or network scanning.
- Does not modify processes, firewall rules, registry settings, or system configuration.
- Does not store persistent connection history.
- Short-lived connections between samples can be missed.
- Address scope and signature status are context, not trust or threat verdicts.

See [SECURITY.md](SECURITY.md) for security guidance.

## License

Netpulse is available under the [MIT License](LICENSE).
