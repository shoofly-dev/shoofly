# Steer note for Card 229 — Cross-platform support

Evan wants PC/Linux support too. Apply these rules:

## Notifications — cross-platform

In shoofly-setup multiselect, detect platform at runtime:

- darwin → label "macOS notifications", use osascript
- linux → label "Desktop notifications", use notify-send (check via `which notify-send`)
- win32 → label "Desktop notifications", use PowerShell:
  `powershell -Command "Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.MessageBox]::Show('$msg')"`

In shoofly-notify (the existing bash script), add a linux/windows branch:
- Linux: `notify-send "Shoofly" "$msg"` or fallback to echo
- Windows: the script is bash, so WSL/Git Bash users get echo fallback

## Wizard itself
shoofly-setup is Node.js — runs natively on macOS, Linux, Windows (Node >= 18).
Platform detection: `process.platform === 'darwin' | 'linux' | 'win32'`

## Smoke test
Must be platform-agnostic — no osascript calls. Just verify detection pipeline returns a result.

## Installers (install.sh)
Keep as bash/macOS for now — Windows users on WSL will work too.
Add a note in the outro: "On Linux? Use: bash <(curl -fsSL https://shoofly.dev/install-advanced.sh)"
Windows note: "On Windows? Run in WSL or Git Bash."
