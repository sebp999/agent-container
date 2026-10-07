# Agent Coder Container

Run coding agents in a restricted Docker-compatible container while exposing only the source directory you choose.

The wrapper works with Docker Desktop, Colima, and other engines that provide a compatible `docker` CLI. It does not mount the Docker socket and the image does not include Docker.

## Prerequisites

- A Docker-compatible engine and CLI.
- On macOS with Colima:

  ```bash
  colima start
  docker info
  ```

- Network access while building the image, because the agent CLIs are installed from npm.

## Build

Build the image:

```bash
docker build -t agent-coder .
```

Or use the helper, which builds the container user with your host UID/GID:

```bash
./agent-build
```

The UID/GID build args matter most on Linux bind mounts. Docker Desktop and Colima on macOS usually handle host file ownership through their VM file sharing layer.

If the requested numeric user or group already exists in the base image, the Dockerfile reuses it instead of creating a duplicate. This commonly happens because the Node base image already has UID/GID `1000`, and macOS commonly uses host group id `20`.

## Usage

From any source checkout:

```bash
./agent claude .
./agent codex .
./agent opencode .
```

If you omit the directory, the current directory is used:

```bash
./agent claude
```

Arguments after the directory are passed to the agent:

```bash
./agent claude . --resume
./agent codex --help
```

Use a different Docker-compatible CLI if needed:

```bash
AGENT_CODER_DOCKER=docker ./agent claude .
```

Use a different image tag:

```bash
AGENT_CODER_IMAGE=agent-coder:dev ./agent codex .
```

## Environment Variables

The wrapper does not forward your full host environment.

Forward only named variables with `AGENT_CODER_ENV`, using commas or spaces:

```bash
AGENT_CODER_ENV=ANTHROPIC_API_KEY ./agent claude .
AGENT_CODER_ENV=OPENAI_API_KEY ./agent codex .
AGENT_CODER_ENV=ANTHROPIC_API_KEY,OPENAI_API_KEY ./agent opencode .
```

Variables listed in `AGENT_CODER_ENV` are passed with Docker's `--env NAME` form, so the value comes from the host environment at launch time. Unset variables are skipped with a warning.

Terminal-related variables `TERM` and, when set, `COLORTERM` are forwarded explicitly so full-screen agent UIs behave normally.

If a corporate proxy uses a private certificate authority, set
`NODE_EXTRA_CA_CERTS` to the CA bundle on the host. The wrapper mounts only that
file read-only and changes the variable to its path inside the container:

```bash
export NODE_EXTRA_CA_CERTS="$HOME/athena-crt.crt"
./agent claude ~/src/my-project
```

Do not add `NODE_EXTRA_CA_CERTS` to `AGENT_CODER_ENV`; the wrapper handles it
separately because the host path does not exist inside the container.

OpenCode uses Bun/OpenTUI native libraries that are unpacked into `/tmp` and loaded at runtime. For that reason `/tmp` is still an isolated tmpfs, but it is mounted with `exec`.

When launching OpenCode, the wrapper requires the host configuration file at
`~/.config/opencode/opencode.json` and mounts that single file read-only at the
same location under the container user's home. The rest of the host's
`~/.config` directory remains unavailable to the container.

## Authentication Persistence

The host home directory is never mounted. Instead, each agent gets a dedicated Docker named volume mounted as the container user's home directory:

```text
agent-coder-claude   -> /home/coder
agent-coder-codex    -> /home/coder
agent-coder-opencode -> /home/coder
```

This lets browser/device-code login flows and local agent settings persist across container runs without exposing `~/.ssh`, cloud credentials, or other host configuration.

Before starting the agent, the wrapper runs a short volume-preparation container as root to make the selected auth volume writable by `coder`. That helper mounts only the named auth volume, not your source directory. The actual agent container then runs as the non-root `coder` user with the restricted flags described below.

To remove persisted authentication and agent state:

```bash
docker volume rm agent-coder-claude
docker volume rm agent-coder-codex
docker volume rm agent-coder-opencode
```

## Mounts

For a command such as:

```bash
./agent claude ~/src/my-project
```

the wrapper mounts:

```text
~/src/my-project       -> /workspace
agent-coder-claude     -> /home/coder
tmpfs                  -> /tmp
${NODE_EXTRA_CA_CERTS}  -> /etc/ssl/certs/agent-coder-extra-ca.crt (when set)
~/.config/opencode/opencode.json -> /home/coder/.config/opencode/opencode.json (OpenCode only, read-only)
```

It does not mount:

```text
$HOME
~/.ssh
~/.aws
~/.config (except the single OpenCode config file for OpenCode runs)
/var/run/docker.sock
Docker configuration
other source directories
```

Changes under `/workspace` are bind-mounted and appear immediately on the host.

## Security Model

The intended boundary is simple:

```text
Access to selected source directory: YES
Access to network: YES
Access to per-agent Docker volume: YES
Access to Docker socket: NO
Access to host home directory: NO
Access to SSH keys: NO
Access to cloud credentials: NO
Root privileges: NO
Linux capabilities: NONE
Writable root filesystem: NO
```

The container is launched with:

```text
--rm
--interactive
--tty when attached to a TTY
--cap-drop ALL
--security-opt no-new-privileges
--read-only
--tmpfs /tmp:rw,nosuid,nodev,exec,mode=1777
-v SOURCE:/workspace
-v agent-coder-AGENT:/home/coder
-w /workspace
```

This is not a complete defense against container escape vulnerabilities. It is intended to avoid casually exposing the rest of your machine to autonomous coding tools.

## macOS and Linux Notes

With Docker Desktop or Colima on macOS, bind-mounted file ownership is usually mediated by the VM and should feel like normal host editing.

On Linux, container UIDs are real host UIDs for bind mounts. Prefer building with:

```bash
./agent-build
```

or manually:

```bash
docker build \
  --build-arg USER_UID="$(id -u)" \
  --build-arg USER_GID="$(id -g)" \
  -t agent-coder \
  .
```

If the image was built with a different UID/GID, files created in the checkout may appear to be owned by that numeric user on the host.

## Cleanup

Agent sessions are run with `--rm`, so the container is removed when the session exits.

Source changes remain because `/workspace` is a bind mount.

Authentication volumes remain until you remove them:

```bash
docker volume rm agent-coder-claude agent-coder-codex agent-coder-opencode
```
