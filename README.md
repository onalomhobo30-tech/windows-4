# Phase 1 WinPE installer foundation

The browser shell remains the product UI prototype. This phase adds the first native deployment boundary under `installer/winpe/`:

- `Build-WinPE.ps1` creates amd64 ISO or USB media with the Microsoft ADK/WinPE tools.
- `Start-Windows4Installer.ps1` is the WinPE entry point and operator console.
- `Windows4Installer.cmd` provides a simple manual launcher.

The foundation is deliberately conservative: it inventories hardware and disks, logs every session, and keeps destructive disk preparation behind explicit confirmation. It does **not** ship Windows binaries or attempt to bypass licensing, Secure Boot, or vendor recovery controls.

See [`installer/winpe/README.md`](installer/winpe/README.md) for prerequisites, commands, and safety notes.
