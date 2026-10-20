# Security policy

## Reporting a vulnerability

Do not open a public issue. Use GitHub's private vulnerability reporting (Security tab,
"Report a vulnerability") or contact the maintainer directly. Expect an answer within a
week.

## Practices in this repository

- Secrets never enter Git: the bootstrap script contains no credential and never stores
  one; every login it offers is interactive. gitleaks runs in the pre-commit hooks and on
  every pull request.
- Shell scripts are checked with shellcheck on every pull request.
- Third-party GitHub Actions are pinned by commit SHA; workflows are audited with zizmor and
  run with least-privilege permissions.
- Dependencies are updated through Renovate pull requests and gated by the required checks.
