# claude-pod for PowerShell (native Windows)

> PowerShell port of [`claude-pod`](../README.md): a Docker sandbox for the Claude Code CLI. Runs Claude against one project folder — including with `--dangerously-skip-permissions` — while the rest of your Windows profile, SSH keys, and other projects stay invisible to the container. Unofficial.

This folder contains native Windows equivalents of the bash scripts in the repo root. The security model, login flow, and behavior are the same as the bash version — see the [main README](../README.md) for the full threat model and the details of what is and isn't isolated. This document covers only what differs on Windows.

| Bash (repo root) | PowerShell (this folder) |
|---|---|
| `claude-pod` | `claude-pod.ps1` |
| `install.sh` | `install.ps1` |
| `uninstall.sh` | `uninstall.ps1` |
| `Dockerfile` | `Dockerfile` (own copy, see [Customizing the image](#customizing-the-image)) |

## TL;DR

```powershell
# Clone this repo once, anywhere you like (C:\tools\claude-pod is just an example)
git clone https://github.com/ebutusov/claude-pod.git C:\tools\claude-pod

# Build the image (once) — runs from anywhere, no cd needed
C:\tools\claude-pod\powershell\install.ps1

# cd into your project, then launch Claude
cd C:\projects\your-project
C:\tools\claude-pod\powershell\claude-pod.ps1 claude --dangerously-skip-permissions

# Forgot a command later? Print a copy-pastable cheatsheet
C:\tools\claude-pod\powershell\claude-pod.ps1 --help
```

## Requirements

- **Docker Desktop for Windows in Linux-containers mode** (WSL2 backend recommended).
- **Windows PowerShell 5.1 or PowerShell 7+.** Nothing else — no Node.js, npm, or `claude` on the host.

If scripts are blocked by your execution policy, run them with:

```powershell
powershell -ExecutionPolicy Bypass -File C:\tools\claude-pod\powershell\claude-pod.ps1
```

## Usage

### Running

`cd` into the project first — the current folder is what gets mounted:

```powershell
cd C:\projects\anything
C:\tools\claude-pod\powershell\claude-pod.ps1
```

You land in a bash shell inside the container with `claude` on `PATH`. Anything you pass is run inside the container instead of bash:

```powershell
C:\tools\claude-pod\powershell\claude-pod.ps1 claude --dangerously-skip-permissions
```

Type `exit` to leave the container. On first launch Claude prints a login URL; open it in your host browser, complete the login, and paste the code back. The session persists in `%USERPROFILE%\.claude-pod\`.

### Shortcut function

Add a function to your PowerShell profile (`notepad $PROFILE`) so you don't need the full path:

```powershell
function claude-pod { & 'C:\tools\claude-pod\powershell\claude-pod.ps1' @args }
```

Then just `claude-pod` or `claude-pod claude --dangerously-skip-permissions`.

### Options

Options are environment variables, so set them in the session before running (PowerShell has no `VAR=value command` prefix syntax):

```powershell
# Publish ports (always bound to 127.0.0.1 on the host)
$env:PORTS = '3000 5173'          # PORT or HOST:CONTAINER, space-separated
claude-pod

# Cut all networking (mutually exclusive with PORTS; Claude itself can't reach Anthropic this way)
$env:NET = 'none'

# Resource limits (PIDS defaults to 4096; MEMORY and CPUS have no default)
$env:MEMORY = '4g'; $env:CPUS = '2'; $env:PIDS = '512'

# Override the container user (default 1000:1000)
$env:CLAUDE_POD_USER = '1000:1000'
```

Variables stay set for the rest of the session. Clear one with `Remove-Item Env:PORTS`. As in the bash version, bind dev servers to `0.0.0.0` inside the container, otherwise the published port is unreachable from your browser (see [Exposing ports](../README.md#exposing-ports)).

### Updating or pinning the Claude Code version

```powershell
C:\tools\claude-pod\powershell\install.ps1                      # latest, bypasses the npm cache layer

$env:CLAUDE_CODE_VERSION = '2.0.0'; C:\tools\claude-pod\powershell\install.ps1   # pinned
```

### Customizing the image

`powershell\Dockerfile` is a separate copy from the root `Dockerfile`. It differs in two ways: the base is the full `node:24` image (not `node:24-slim`) and it additionally installs `python3`. Edit it and re-run `install.ps1` to add your own toolchains.

### Uninstall

```powershell
C:\tools\claude-pod\powershell\uninstall.ps1
```

After confirmation, removes the `claude-pod` image and `%USERPROFILE%\.claude-pod\` (auth + session history). It does not touch the base image, Docker build cache, this repo, or your `$PROFILE` — remove the shortcut function yourself.

## Differences from the bash version

- **Path mapping.** The container is Linux, so the project at `C:\Users\me\proj` is mounted at `/c/Users/me/proj` (same convention as Git Bash). Paths in Claude's output and tool results use this form. The mount uses `--mount` rather than `-v`, because the drive-letter colon makes `-v SRC:DST` ambiguous.
- **Unsupported paths.** UNC paths (`\\server\share`) and paths containing a comma or double quote are rejected with an error. Use a folder on a local drive.
- **User ID.** There is no `id` on Windows, and Docker Desktop bind mounts don't enforce host UID/GID, so the container runs as a fixed `1000:1000` (override with `CLAUDE_POD_USER`).
- **State directory.** `%USERPROFILE%\.claude-pod\` replaces `~/.claude-pod/`. There is no `chmod 700`; the default NTFS permissions on your user profile already restrict it to you (and administrators).
- **Colors.** `COLORTERM` is forwarded only if it is set on the host; Windows terminals don't usually set it, so Claude may use a reduced color palette unless you define `$env:COLORTERM = 'truecolor'`.
- **Hardening is unchanged.** Same `--cap-drop=ALL`, `--security-opt=no-new-privileges`, and `--pids-limit` as the bash version.

## Pasting images and screenshots

Same rule as the main README ([Pasting images and screenshots](../README.md#pasting-images-and-screenshots)): Claude can only read files inside the project folder. Copy the screenshot into the project, then re-copy it from that location before pasting.

## License and trademarks

MIT, same as the rest of the repository — see [`LICENSE`](../LICENSE). Claude Code is a separate product owned by Anthropic, PBC, and is not redistributed by this project; this project is not affiliated with or endorsed by Anthropic. "Claude" and "Claude Code" are trademarks of Anthropic, PBC.
