# Security Policy

## Reporting a Vulnerability

We take security seriously. If you discover a vulnerability, please report it responsibly.

### How to Report

**Do NOT** create a public GitHub issue for security vulnerabilities.

Instead, please:

1. Email: Open a private security advisory at [GitHub Security](https://github.com/oxFFFF-Q/openclaw-migrate/security/advisories/new)
2. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### What to Include

- Type of vulnerability (XSS, injection, etc.)
- Affected versions
- Proof of concept (if safe to share)
- Your contact info (optional)

### Response Time

- **Initial response**: Within 48 hours
- **Status update**: Weekly until resolved
- **Fix timeline**: Depends on severity (critical: 7 days, high: 30 days)

## Security Best Practices

When using this tool:

### ✅ DO
- Verify archive checksums before importing
- Backup existing configuration before import
- Review manifest.json content
- Use `--mode=replicate` for sharing between machines

### ❌ DON'T
- Import archives from untrusted sources
- Use `--mode=full` when exporting sensitive data
- Share your `~/.openclaw/` directory publicly
- Import without reviewing the manifest

## Supported Versions

| Version | Security Updates |
| ------- | ---------------- |
| 1.x.x   | ✅ Active        |
| < 1.0   | ❌ End of life   |

## Disclosure Policy

We follow [responsible disclosure](https://en.wikipedia.org/wiki/Responsible_disclosure):

1. Report privately first
2. Allow reasonable time to fix
3. Coordinated public disclosure after fix

Thank you for keeping OpenClaw Migration Tool secure! 🔒
