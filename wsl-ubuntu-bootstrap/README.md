# WSL AI Toolkit

For **Ubuntu 22.04/24.04 WSL2**. Install once per distribution, as your normal user (not root).

## Windows PowerShell

Check existing distributions:

```powershell
wsl -l -v
```

If you need two new instances and have a recent WSL:

```powershell
wsl --install -d Ubuntu-24.04 --name Ubuntu-Work
wsl --install -d Ubuntu-24.04 --name Ubuntu-Perso
```

If your work distribution already exists, **do not reinstall or rename it**. Use its existing WSL name.

## Install inside each WSL

Move `bootstrap.sh` into the Linux environment (for example `~/bootstrap.sh`), then:

```bash
bash ~/bootstrap.sh --profile work --devops
# In the OTHER distribution:
bash ~/bootstrap.sh --profile personal
```

Optional: `--no-sandbox-config` installs bubblewrap and socat without modifying `~/.claude/settings.json`.

**Scripts install software from vendor-owned sources and configure apt repos; inspect before running. Internet and sudo required.** They do not log in to any service, change your Git identity, remove projects, or rewrite SSH keys. Existing Claude settings are merged and backed up before changes.

## Authenticate (separately in each WSL)

```bash
claude
codex
gemini
gh auth login
az login
```

Verify Claude's `/sandbox` menu after login. Sandbox restrictions can prevent network requests and filesystem access until configured; sandbox is not a VM security boundary. Do not run agents with unrestricted production credentials or on mounted shared Windows code containing sensitive data.

## Optional OpenShift CLI

The `oc` client is **not** included automatically because you should match the OpenShift version your clusters support. Download it from your trusted OpenShift console or approved internal artifact repository and place it in `~/.local/bin`.

## VS Code

Install the VS Code WSL extension on Windows. From each distribution run `cd ~/projects && code .` to open independent remote windows.

## Maintenance

Re-run bootstrap to update npm tools and package-managed CLIs. NVM controls Node.js. Review `.bashrc` for local shell customizations. The script does not configure Git credentials or SSO for you.

## Zsh, Oh My Zsh and Oh My Bash

The bootstrap installs `zsh`, clones the upstream Oh My Zsh and Oh My Bash repositories, and installs small, repeat-safe shell integration fragments. Existing `~/.bashrc` and `~/.zshrc` are **not replaced**. Both shells are available:

```bash
zsh     # Oh My Zsh, robbyrussell theme, git plugin
bash    # Oh My Bash, font theme
```

The login shell is **not changed by default**. To explicitly set Zsh as your login shell, run the bootstrap with `--default-shell zsh` (or run `chsh -s "$(command -v zsh)"`). On WSL, restart the distribution/terminal to observe the change. You can select Bash instead with `--default-shell bash`.

Shell configuration fragments:

- `~/.config/wsl-ai-toolkit/zsh-init.zsh`
- `~/.config/wsl-ai-toolkit/bash-init.sh`

If you have an extensively customized Oh My Zsh/Oh My Bash setup already, inspect the appended source line and adjust the fragments to avoid duplicate initialization.

## Fixed yq binary and Azure DevOps CLI

The script maps Linux `x86_64` → `amd64` and `aarch64` → `arm64` for mikefarah/yq release assets.

Azure DevOps extension (`az extension add --name azure-devops`) is installed for **Azure DevOps Services (cloud)**. It does **not** support on-prem Azure DevOps Server / TFS. Login remains interactive using `az login` (prefer Entra ID over PAT).

GitHub: `gh auth login --hostname github.com --git-protocol https --web` then `gh auth setup-git` and `gh auth status`. Note that `gh` may store an OAuth token in a plaintext file if a system credential store is unavailable. Set up secure credential storage for higher-security usage, and never share credentials across WSL instances.

## Integrated GitHub + Azure DevOps configuration

The `bootstrap.sh` script now accepts:

