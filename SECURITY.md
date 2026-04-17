# Security Policy

## 지원 버전 (Supported Versions)

| Version | Supported |
|---|---|
| main (v7.1+) | Yes |
| v7.0 and below | No — please upgrade |

Only the `main` branch and releases tagged **v7.1 or later** receive security fixes.

---

## Reporting a Vulnerability / 취약점 신고

**Do NOT open a public GitHub Issue for security vulnerabilities.**

Use **GitHub Private Vulnerability Reporting**:

1. Go to the repository's **Security** tab.
2. Click **"Report a vulnerability"** under **Advisories**.
3. Fill in the form with steps to reproduce, impact assessment, and any proof-of-concept.

We will acknowledge your report within **30 days** and work with you toward coordinated disclosure.

취약점은 공개 Issue가 아닌 위 Private Advisories 경로로만 신고해 주세요.

---

## Disclosure Timeline

| Milestone | Target |
|---|---|
| Acknowledgment | 30 days from report |
| Status update | 60 days from report |
| Coordinated disclosure | After fix is released or 90 days, whichever comes first |

---

## Scope

**In scope** — vulnerabilities in:
- Template files shipped by this repository (`.claude/`, `.omc/`, `install.sh`, agent/hook/skill templates)
- `install.sh` installation script

**Out of scope:**
- Projects generated *by* this template — those are downstream repositories owned by their respective maintainers. Report issues in those repos.
- Bugs or vulnerabilities in **Claude Code itself** — report those directly to [Anthropic](https://www.anthropic.com/contact).
- Social engineering or phishing attacks.

---

## Thank You

We appreciate responsible disclosure and will credit reporters (with permission) in our release notes.
