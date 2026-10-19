#!/usr/bin/env bash
set -Eeuo pipefail

PROFILE=""; DEVOPS=0; SUDO_NOPASSWD=1; CONFIG_SANDBOX=1; DEFAULT_SHELL=""; SETUP_AUTH=0; GIT_NAME=""; GIT_EMAIL=""; AZ_ORG=""; AZ_PROJECT=""; OS_UPDATE=1; OS_FULL_UPGRADE=0; SKIP_AUTH=0; AUTH_CHOICE="ask"; ACM_CLI=0; FORCE_UPDATE=0; INTERACTIVE_STEPS=1; SKIP_STEPS=","; RUN_ONLY=""; AUTH_GH="ask"; AUTH_AZ="ask"
usage(){ cat <<'HELP'
Usage: bash bootstrap.sh --profile work|personal [--devops] [--no-sandbox-config] [--default-shell zsh|bash] [--setup-auth|--skip-auth|--auth-github|--auth-azure] [--force-update] [--yes|--non-interactive] [--skip-step NAME] [--skip-os-upgrade] [--full-upgrade] [--acm-cli] [--no-sudo-nopasswd] [--git-name "Name"] [--git-email "email"] [--azure-org URL] [--azure-project NAME]
Runs inside Ubuntu WSL2 as a normal user with sudo privileges.
Installs AI agents, Azure CLI, GitHub CLI, and developer utilities.
--devops additionally installs kubectl, Helm, Terraform, OpenTofu and Ansible.
Installs Zsh + Oh My Zsh and Oh My Bash; preserves existing dotfiles.
--default-shell zsh|bash optionally sets the default login shell (not by default).
By default, asks before EACH installation phase [Y/n] and each authentication [y/N].
--yes / --non-interactive runs installation phases without questions, but skips auth unless --setup-auth.
--skip-step NAME skips an installation phase (repeatable or comma-separated).
Phases: os-upgrade, base, sudo, shell, github-cli, azure-cli, azure-devops, node-ai, python-tools, gitops, sandbox, devops, git-config, auth-github, auth-azure.
--skip-auth skips both logins. --setup-auth asks separately for each authentication.
--auth-github / --auth-azure explicitly start only that login (unless already connected).
--force-update refreshes release binaries even if already installed.
--setup-auth never forces a login: GitHub and Azure have separate [y/N] prompts.
Ubuntu apt update + upgrade runs by default; --skip-os-upgrade skips apt upgrade.
--full-upgrade uses apt full-upgrade (may remove packages); never upgrades Ubuntu release.
--acm-cli installs upstream Open Cluster Management clusteradm (not RHACM-specific).
--git-name/--git-email configure Git identity; --azure-org/--azure-project
configure Azure DevOps Services (cloud) defaults (not on-prem TFS).
By default grants current WSL user passwordless sudo (security-sensitive).
--no-sudo-nopasswd disables this. New interactive shells start in ~/projects.
HELP
}
while (($#)); do
 case "$1" in
  --profile) PROFILE="${2:-}"; shift 2;;
  --devops) DEVOPS=1; shift;;
  --setup-auth) SETUP_AUTH=1; SKIP_AUTH=0; AUTH_CHOICE="ask"; shift;;
  --auth-github) SKIP_AUTH=0; AUTH_GH="login"; shift;;
  --auth-azure) SKIP_AUTH=0; AUTH_AZ="login"; shift;;
  --skip-auth) SKIP_AUTH=1; SETUP_AUTH=0; AUTH_CHOICE="skip"; AUTH_GH="skip"; AUTH_AZ="skip"; shift;;
  --force-update) FORCE_UPDATE=1; shift;;
  --yes|--non-interactive) INTERACTIVE_STEPS=0; shift;;
  --skip-step) [[ -n "${2:-}" ]] || { echo "Missing step name" >&2; exit 2; }; SKIP_STEPS+="${2// /},"; shift 2;;
  --skip-os-upgrade) OS_UPDATE=0; shift;;
  --full-upgrade) OS_FULL_UPGRADE=1; shift;;
  --acm-cli) ACM_CLI=1; shift;;
  --no-sudo-nopasswd) SUDO_NOPASSWD=0; shift;;
  --git-name) GIT_NAME="${2:?Missing git name}"; shift 2;;
  --git-email) GIT_EMAIL="${2:?Missing git email}"; shift 2;;
  --azure-org) AZ_ORG="${2:?Missing Azure organization}"; shift 2;;
  --azure-project) AZ_PROJECT="${2:?Missing Azure project}"; shift 2;;
  --no-sandbox-config) CONFIG_SANDBOX=0; shift;;
  --default-shell) DEFAULT_SHELL="${2:-}"; shift 2;;
  -h|--help) usage; exit 0;;
  *) echo "Unknown option: $1" >&2; usage; exit 2;;
 esac