```bash
bash bootstrap.sh --profile personal --default-shell zsh --setup-auth \
  --git-name "Your Name" --git-email "your@email.example"

# Work: Azure DevOps Services *cloud* organization only
bash bootstrap.sh --profile work --devops --default-shell zsh --setup-auth \
  --git-name "Your Name" --git-email "work@email.example" \
  --azure-org "https://dev.azure.com/ORG" --azure-project "PROJECT"
```

`--setup-auth` invokes interactive GitHub OAuth login (no hard-coded PAT), configures Git HTTPS to use `gh` after login, and invokes Azure device-code authentication. Existing GitHub sessions are preserved. Other accounts (Claude, Codex, Gemini) remain user-interactive: launch `claude`, `codex`, and `gemini` separately to sign in. Never commit token files or paste credentials into agent prompts. `gh` may fall back to storing tokens in plaintext under `~/.config/gh` when no secure keyring is available in WSL; consider installing/configuring a compatible credential store. The Azure CLI stores account authentication state under `~/.azure`—keep distributions and home directories separate.

This **does not** give permission to push, merge or run production pipelines automatically. Repository access, branch protection and CI rights are enforced server-side. Use the installed `ai-git-workflow --help` command to see explicit branch/push/PR/check/merge and Azure DevOps cloud pipeline listing actions. It does not trigger pipelines or bypass approvals.

`az devops` supports Azure DevOps Services **cloud** only, not the ICRC/TFS on-prem server. Use your on-prem Git remote and server-compatible REST API for that service; do not put its URL into `--azure-org`.

The script can be rerun. `--setup-auth` requires an interactive WSL shell; do not use `sudo bash bootstrap.sh`.

## Passwordless sudo and default projects directory

By default, bootstrap creates `~/projects` when absent and configures the **current non-root WSL user** for passwordless sudo using `/etc/sudoers.d/90-wsl-ai-toolkit-USERNAME`. It validates the rule with `visudo` and does not rewrite `/etc/sudoers`. To retain password prompts, pass `--no-sudo-nopasswd`. This option only skips creating/updating the rule; it does **not** revoke an already installed sudoers rule. To revoke, manually remove the corresponding file using sudo.

**Security warning:** `NOPASSWD: ALL` effectively grants local processes and AI agents running under this WSL user unrestricted root access to this distribution, and potentially to accessible Windows-mounted paths. Avoid on managed corporate machines unless permitted by IT. Prefer `--no-sudo-nopasswd` when handling sensitive corporate credentials or code.

The script also adds idempotent shell initialization to `~/.bashrc` and `~/.zshrc`. Both Bash and Zsh interactive shells switch into `~/projects` on startup. If `~/.bash_profile` exists, it receives an interactive-login-only `cd` line as well (without replacing the file). This also changes the initial working directory of VS Code integrated terminals; manually `cd` back to a project directory if needed.

## Ubuntu updates, security tooling, and skipping authentication

Default bootstrap runs `apt-get update` and `apt-get upgrade -y` (installed package updates only, **not** an Ubuntu distribution release upgrade). Use `--skip-os-upgrade` to install tools without upgrading existing OS packages, or `--full-upgrade` to opt into apt full-upgrade (can change package dependencies and remove packages).

Bootstrap installs Gitleaks (`gitleaks git .` / `gitleaks dir .`), Argo CD CLI (`argocd`), shellcheck, git-lfs, bash-completion, htop, btop, tree, ncdu, lsof, strace, dnsutils, tmux and other diagnostics. `--acm-cli` optionally installs upstream OCM `clusteradm`, which is **not** a replacement for the Red Hat Advanced Cluster Management UI/API or `oc` on OpenShift. The `oc` client is intentionally left to a supported cluster-matched binary source.

**Authentication is skipped by default.** `--skip-auth` makes that explicit; `--setup-auth` opts into GitHub and Azure interactive login. Neither option authenticates Claude, Codex, Gemini, Argo CD, nor OpenShift automatically. Do not hard-code personal access tokens into this script.

Example:

