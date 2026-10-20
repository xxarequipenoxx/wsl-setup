# wsl-setup

Bootstrap for Ubuntu 22.04/24.04 on WSL2. One script, run once per distribution as a normal
user with sudo, prepares a development environment for AI-assisted work:

- AI coding agents: Claude Code, Codex, Gemini CLI (Node.js through nvm)
- GitHub CLI, Azure CLI and the Azure DevOps extension (Services only)
- Developer and security utilities: gitleaks, shellcheck, yq, Argo CD CLI and diagnostics
- Optional DevOps tooling with `--devops`: kubectl, Helm, Terraform, OpenTofu, Ansible
- Zsh with Oh My Zsh and Oh My Bash, without replacing existing dotfiles
- An optional sandbox configuration for Claude Code (bubblewrap, socat)

Each phase is prompted and can be skipped; authentication is never automatic.

## Usage

```bash
bash wsl-ubuntu-bootstrap/bootstrap.sh --help
bash wsl-ubuntu-bootstrap/bootstrap.sh --profile personal
bash wsl-ubuntu-bootstrap/bootstrap.sh --profile work --devops --no-sudo-nopasswd
```

The script installs software from vendor sources and adds apt repositories: read it before
running it. By default it grants the current user passwordless sudo; pass
`--no-sudo-nopasswd` to keep password prompts. Full options, authentication and security
notes: [wsl-ubuntu-bootstrap/README.md](wsl-ubuntu-bootstrap/README.md).

## Repository

| Path | Content |
|---|---|
| `wsl-ubuntu-bootstrap/` | the bootstrap script and its documentation |
| `.github/workflows/` | pull request checks (commits, security, shellcheck) and release |

Conventions for contributors and AI agents: [AGENTS.md](AGENTS.md). Security policy:
[SECURITY.md](SECURITY.md).