done
[[ "$PROFILE" == work || "$PROFILE" == personal ]] || { usage; exit 2; }
[[ -z "$DEFAULT_SHELL" || "$DEFAULT_SHELL" == zsh || "$DEFAULT_SHELL" == bash ]] || { usage; exit 2; }
[[ "$(id -u)" -ne 0 ]] || { echo 'Run as a normal WSL user, not root.' >&2; exit 1; }
[[ -f /etc/os-release ]] && . /etc/os-release
[[ "${ID:-}" == ubuntu ]] || { echo 'Ubuntu is required.' >&2; exit 1; }
command -v sudo >/dev/null || { echo 'sudo required'; exit 1; }
log(){ printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
fetch(){ curl --fail --silent --show-error --location --retry 3 "$1" -o "$2"; }
should_install(){
 local name="$1"
 if ! command -v "$name" >/dev/null 2>&1; then
  printf '%s not installed: installing.\n' "$name"; return 0
 fi
 if ((FORCE_UPDATE)); then
  printf '%s already installed: refreshing release.\n' "$name"; return 0
 fi
 printf '%s already installed: keeping current release (use --force-update to refresh).\n' "$name"
 return 1
}
ask_yes_no(){
 local question="$1" answer=""
 if [[ ! -r /dev/tty ]]; then return 1; fi
 printf '\n%s [y/N] ' "$question" > /dev/tty
 IFS= read -r answer < /dev/tty || answer=""
 [[ "${answer,,}" == y || "${answer,,}" == yes ]]
}
# Each phase is optional. Prompting never consumes input from piped installers.
valid_step(){
 case "$1" in
  os-upgrade|base|sudo|shell|github-cli|azure-cli|azure-devops|node-ai|python-tools|gitops|sandbox|devops|git-config|auth-github|auth-azure) return 0;;
  *) return 1;;
 esac
}
IFS=',' read -ra REQUESTED_SKIPS <<< "${SKIP_STEPS#,}"
for skip in "${REQUESTED_SKIPS[@]}"; do
 [[ -z "$skip" ]] || valid_step "$skip" || { echo "Unknown --skip-step: $skip" >&2; exit 2; }
done
phase(){
 local name="$1" label="$2"
 if [[ ",${SKIP_STEPS}," == *",${name},"* ]]; then
  echo "Skipping ${label} (--skip-step ${name})."; return 1
 fi
 if ((INTERACTIVE_STEPS)) && [[ -r /dev/tty ]]; then
  local answer=""
  printf '\nRun %s? [Y/n] ' "$label" > /dev/tty
  IFS= read -r answer < /dev/tty || answer=""
  case "${answer,,}" in n|no) echo "Skipping ${label} (selected no)."; return 1;; esac
 fi
 return 0
}
auth_phase(){
 local name="$1" label="$2"
 if [[ ",${SKIP_STEPS}," == *",${name},"* ]]; then
  echo "Skipping ${label} (--skip-step ${name})."; return 1
 fi
 if ((INTERACTIVE_STEPS)); then
  ask_yes_no "Start ${label}?" || { echo "Skipping ${label}."; return 1; }
  return 0
 fi
 return 1
}
ARCH="$(dpkg --print-architecture)"; CODENAME="${VERSION_CODENAME:-$(lsb_release -cs)}"
TEMP_DIR="$(mktemp -d)"; trap 'rm -rf "$TEMP_DIR"' EXIT
log "Profile: $PROFILE | Ubuntu ${VERSION_ID:-unknown}"
if phase os-upgrade 'Ubuntu OS update and upgrade'; then
 log 'Updating Ubuntu package indexes and installed OS packages (no release upgrade)'
 sudo apt-get update
 if ((OS_UPDATE)); then
  if ((OS_FULL_UPGRADE)); then
   sudo DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
  else
   sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
  fi
 fi
