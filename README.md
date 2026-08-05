# netpulse

`netpulse` is a minimal, read-only TCP connection monitor for Windows. It maps established connections to local processes, classifies remote addresses, checks executable signatures, and can watch for opened and closed connections.

It does not scan the network, modify processes or firewall rules, contact external services, or store connection data.

## Requirements

- Windows 10, Windows 11, or a supported Windows Server release
- Windows PowerShell 5.1 or later
- The built-in `NetTCPIP` and `Microsoft.PowerShell.Security` modules

Administrator rights are not required. Windows may hide executable details for some protected processes; those signatures appear as `Unknown`.

## Usage

Take one snapshot and exit:

```powershell
.\netpulse.ps1
```

Watch for changes, waiting five seconds between samples:

```powershell
.\netpulse.ps1 -Watch
```

Press `Ctrl+C` to stop watch mode.

If the current execution policy blocks local scripts, review `netpulse.ps1` first and run it in a one-time process without changing the user or machine policy:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\netpulse.ps1
```

## Output

| Field | Meaning |
| --- | --- |
| `Process` | Local process name, or `Unknown` if it is no longer available |
| `PID` | Owning process identifier reported by Windows |
| `Local` | Local address and port |
| `Remote` | Remote address and port |
| `Scope` | `Loopback`, `Private`, `LinkLocal`, `Public`, `Special`, or `Unknown` |
| `Signature` | Authenticode status reported by Windows |

A valid signature is not proof that software is safe, and an unsigned executable is not proof that it is malicious. `netpulse` reports evidence; it does not assign threat scores.

## Scope and limitations

- Only established TCP connections on the current computer are included.
- UDP endpoints and listening TCP ports are intentionally excluded.
- Watch mode compares samples in memory and writes no history file.
- Connections that open and close between five-second samples can be missed.
- No DNS resolution or geolocation is performed.
- Process paths can become unavailable because of permissions or process termination.

Connection output can reveal local process names and network addresses. Review it before sharing screenshots or terminal transcripts.

## License

MIT
