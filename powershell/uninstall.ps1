#Requires -Version 5.1
# PowerShell port of uninstall.sh.
$ErrorActionPreference = 'Stop'

function Info($m) { Write-Host '* ' -ForegroundColor Blue -NoNewline; Write-Host $m -ForegroundColor White }
function Ok($m)   { Write-Host 'v ' -ForegroundColor Green -NoNewline; Write-Host $m }
function Dim($m)  { Write-Host $m -ForegroundColor DarkGray }

$claudeDir = Join-Path $HOME '.claude-pod'
$image = 'claude-pod'

Info 'Will remove'
Dim "  image: $image"
Dim "  dir:   $claudeDir (auth + session history)"
Write-Host ''

Info 'Will NOT remove'
Dim '  node:24 base image (docker rmi node:24 to clear)'
Dim '  Docker build cache (docker builder prune to clear)'
Dim '  this repo folder (delete it yourself)'
Write-Host ''

# Non-interactive stdin counts as a declined prompt.
try { $reply = Read-Host 'Proceed? [y/N]' } catch { $reply = '' }
if ($reply -notmatch '^[Yy]$') { Write-Host 'Aborted.'; exit 0 }
Write-Host ''

Info "Removing image '$image'"
# Probe with `image ls -q`, not `image inspect` (see uninstall.sh for why).
$present = & docker image ls -q $image 2>$null
if ($present) {
  $ErrorActionPreference = 'Continue'
  & docker rmi -f $image 2>&1 | ForEach-Object { Dim "  $_" }
  $rc = $LASTEXITCODE
  $ErrorActionPreference = 'Stop'
  if ($rc -ne 0) { Write-Host "x docker rmi failed (exit $rc)" -ForegroundColor Red; exit 1 }
  Ok "Image '$image' removed"
} else {
  Ok "Image '$image' was not present"
}
Write-Host ''

Info 'Removing host directory'
if (Test-Path $claudeDir) {
  Remove-Item -Recurse -Force $claudeDir
  Ok "Removed $claudeDir"
} else {
  Ok "$claudeDir was not present"
}
Write-Host ''

Ok 'Done'