fi
if phase base 'base Linux packages, Zsh and sandbox dependencies'; then
 sudo apt-get update
 sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates curl wget git openssh-client gnupg lsb-release apt-transport-https \
  unzip zip tar xz-utils build-essential python3 python3-venv python3-pip pipx \
  bash-completion htop btop tree ncdu lsof strace dnsutils iputils-ping netcat-openbsd \
  rsync file less tmux shellcheck git-lfs git-extras \
  jq ripgrep fzf direnv bubblewrap socat software-properties-common zsh
fi
# Privileged change is deliberate and can be disabled by flag. Never edit /etc/sudoers directly.
if ((SUDO_NOPASSWD)) && phase sudo "passwordless sudo configuration (SECURITY SENSITIVE)"; then
 log 'Configuring passwordless sudo for current WSL user (security sensitive)'
 CURRENT_USER="$(id -un)"
 # Escaping sudoers special characters is avoidable by requiring a standard Linux username.
 if [[ ! "$CURRENT_USER" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
  echo "Cannot safely make sudoers entry for user: $CURRENT_USER" >&2; exit 1
 fi
 RULE_FILE="/etc/sudoers.d/90-wsl-ai-toolkit-${CURRENT_USER}"
 printf '%s ALL=(ALL:ALL) NOPASSWD: ALL\n' "$CURRENT_USER" > "$TEMP_DIR/sudo-rule"
 chmod 0440 "$TEMP_DIR/sudo-rule"
 sudo visudo -cf "$TEMP_DIR/sudo-rule" >/dev/null
 sudo install -o root -g root -m 0440 "$TEMP_DIR/sudo-rule" "$RULE_FILE"
 sudo visudo -cf "$RULE_FILE" >/dev/null
fi

mkdir -p "$HOME/projects" "$HOME/.local/bin" "$HOME/.config/wsl-ai-toolkit"
printf '%s\n' "$PROFILE" > "$HOME/.config/wsl-ai-toolkit/profile"

# Add user-local binaries to subsequent interactive bash sessions without duplicating lines.
if ! grep -Fq '# wsl-ai-toolkit PATH' "$HOME/.bashrc"; then
 cat >> "$HOME/.bashrc" <<'BASHRC'

# wsl-ai-toolkit PATH
export PATH="$HOME/.local/bin:$PATH"
BASHRC
fi
export PATH="$HOME/.local/bin:$PATH"

if phase shell 'Oh My Zsh, Oh My Bash, shell configuration and default shell'; then
log 'Installing Oh My Zsh and Oh My Bash without overwriting shell dotfiles'
# Clone upstream into a user-owned directory. Unlike the stock installers,
# cloning directly does not replace .bashrc / .zshrc or change the login shell.
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
 git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
elif [[ -d "$HOME/.oh-my-zsh/.git" ]]; then
 git -C "$HOME/.oh-my-zsh" pull --ff-only || echo 'Oh My Zsh update skipped (local changes or network).'
fi
if [[ ! -d "$HOME/.oh-my-bash" ]]; then
 git clone --depth=1 https://github.com/ohmybash/oh-my-bash.git "$HOME/.oh-my-bash"
elif [[ -d "$HOME/.oh-my-bash/.git" ]]; then
 git -C "$HOME/.oh-my-bash" pull --ff-only || echo 'Oh My Bash update skipped (local changes or network).'
fi
# Keep all our shell integration in dedicated, repeat-safe fragments.
cat > "$HOME/.config/wsl-ai-toolkit/zsh-init.zsh" <<'ZSHINIT'
export PATH="$HOME/.local/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git)
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then source "$ZSH/oh-my-zsh.sh"; fi
export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then source "$NVM_DIR/nvm.sh"; fi
if command -v direnv >/dev/null 2>&1; then eval "$(direnv hook zsh)"; fi
# New interactive terminals start in the WSL projects directory.
[[ -o interactive ]] && cd "$HOME/projects"
ZSHINIT
cat > "$HOME/.config/wsl-ai-toolkit/bash-init.sh" <<'BASHINIT'
export PATH="$HOME/.local/bin:$PATH"
export OSH="$HOME/.oh-my-bash"
OSH_THEME="font"
if [[ -f "$OSH/oh-my-bash.sh" ]]; then source "$OSH/oh-my-bash.sh"; fi
export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then source "$NVM_DIR/nvm.sh"; fi
if command -v direnv >/dev/null 2>&1; then eval "$(direnv hook bash)"; fi
# New interactive terminals start in the WSL projects directory.
[[ $- == *i* ]] && cd "$HOME/projects"
BASHINIT
# Zsh uses .zshrc as an interactive entrypoint. Preserve user customization.
touch "$HOME/.zshrc"
if ! grep -Fq '# wsl-ai-toolkit zsh integration' "$HOME/.zshrc"; then
 cat >> "$HOME/.zshrc" <<'ZSHRC'

# wsl-ai-toolkit zsh integration
source "$HOME/.config/wsl-ai-toolkit/zsh-init.zsh"
ZSHRC
fi
if ! grep -Fq '# wsl-ai-toolkit bash integration' "$HOME/.bashrc"; then
 cat >> "$HOME/.bashrc" <<'BASHRC'

# wsl-ai-toolkit bash integration
source "$HOME/.config/wsl-ai-toolkit/bash-init.sh"
BASHRC
fi
# A custom .bash_profile can bypass .bashrc entirely. Preserve it and add only
# the directory behavior for interactive login Bash in that case.
if [[ -f "$HOME/.bash_profile" ]] && ! grep -Fq '# wsl-ai-toolkit projects login' "$HOME/.bash_profile"; then
 cat >> "$HOME/.bash_profile" <<'BASHPROFILE'

# wsl-ai-toolkit projects login
case $- in *i*) cd "$HOME/projects" ;; esac
BASHPROFILE
fi
if [[ -n "$DEFAULT_SHELL" ]]; then
 SHELL_PATH="$(command -v "$DEFAULT_SHELL")"
 CURRENT_LOGIN_SHELL="$(getent passwd "$(id -un)" | cut -d: -f7)"
 if [[ "$CURRENT_LOGIN_SHELL" != "$SHELL_PATH" ]]; then
  log "Setting default login shell to $SHELL_PATH (explicitly requested)"
  # chsh may ask for the current user password.
  chsh -s "$SHELL_PATH"
 fi
fi

fi

if phase github-cli 'GitHub CLI'; then
log 'Installing GitHub CLI (Ubuntu repository)'
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y gh

fi

if phase azure-cli 'Azure CLI'; then
log 'Installing Azure CLI (Microsoft signed repository)'
fetch https://packages.microsoft.com/keys/microsoft.asc "$TEMP_DIR/microsoft.asc"
gpg --batch --yes --dearmor -o "$TEMP_DIR/microsoft.gpg" "$TEMP_DIR/microsoft.asc"
sudo install -m 0644 "$TEMP_DIR/microsoft.gpg" /usr/share/keyrings/microsoft-archive-keyring.gpg
ARCH="$(dpkg --print-architecture)"
CODENAME="${VERSION_CODENAME:-$(lsb_release -cs)}"
printf 'Types: deb\nURIs: https://packages.microsoft.com/repos/azure-cli/\nSuites: %s\nComponents: main\nArchitectures: %s\nSigned-By: /usr/share/keyrings/microsoft-archive-keyring.gpg\n' "$CODENAME" "$ARCH" | sudo tee /etc/apt/sources.list.d/azure-cli.sources >/dev/null
sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y azure-cli

fi

# The Azure DevOps extension supports Azure DevOps Services (cloud), not on-prem TFS.
# Installing the extension does not authenticate or grant access.
if phase azure-devops 'Azure DevOps CLI extension'; then
log 'Installing Azure DevOps CLI extension (cloud only)'
if ! command -v az >/dev/null 2>&1; then
 echo 'Azure CLI is unavailable; skipping Azure DevOps extension.'
elif az extension show --name azure-devops >/dev/null 2>&1; then
 az extension update --name azure-devops
else
 az extension add --name azure-devops
fi

fi

if phase node-ai 'Node.js, Codex, Gemini and Claude'; then
log 'Installing Node.js LTS via nvm (user-local)'
if [[ ! -s "$HOME/.nvm/nvm.sh" ]]; then
 fetch https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh "$TEMP_DIR/nvm-install.sh"
 PROFILE="$HOME/.bashrc" bash "$TEMP_DIR/nvm-install.sh"
fi
export NVM_DIR="$HOME/.nvm"
# shellcheck source=/dev/null
. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*' >/dev/null
nvm use default >/dev/null

log 'Installing OpenAI Codex and Google Gemini CLI'
npm install --global @openai/codex @google/gemini-cli

log 'Installing/updating Claude Code (native installer)'
if command -v claude >/dev/null 2>&1 && ! ((FORCE_UPDATE)); then
 claude update || echo 'Claude update unavailable; keeping installed version.'
else
 fetch https://claude.ai/install.sh "$TEMP_DIR/claude-install.sh"
 bash "$TEMP_DIR/claude-install.sh"
fi

fi

if phase python-tools 'uv and yq'; then
log 'Installing uv and yq'
if command -v uv >/dev/null 2>&1; then
 uv self update || echo 'uv self update unavailable; keeping installed version.'
else
 fetch https://astral.sh/uv/install.sh "$TEMP_DIR/uv-install.sh"
 sh "$TEMP_DIR/uv-install.sh"
fi
if should_install yq; then
 case "$(uname -m)" in
  x86_64) YQ_ARCH=amd64 ;;
  aarch64) YQ_ARCH=arm64 ;;
  *) YQ_ARCH=""; echo "Skipping yq: unsupported architecture $(uname -m)" ;;
 esac
 if [[ -n "$YQ_ARCH" ]]; then
  fetch "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${YQ_ARCH}" "$TEMP_DIR/yq"
  install -m 0755 "$TEMP_DIR/yq" "$HOME/.local/bin/yq"
 fi
