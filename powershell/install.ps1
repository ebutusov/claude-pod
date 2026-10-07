#Requires -Version 5.1
# PowerShell port of install.sh. Builds the 'claude-pod' image.
$ErrorActionPreference = 'Stop'

function Info($m) { Write-Host '* ' -ForegroundColor Blue -NoNewline; Write-Host $m -ForegroundColor White }
function Ok($m)   { Write-Host 'v ' -ForegroundColor Green -NoNewline; Write-Host $m }
function Err($m)  { Write-Host "x $m" -ForegroundColor Red }
function Die($m)  { Err $m; exit 1 }
function Dim($m)  { Write-Host $m -ForegroundColor DarkGray }

$repoDir = $PSScriptRoot
$image = 'claude-pod'
$version = if ($env:CLAUDE_CODE_VERSION) { $env:CLAUDE_CODE_VERSION } else { 'latest' }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Die 'Docker is required but not on PATH.' }
& docker info *> $null
if ($LASTEXITCODE -ne 0) { Die 'Docker daemon is not running.' }

# Pinned versions: the literal in the Dockerfile RUN line is the cache key. For "latest" we pass
# CACHEBUST=<unix time> to force a refetch.
$buildArgs = @('--build-arg', "CLAUDE_CODE_VERSION=$version")
if ($version -eq 'latest') {
  $buildArgs += @('--build-arg', "CACHEBUST=$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())")
}

Info 'Preflight'
Dim "  docker:        $(& docker --version)"
Dim "  repo:          $repoDir"
Dim "  image:         $image"
Dim "  claude-code:   $version"
Write-Host ''

Info "Building image '$image'"
# Docker writes build progress to stderr; under 'Stop' Windows PowerShell 5.1 would turn that into
# a terminating error, so relax it for this call and rely on $LASTEXITCODE instead.
$ErrorActionPreference = 'Continue'
& docker build --progress=plain @buildArgs -t $image $repoDir 2>&1 |
  ForEach-Object { Dim "  $_" }
$buildExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($buildExit -ne 0) { Die "docker build failed (exit $buildExit)" }
Ok "Image '$image' built"
Write-Host ''

Info 'Installed'
$ErrorActionPreference = 'Continue'
$resolved = & docker run --rm $image claude --version 2>&1
$runExit = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
if ($runExit -eq 0) { Dim "  claude-code:   $resolved" }
else { Err "Could not determine Claude Code version (build succeeded; 'claude --version' failed)" }
Write-Host ''

Info 'Next steps'
Write-Host '  cd into your work-in-progress project folder first, then:'
Write-Host "    Open shell in pod:        $repoDir\claude-pod.ps1"
Write-Host "    Or run Claude directly:   $repoDir\claude-pod.ps1 claude --dangerously-skip-permissions"
Write-Host "    Optional shortcut:        function claude-pod { & '$repoDir\claude-pod.ps1' @args }   # add to `$PROFILE"
