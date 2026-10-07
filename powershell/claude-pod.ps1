#Requires -Version 5.1
# PowerShell port of `claude-pod` (bash). Works on Windows PowerShell 5.1 and PowerShell 7+.
# Needs Docker Desktop in Linux-containers mode (WSL2 backend recommended).
$ErrorActionPreference = 'Stop'

function Err($msg) { Write-Host "x $msg" -ForegroundColor Red }
function Die($msg) { Err $msg; exit 1 }

# --help / -h: print copy-pastable usage and exit BEFORE any Docker work, so help still works when
# Docker is down or the image isn't built yet. We resolve our own location so every command printed
# below is copy-pastable as-is, no matter where the repo was cloned or whether the function is set up.
if ($args.Count -gt 0 -and ($args[0] -eq '--help' -or $args[0] -eq '-h')) {
  $here = $PSScriptRoot
  function Row($label, $cmd) {
    Write-Host ('  {0,-18} ' -f $label) -NoNewline
    Write-Host $cmd -ForegroundColor White
  }
  Write-Host 'claude-pod' -ForegroundColor White -NoNewline
  Write-Host ' - run Claude Code in a Docker sandbox scoped to the current folder.'
  Write-Host "`nRun  (cd into your project first - the current folder is what gets mounted):"
  Row 'Open a shell:'   "$here\claude-pod.ps1"
  Row 'Run Claude:'     "$here\claude-pod.ps1 claude --dangerously-skip-permissions"
  Write-Host "`nManage  (works from any folder):"
  Row 'Install/update:' "$here\install.ps1"
  Row 'Pin a version:'  "`$env:CLAUDE_CODE_VERSION='2.0.0'; $here\install.ps1"
  Row 'Uninstall:'      "$here\uninstall.ps1"
  Write-Host "`nOptions  (set the env var first, then run):"
  Row 'Publish ports:'  "`$env:PORTS='3000 5173'; $here\claude-pod.ps1"
  Row 'Isolate/limit:'  "`$env:NET='none'; `$env:MEMORY='4g'; `$env:PIDS='512'; $here\claude-pod.ps1"
  Write-Host ''
  Row 'Shortcut:'       "function claude-pod { & '$here\claude-pod.ps1' @args }   # add to `$PROFILE"
  Row 'Blocked script?' "powershell -ExecutionPolicy Bypass -File $here\claude-pod.ps1"
  Row 'Full README:'    'https://github.com/trekhleb/claude-pod'
  exit 0
}

# Preflight checks, in causal order (see claude-pod bash script for the rationale):
# daemon down would otherwise be misreported as a missing image, and a missing image would make
# Docker try to pull 'claude-pod' from Docker Hub. `image ls -q` resolves names like `docker run`.
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Die 'Docker is required but not on PATH.' }
& docker info *> $null
if ($LASTEXITCODE -ne 0) { Die 'Docker daemon is not running.' }
$img = & docker image ls -q claude-pod 2>$null
if (-not $img) {
  Err "Image 'claude-pod' not found."
  Die "Please run '$PSScriptRoot\install.ps1' first to build the local container."
}

# Host-side state dir: persists Claude's auth + history across container restarts. It lives under
# the user profile, whose default NTFS ACLs are already owner-only, so no chmod equivalent is needed.
$stateDir = Join-Path $HOME '.claude-pod'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null

# Claude reads its config from $HOME/.claude.json; we bind-mount this file separately. It must
# pre-exist (Docker would create a directory otherwise) and must not be empty (parse error), so
# seed it with {}. Write without a BOM: Windows PowerShell 5.1's `Set-Content -Encoding UTF8` adds one.
$stateJson = Join-Path $stateDir '.claude.json'
if (-not (Test-Path $stateJson) -or (Get-Item $stateJson).Length -eq 0) {
  [System.IO.File]::WriteAllText($stateJson, '{}', (New-Object System.Text.UTF8Encoding($false)))
}