fi

fi

if phase gitops 'Gitleaks, Argo CD and ACM CLI'; then
log 'Installing Gitleaks (Git secret scanning) and Argo CD CLI'
case "$(uname -m)" in
 x86_64) GITLEAKS_ARCH=x64; ARGO_ARCH=amd64; CLUSTERADM_ARCH=amd64 ;;
 aarch64) GITLEAKS_ARCH=arm64; ARGO_ARCH=arm64; CLUSTERADM_ARCH=arm64 ;;
 *) echo 'Unsupported architecture for Gitleaks/Argo CD' >&2; exit 1 ;;
esac
# GitHub release API used to select the matching versioned Gitleaks archive.
# Rate-limited environments can fail here; rerunning is safe.
if should_install gitleaks; then
 GITLEAKS_TAG="$(curl -fsSL --retry 3 https://api.github.com/repos/gitleaks/gitleaks/releases/latest | python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"])')"
 GITLEAKS_VERSION="${GITLEAKS_TAG#v}"
 fetch "https://github.com/gitleaks/gitleaks/releases/download/${GITLEAKS_TAG}/gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" "$TEMP_DIR/gitleaks.tar.gz"
 mkdir -p "$TEMP_DIR/gitleaks-extract"
 tar -xzf "$TEMP_DIR/gitleaks.tar.gz" -C "$TEMP_DIR/gitleaks-extract" gitleaks
 install -m 0755 "$TEMP_DIR/gitleaks-extract/gitleaks" "$HOME/.local/bin/gitleaks"
