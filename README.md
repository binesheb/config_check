# Config Check — Surface Book 3

Non-destructive Windows PowerShell 5.1 diagnostic for evaluating the used Surface Book 3.

## Run

PowerShell as Administrator:

```powershell
irm https://github.com/binesheb/config_check/raw/refs/heads/main/irm.ps1 | iex
```

The tool checks Surface Book 3 identity, CPU, RAM, NVIDIA GPU, display, SSD, battery health/cycles, battery report, Device Manager/PnP errors, NTFS, DISM, SFC and recent critical/error events. It generates reports on the Desktop and calculates a health score, price ceiling and purchase verdict.

Physical checks remain mandatory for swelling, display lifting, touch, pixels, ports, hinge and detach/reattach.