```bash
bash bootstrap.sh --profile work --devops --acm-cli --default-shell zsh --skip-auth
# Opt in to interactive sign-in separately:
bash bootstrap.sh --profile personal --setup-auth --skip-os-upgrade
```

**Security note:** the existing bootstrap defaults to configuring passwordless sudo for your WSL account. This is risky with coding agents; choose `--no-sudo-nopasswd` on professional or privileged machines.

## Authentication prompt / unattended installs

By default, the bootstrap asks at the end: **Authenticate GitHub and Azure now? [y/N]**. Press Enter or type `n` to skip; type `y` to start interactive sign-ins. It never asks for passwords or PATs in the script.

- `--skip-auth`: do not ask and do not authenticate (recommended for automated/repeated installs).
- `--setup-auth`: do not ask; start interactive sign-ins (requires a TTY).
- Without flags in a non-interactive environment, authentication is skipped automatically.

Claude Code, Codex and Gemini authentication is always separate and user-initiated.


## Authentication and update behavior (October 2026)

The bootstrap **prompts separately** for GitHub and Azure sign-in:

```text
Configure / verify GitHub authentication now? [y/N]
Configure / verify Azure authentication now? [y/N]
```

Press Enter or `n` for either provider to skip. If Azure CLI already has a working session, the script shows the active account and asks separately whether to switch it; it does not force device login.

- `--skip-auth`: never prompt or sign in (recommended for automated reruns).
- `--setup-auth`: run both provider flows without asking the initial questions (interactive terminal required).
- `--force-update`: redownload GitHub release binaries (Gitleaks, Argo CD, yq, optional clusteradm and Kubernetes/Helm) even when present.

The default checks for already installed binaries and skips release downloads when present. APT upgrades Ubuntu and APT-installed tools; `npm install -g` refreshes Codex/Gemini; nvm refreshes Node LTS; `uv self update` and `claude update` are attempted for existing user-local installs. `--force-update` is best used periodically for binaries not managed by package managers.

Example:
```bash
bash bootstrap.sh --profile work --devops --acm-cli --default-shell zsh --skip-auth --force-update --no-sudo-nopasswd
```

**Security:** For professional WSL, passwordless sudo is discouraged; use `--no-sudo-nopasswd`.


## Interactive phase skipping (updated)

Running normally from a WSL terminal prompts before each group of work:

- Installation and configuration phases use `Run ...? [Y/n]`. Enter `n` to skip a phase; Enter runs it.
- GitHub and Azure login each use `Start ... authentication? [y/N]` when interactive. To prevent any authentication prompt use `--skip-auth`.
- To suppress all phase prompts and install selected components without logging into accounts: `--yes --skip-auth`.
- To suppress specific steps from the start use repeatable `--skip-step NAME` flags. For example:

```bash
bash bootstrap.sh --profile work --devops --skip-step azure-cli --skip-step azure-devops --skip-step auth-azure
```

Supported phase identifiers: `os-upgrade`, `base`, `sudo`, `shell`, `github-cli`, `azure-cli`, `azure-devops`, `node-ai`, `python-tools`, `gitops`, `sandbox`, `devops`, `git-config`, `auth-github`, `auth-azure`.

`--skip-auth` bypasses GitHub and Azure authentication. `--yes` also skips authentication unless `--setup-auth` is given. Re-running updates package-managed tools; binaries managed as release downloads are retained unless `--force-update` is specified.

## GitHub and Azure authentication are separate

By default the bootstrap prompts **individually** at the end, both defaulting to No:

```text
Authenticate GitHub now? [y/N]
Authenticate Azure now? [y/N]
```

`--setup-auth` keeps these two separate questions, it does not force either login.
`--auth-github` or `--auth-azure` explicitly enables only the selected provider;
`--skip-step auth-github` / `--skip-step auth-azure` skip individual providers;
`--skip-auth` skips both. `--yes` skips implicit authentication.

If an Azure device-code login is already waiting, press Ctrl+C, and rerun the updated bootstrap.