fi
if should_install argocd; then
 fetch "https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-${ARGO_ARCH}" "$TEMP_DIR/argocd"
 install -m 0755 "$TEMP_DIR/argocd" "$HOME/.local/bin/argocd"
fi
if ((ACM_CLI)) && should_install clusteradm; then
 log 'Installing upstream OCM clusteradm (distinct from Red Hat ACM tooling)'
 fetch "https://github.com/open-cluster-management-io/clusteradm/releases/latest/download/clusteradm_linux_${CLUSTERADM_ARCH}.tar.gz" "$TEMP_DIR/clusteradm.tar.gz"
 mkdir -p "$TEMP_DIR/clusteradm-extract"
 tar -xzf "$TEMP_DIR/clusteradm.tar.gz" -C "$TEMP_DIR/clusteradm-extract"
 CLUSTERADM_BINARY="$(find "$TEMP_DIR/clusteradm-extract" -type f -name clusteradm -print -quit)"
 [[ -n "$CLUSTERADM_BINARY" ]] || { echo 'clusteradm archive did not contain a clusteradm binary' >&2; exit 1; }
 install -m 0755 "$CLUSTERADM_BINARY" "$HOME/.local/bin/clusteradm"
fi

fi

if ((CONFIG_SANDBOX)) && phase sandbox "Claude native sandbox configuration"; then
 log 'Configuring Claude native sandbox without overwriting other settings'
 mkdir -p "$HOME/.claude"
 SETTINGS="$HOME/.claude/settings.json" python3 - <<'PY'
