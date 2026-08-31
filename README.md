<h1 align="center">Netpulse</h1>

<p align="center">
  A compact, read-only TCP connection monitor for Windows.
</p>

---

Netpulse shows established local TCP connections, their owning processes, remote-address scope, and Authenticode status.

Run it once for a snapshot or use watch mode to see connections open and close.

## Install

You need Windows PowerShell 5.1 or later. Administrator rights are not required.

```powershell
git clone https://github.com/delriscotechnologies/netpulse.git
cd netpulse
.\netpulse.ps1
```

## What it does

1. Reads established TCP connections on the local computer.
2. Maps connections to their owning process and PID.
3. Classifies remote addresses as loopback, link-local, private, special-purpose, or external.
4. Checks Authenticode status when the executable path is available.
5. Optionally watches for opened and closed connections.

## Output

```text
NETPULSE | LOCAL TCP CONNECTION MONITOR
Mode: SNAPSHOT | Connections: 4
-----------------------------------------

Process   PID   Local                 Remote                 Scope   Signature
-------   ---   -----                 ------                 -----   ---------
chrome    8420  192.168.1.25:52143    203.0.113.10:443       Special  Valid
code      9116  192.168.1.25:52201    198.51.100.24:443      Special  Valid
svchost   1540  192.168.1.25:49722    203.0.113.53:443       Special  Valid
discord   6312  192.168.1.25:52180    198.51.100.80:443      Special  Valid
```

| Field | Description |
| --- | --- |
| Process | Owning process name |
| PID | Process identifier |
| Local | Local address and port |
| Remote | Remote address and port |
| Scope | Remote address category: `Loopback`, `LinkLocal`, `Private`, `Special`, or `External` |
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
- `External` means outside the recognized local or special ranges; it does not guarantee public routability.
- Address scope and signature status are context, not trust or threat verdicts.

See [SECURITY.md](SECURITY.md) for security guidance.

## License

Netpulse is available under the [MIT License](LICENSE).
