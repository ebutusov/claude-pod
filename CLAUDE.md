# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`claude-pod` is a small set of shell scripts + a Dockerfile that run the Claude Code CLI inside a Docker container mounted on the current project folder. There is no build system, test suite, or linter — the "code" is `claude-pod`, `install.sh`, `uninstall.sh`, `Dockerfile`, and the README.

## Commands

- Build/update the image: `./install.sh` (pin with `CLAUDE_CODE_VERSION=2.0.0 ./install.sh`; `latest` passes `CACHEBUST=$(date +%s)` to force an npm refetch)
- Try the wrapper: `cd <some-project> && /path/to/claude-pod` (shell) or `claude-pod claude --dangerously-skip-permissions`
- Help (works without Docker): `./claude-pod --help`
- Remove everything: `./uninstall.sh`
- Runtime env knobs read by `claude-pod`: `PORTS="3000 8080:80"`, `NET=none`, `PIDS` (default 4096), `MEMORY`, `CPUS`

## Architecture

- `claude-pod` (bash): preflight (docker present, daemon up, image exists via `image ls -q`), seeds `~/.claude-pod/` (mode 700) and `~/.claude-pod/.claude.json` (must exist and contain `{}` — Docker would otherwise create a directory, and Claude rejects an empty file), validates `PORTS`/`NET`/limits into `DOCKER_FLAGS`, then `exec docker run` with `--cap-drop=ALL`, `no-new-privileges`, `--user $(id -u):$(id -g)`, `HOME=/home/claude-pod`, `$PWD` mounted at the identical path, and `~/.claude-pod` mounted as the container's `~/.claude`.
- `Dockerfile`: `node:24-slim` + git/curl/jq/gh + `npm i -g @anthropic-ai/claude-code`. It deliberately has no `USER` — the runtime user is the host UID/GID injected by the wrapper, hence the world-writable `/home/claude-pod` and the `PS1`/aliases appended to `/etc/bash.bashrc` (no passwd entry or `.bashrc` for that user).
- `install.sh` builds the image tagged `claude-pod`; `uninstall.sh` removes it, `~/.claude-pod`, and mentions the base image.
- `powershell/` is a parallel native-Windows port (`claude-pod.ps1`, `install.ps1`, `uninstall.ps1`, its own `Dockerfile`, which uses `node:24` and adds `python`). It is currently untracked and the README still says native Windows is unsupported.

## Keep in sync

- Behavior changes to the bash scripts should be mirrored in the `powershell/` counterparts (and vice versa); the ps1 files reference the bash script for rationale.
- The base image tag is hard-coded in `Dockerfile` and in the `uninstall.sh` message ("If you bump this tag, also update the literal in uninstall.sh").
- `--help` output in `claude-pod` and the README usage/options sections describe the same commands; update both.
- Scripts are heavily commented with the *why* (Docker quirks, security rationale); preserve and extend that style when editing.