import json, os, pathlib, sys
p=pathlib.Path(os.environ['SETTINGS'])
try:
    settings=json.loads(p.read_text()) if p.exists() else {}
except (ValueError, UnicodeDecodeError) as e:
    print(f'Invalid Claude settings JSON: {e}. Leaving existing file untouched.', file=sys.stderr)
    sys.exit(1)
if not isinstance(settings,dict):
    sys.exit('Claude settings must be a JSON object.')
settings.setdefault('sandbox', {})
if not isinstance(settings['sandbox'],dict):
    sys.exit('Claude sandbox settings must be a JSON object.')
for key, value in {'enabled':True,'autoAllowBashIfSandboxed':True,'failIfUnavailable':True,'allowUnsandboxedCommands':False}.items():
    settings['sandbox'].setdefault(key,value)
if p.exists():
    backup=p.with_name(p.name+'.bak-wsl-ai-toolkit')
    backup.write_bytes(p.read_bytes())
import tempfile,os
fd,tmp=tempfile.mkstemp(prefix='.claude-settings-',dir=p.parent)
with os.fdopen(fd,'w') as f:
    json.dump(settings,f,indent=2); f.write('\n')
    f.flush(); os.fsync(f.fileno())
os.chmod(tmp,0o600); os.replace(tmp,p)
PY
fi

if ((DEVOPS)) && phase devops "optional kubectl, Helm, Terraform, OpenTofu and Ansible"; then
 log 'Installing optional DevOps tools: kubectl, Helm, Terraform, OpenTofu, Ansible'
 # Kubernetes: download binaries and matching checksum from the official distribution service.
 if should_install kubectl; then
 KVER="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
 case "$(uname -m)" in x86_64) KARCH=amd64;; aarch64) KARCH=arm64;; *) echo 'Unsupported kubectl CPU architecture' >&2; exit 1;; esac
 fetch "https://dl.k8s.io/release/${KVER}/bin/linux/${KARCH}/kubectl" "$TEMP_DIR/kubectl"
 fetch "https://dl.k8s.io/release/${KVER}/bin/linux/${KARCH}/kubectl.sha256" "$TEMP_DIR/kubectl.sha256"
 (cd "$TEMP_DIR" && printf '%s  kubectl\n' "$(cat kubectl.sha256)" | sha256sum --check --status)
 install -m 0755 "$TEMP_DIR/kubectl" "$HOME/.local/bin/kubectl"
 fi
 # Official Helm apt repository is managed by Buildkite; prefer signed release archive via upstream installer.
 if should_install helm; then
 fetch https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 "$TEMP_DIR/get-helm-3"
 chmod +x "$TEMP_DIR/get-helm-3"
 HELM_INSTALL_DIR="$HOME/.local/bin" USE_SUDO=false "$TEMP_DIR/get-helm-3"
 fi
 # HashiCorp signed apt repo for Terraform.
 fetch https://apt.releases.hashicorp.com/gpg "$TEMP_DIR/hashicorp.asc"
 gpg --batch --yes --dearmor -o "$TEMP_DIR/hashicorp.gpg" "$TEMP_DIR/hashicorp.asc"
 sudo install -m 0644 "$TEMP_DIR/hashicorp.gpg" /usr/share/keyrings/hashicorp-archive-keyring.gpg
 printf 'deb [arch=%s signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com %s main\n' "$ARCH" "$CODENAME" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
 sudo apt-get update
 sudo DEBIAN_FRONTEND=noninteractive apt-get install -y terraform
 # OpenTofu: pinned release, checksum file signed by the OpenTofu key (fingerprint pinned here).
 if should_install tofu; then
 TOFU_VERSION=1.12.6
 TOFU_FPR='E3E6 E43D 84CB 852E ADB0  051D 0C0A F313 E5FD 9F80'
 TOFU_BASE="https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}"
 fetch "${TOFU_BASE}/tofu_${TOFU_VERSION}_linux_${ARCH}.zip" "$TEMP_DIR/tofu_${TOFU_VERSION}_linux_${ARCH}.zip"
 fetch "${TOFU_BASE}/tofu_${TOFU_VERSION}_SHA256SUMS" "$TEMP_DIR/tofu_${TOFU_VERSION}_SHA256SUMS"
 fetch "${TOFU_BASE}/tofu_${TOFU_VERSION}_SHA256SUMS.gpgsig" "$TEMP_DIR/tofu.gpgsig"
 fetch https://get.opentofu.org/opentofu.asc "$TEMP_DIR/opentofu.asc"
 gpg --show-keys --with-fingerprint "$TEMP_DIR/opentofu.asc" | grep -qF "$TOFU_FPR" || { echo 'OpenTofu signing key fingerprint mismatch' >&2; exit 1; }
 gpg --batch --no-default-keyring --keyring "$TEMP_DIR/opentofu.kbx" --import "$TEMP_DIR/opentofu.asc" 2>/dev/null
 gpg --batch --no-default-keyring --keyring "$TEMP_DIR/opentofu.kbx" --verify "$TEMP_DIR/tofu.gpgsig" "$TEMP_DIR/tofu_${TOFU_VERSION}_SHA256SUMS"
 (cd "$TEMP_DIR" && sha256sum --check --status --ignore-missing "tofu_${TOFU_VERSION}_SHA256SUMS")
 python3 -m zipfile -e "$TEMP_DIR/tofu_${TOFU_VERSION}_linux_${ARCH}.zip" "$TEMP_DIR/tofu-extract"
 install -m 0755 "$TEMP_DIR/tofu-extract/tofu" "$HOME/.local/bin/tofu"
 fi
 if pipx list --short 2>/dev/null | grep -q "^ansible "; then pipx upgrade ansible; else pipx install ansible --include-deps; fi
 # oc intentionally not auto-installed: obtain the version compatible with your OpenShift fleet.
