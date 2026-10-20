# AGENTS.md

Conventions for AI agents working in this repository. Account-wide rules (roles, separation
of duties, forbidden actions, security) live in `~/.ai/` on the maintainer's machine and are
not repeated here. Shared CI, versioning and branch policy come from
[github-standards](https://github.com/xxarequipenoxx/github-standards).

## What this repository is

Bootstrap for Ubuntu 22.04/24.04 on WSL2: one Bash script, run once per distribution as a
normal user, that installs the AI coding agents (Claude Code, Codex, Gemini), GitHub and
Azure CLIs, developer and security utilities, optional DevOps tooling (`--devops`), Zsh with
Oh My Zsh and Oh My Bash, and an optional sandbox configuration for Claude Code. It is meant
for the maintainer's work and personal WSL distributions. The repository is public: never add
employer identifiers (hostnames, organisation or project names, internal URLs).

## Binding rules

- Code, comments, commit messages and documentation are written in English.
- Conventional Commits, checked by commitizen (`.cz.toml`). The pull request title becomes
  the squash commit on `main`, so it is conventional too and it drives the version bump:
  `feat` bumps the minor, `fix` and `perf` the patch; other types release nothing.
- No AI attribution anywhere: no `Co-Authored-By` trailer naming an AI vendor, no
  "generated with" footer, in commits, pull request titles, bodies or code comments.
- Never commit on `main`, never merge: open a pull request, the human merges.
- Versions come from Git tags only; never write a version number into a file.
- Workflows stay thin callers of github-standards. Any local workflow pins third-party
  actions by full commit SHA with a `# vX.Y.Z` comment, sets `permissions: {}` at the top
  and least privilege per job, and passes user-controlled values through `env:`.
- Never commit secrets and never hard-code a token in the script: every login stays
  interactive and user-initiated.
- The script must stay idempotent and safe to re-run; it must not replace existing dotfiles.
- Run `pre-commit run --all-files` and `shellcheck` on the scripts before opening a pull
  request.

## Layout

| Path | Content |
|---|---|
| `wsl-ubuntu-bootstrap/bootstrap.sh` | the bootstrap script: option parsing, then one prompted phase per component (`--skip-step NAME`) |
| `wsl-ubuntu-bootstrap/README.md` | usage, options, authentication and security notes |
| `.github/workflows/` | `pr.yml` (commits, security, shellcheck), `release.yml` |

## Commands

| Command | What it does |
|---|---|
| `pre-commit install` | install the pre-commit and commit-msg hooks (`default_install_hook_types`) |
| `pre-commit run --all-files` | run every hook on all files |
| `shellcheck wsl-ubuntu-bootstrap/bootstrap.sh` | lint the script, as the `shellcheck` job does |
| `bash wsl-ubuntu-bootstrap/bootstrap.sh --help` | list the bootstrap options |
