# Contributing

## Scope

Changes should preserve the approved terminal-rendering lifecycle, SponsorBar protocol compatibility, and production safety checks. Do not add ways to bypass account eligibility, lease expiry, interactive-terminal requirements, or completion timing.

## Before opening a pull request

```sh
swift format lint --recursive Sources Tests Package.swift
swift test
swift build -c release
```

Add tests for protocol model, signing canonicalization, lifecycle, or command-line changes. Tests must use synthetic values and must not contact SponsorBar.

## Sensitive data

Never commit:

- SponsorBar bearer tokens or device IDs
- Secure Enclave or exported private-key material
- Keychain exports
- Real signed request headers
- Production API captures containing account or campaign data

Use obvious placeholders such as `device`, `token`, and `signature` in fixtures.