fi

# GitHub + Azure DevOps integrations: never print or persist access tokens in this script.
if phase git-config 'Git identity, Azure DevOps defaults and workflow helper'; then
log 'Configuring Git identity and optional Azure DevOps cloud defaults'
if [[ -n "$GIT_NAME" ]]; then git config --global user.name "$GIT_NAME"; fi
if [[ -n "$GIT_EMAIL" ]]; then git config --global user.email "$GIT_EMAIL"; fi
if [[ -n "$AZ_ORG" ]]; then
 if [[ "$AZ_ORG" != https://dev.azure.com/* && "$AZ_ORG" != https://*.visualstudio.com* ]]; then
  echo 'Azure DevOps organization must be a cloud URL (https://dev.azure.com/... or https://*.visualstudio.com/...).' >&2; exit 2
 fi
 if [[ -n "$AZ_PROJECT" ]]; then
  az devops configure --defaults "organization=$AZ_ORG" "project=$AZ_PROJECT"
 else
  az devops configure --defaults "organization=$AZ_ORG"
 fi
elif [[ -n "$AZ_PROJECT" ]]; then
 echo 'Warning: --azure-project ignored unless --azure-org is also set' >&2
fi

# Workflow helper: commands are explicit, particularly push/PR/merge/pipeline.
cat > "$HOME/.local/bin/ai-git-workflow" <<'WORKFLOW'
#!/usr/bin/env bash
set -Eeuo pipefail
usage() {
 cat <<'DOC'
Usage: ai-git-workflow COMMAND [ARG]
  status                     Show Git branch, GitHub auth and PR checks
  branch NAME                Create a local feature branch
  publish                    Explicitly push current branch upstream
  pr                         Explicitly create GitHub PR from pushed branch
  checks                     View PR checks
  runs                       View recent GitHub Actions workflow runs
  watch RUN_ID               Follow a GitHub Actions run
  merge NUMBER               Explicitly squash-merge selected GitHub PR
  pipelines                  List Azure DevOps Services pipelines
  pipeline-runs              List Azure DevOps Services pipeline runs
No automatic merges, pushes or pipeline triggers. For Azure DevOps Server/TFS
(on-prem), use a supported Git remote or version-compatible REST API instead.
DOC
}
case "${1:-}" in
 status) git status -sb; gh auth status; gh pr checks || true;;
 branch) [[ $# == 2 ]] || { usage; exit 2; }; git switch -c "$2";;
 publish) git push -u origin "$(git branch --show-current)";;
 pr) gh pr create --base main --fill;;
 checks) gh pr checks;;
 runs) gh run list;;
 watch) [[ $# == 2 ]] || { usage; exit 2; }; gh run watch "$2";;
 merge) [[ $# == 2 && "$2" =~ ^[0-9]+$ ]] || { usage; exit 2; }; gh pr merge "$2" --squash --delete-branch;;
 pipelines) az pipelines list --output table;;
 pipeline-runs) az pipelines runs list --output table;;
 -h|--help|help|'') usage;;
 *) usage; exit 2;;