# Project path: the container is Linux, so a Windows path like C:\Users\me\proj is exposed as
# /c/Users/me/proj (same convention as Git Bash / WSL-style paths). We use --mount instead of -v
# because the drive-letter colon makes `-v SRC:DST` ambiguous.
$cwd = (Get-Location)
if ($cwd.Provider.Name -ne 'FileSystem') { Die 'Run claude-pod from a regular filesystem folder.' }
$hostPath = $cwd.ProviderPath
if ($hostPath -match '^([A-Za-z]):\\?(.*)$') {
  $containerPath = '/' + $Matches[1].ToLower() + '/' + ($Matches[2] -replace '\\', '/')
  $containerPath = $containerPath.TrimEnd('/')
  if ($containerPath.Length -eq 2) { $containerPath += '/' }   # drive root: "/c" -> "/c/"
} else {
  Die "Unsupported path '$hostPath' (UNC paths can't be mounted); use a folder on a local drive."
}
if ($hostPath -match '[,"]') { Die "Path '$hostPath' contains a comma or quote, which --mount can't express." }

# TTY detection: passing -t when input/output is piped would crash Docker.
$dockerFlags = New-Object System.Collections.Generic.List[string]
$dockerFlags.Add('--rm')
if (-not [Console]::IsInputRedirected)  { $dockerFlags.Add('-i') }
if (-not [Console]::IsOutputRedirected) { $dockerFlags.Add('-t') }

# Optional port mapping: PORTS="3000 8080:80". Always bound to 127.0.0.1, validated up front.
if ($env:PORTS) {
  foreach ($port in ($env:PORTS -split '\s+' | Where-Object { $_ })) {
    if ($port -notmatch '^[0-9]+(:[0-9]+)?$') {
      Die "PORTS entry '$port' is invalid; expected 'PORT' or 'HOST:CONTAINER' (digits only)."
    }
    foreach ($n in $port.Split(':')) {
      if ([int64]$n -lt 1 -or [int64]$n -gt 65535) {
        Die "PORTS entry '$port' has '$n' outside the 1-65535 range."
      }
    }
    $dockerFlags.Add('-p')
    if ($port.Contains(':')) { $dockerFlags.Add("127.0.0.1:$port") }
    else                     { $dockerFlags.Add("127.0.0.1:${port}:${port}") }
  }
}

# Optional network isolation (NET=none). Mutually exclusive with PORTS.
if ($env:NET -eq 'none') {
  if ($env:PORTS) { Die "NET=none and PORTS are mutually exclusive: a no-network container can't publish ports." }
  $dockerFlags.Add('--network=none')
}

# Resource limits: --pids-limit always applied; MEMORY/CPUS opt-in.
$pids = if ($env:PIDS) { $env:PIDS } else { '4096' }
$dockerFlags.Add("--pids-limit=$pids")
if ($env:MEMORY) { $dockerFlags.Add("--memory=$($env:MEMORY)") }
if ($env:CPUS)   { $dockerFlags.Add("--cpus=$($env:CPUS)") }

# Hardening is identical to the bash version. Windows has no `id`; bind mounts from Docker Desktop
# don't enforce host UID/GID, so a fixed non-root uid:gid is used (override with CLAUDE_POD_USER).
$user = if ($env:CLAUDE_POD_USER) { $env:CLAUDE_POD_USER } else { '1000:1000' }
$dockerFlags.Add('--cap-drop=ALL')
$dockerFlags.Add('--security-opt=no-new-privileges')
$dockerFlags.Add('--user');  $dockerFlags.Add($user)
$dockerFlags.Add('-e');      $dockerFlags.Add('HOME=/home/claude-pod')
# Bare `-e COLORTERM` forwards the host value only if set (PowerShell has no equivalent unless defined).
if ($env:COLORTERM) { $dockerFlags.Add('-e'); $dockerFlags.Add('COLORTERM') }
$dockerFlags.Add('--mount'); $dockerFlags.Add("type=bind,source=$hostPath,target=$containerPath")
$dockerFlags.Add('-w');      $dockerFlags.Add($containerPath)
$dockerFlags.Add('--mount'); $dockerFlags.Add("type=bind,source=$stateDir,target=/home/claude-pod/.claude")
$dockerFlags.Add('--mount'); $dockerFlags.Add("type=bind,source=$stateJson,target=/home/claude-pod/.claude.json")
$dockerFlags.Add('claude-pod')
foreach ($a in $args) { $dockerFlags.Add([string]$a) }

& docker run @dockerFlags
exit $LASTEXITCODE
