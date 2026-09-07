# Security Policy

## Reporting a vulnerability

Report security issues privately through [GitHub Security Advisories](https://github.com/rohan-patra/sponsorbar-terminal/security/advisories/new). Do not open a public issue for vulnerabilities involving authentication, request signing, Keychain access, impression completion, or account eligibility.

Do not include live bearer tokens, device identifiers, private keys, signed request headers, or unredacted production responses in a report. Revoke or rotate any credential that may have been exposed.

## Credential handling

The client reads SponsorBar credentials from macOS Keychain at runtime. It does not contain default credentials, write credentials to logs, or persist them in repository files. Device request signatures are generated with a non-exportable Secure Enclave P-256 key when supported by the host Mac.

## Supported versions

This repository currently contains a proof of concept rather than versioned releases. Security fixes apply to the latest commit on the default branch.