esac
WORKFLOW
chmod 0755 "$HOME/.local/bin/ai-git-workflow"

fi

# Each authentication is independent and opt-in. --setup-auth also asks separately.
# No OAuth/device flow is started by simply running installation steps.
if ((SKIP_AUTH)); then
 echo 'Skipping GitHub and Azure authentication (--skip-auth).'
else
 if [[ "$AUTH_GH" == "login" || "$AUTH_AZ" == "login" ]] && [[ ! -r /dev/tty ]]; then
  echo 'Explicit authentication requires an interactive terminal.' >&2; exit 2
 fi
 if [[ ",${SKIP_STEPS}," == *",auth-github,"* || "$AUTH_GH" == "skip" ]]; then
  echo 'Skipping GitHub authentication.'
 elif [[ "$AUTH_GH" == "login" ]] || ask_yes_no 'Authenticate GitHub now?'; then
  log 'GitHub authentication'
  if ! command -v gh >/dev/null 2>&1; then
   echo 'gh not installed; skipping GitHub authentication.'
  elif gh auth status --hostname github.com >/dev/null 2>&1; then
   echo 'GitHub account already connected:'
   gh auth status --hostname github.com
   gh auth setup-git --hostname github.com
  else
   gh auth login --hostname github.com --git-protocol https --web
   gh auth setup-git --hostname github.com
  fi
 else
  echo 'Skipping GitHub authentication.'
 fi
 if [[ ",${SKIP_STEPS}," == *",auth-azure,"* || "$AUTH_AZ" == "skip" ]]; then
  echo 'Skipping Azure authentication.'
 elif [[ "$AUTH_AZ" == "login" ]] || ask_yes_no 'Authenticate Azure now?'; then
  log 'Azure authentication'
  if ! command -v az >/dev/null 2>&1; then
   echo 'az not installed; skipping Azure authentication.'
  elif az account show --output none >/dev/null 2>&1; then
   echo 'Azure session already available:'
   az account show --query '{name:name,tenantId:tenantId,user:user.name}' -o table
   if [[ "$AUTH_AZ" == "login" ]] && ask_yes_no 'Sign in with a different Azure account?'; then
    az login --use-device-code
   fi
  else
   echo 'No active Azure session. Starting device-code login.'
   az login --use-device-code
  fi
  if [[ -n "$AZ_ORG" ]] && command -v az >/dev/null 2>&1; then
   DEVOPS_ARGS=(--organization "$AZ_ORG")
   if [[ -n "$AZ_PROJECT" ]]; then DEVOPS_ARGS+=(--project "$AZ_PROJECT"); fi
   az devops project show "${DEVOPS_ARGS[@]}" --query name -o tsv || \
    echo 'Azure DevOps access could not be verified; check permissions.'
  fi
 else
  echo 'Skipping Azure authentication.'
 fi
fi

log 'Installed command versions'
for cmd in git gh az node npm claude codex gemini uv yq bwrap socat zsh gitleaks argocd clusteradm kubectl helm terraform ansible; do
 if command -v "$cmd" >/dev/null 2>&1; then
  printf '%-12s %s\n' "$cmd" "$(command -v "$cmd")"
 else
  printf '%-12s %s\n' "$cmd" 'not installed (or needs a new shell)'
 fi
done
cat <<'NEXT'

Done. Each installation phase and authentication can be skipped interactively; --yes suppresses questions, --skip-auth skips both logins. New interactive WSL shells start in ~/projects. Passwordless sudo is configured unless --no-sudo-nopasswd was used.
Open a NEW WSL shell and authenticate interactively when you choose:
  claude
  codex
  gemini
  gh auth login --hostname github.com --git-protocol https --web
  gh auth setup-git
  gh auth status
  az login
  # Or re-run with --setup-auth to launch both logins

Then in Claude Code run /sandbox to verify sandbox functionality.
For Zsh: zsh (or rerun with --default-shell zsh). For Bash: bash.
Quick GitHub and Azure DevOps workflow reference: ai-git-workflow --help
Do NOT copy ~/.claude, ~/.codex, ~/.gemini, ~/.azure or ~/.config/gh
between work and personal WSL distributions.
NEXT
