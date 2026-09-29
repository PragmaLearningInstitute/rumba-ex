# Security and data handling

This public edition excludes secrets, participant sessions, private account records, production database exports and installed dependencies. Never add those files in an issue or pull request. Use fictional examples for reproduction.

A source review and focused regression tests were performed during preparation. The review was partial and does not certify the absence of vulnerabilities. `VALIDATION.md` records what was tested. Dependency versions and deployment configuration still require review in each environment.

## Report a vulnerability

If GitHub displays **Report a vulnerability** under this repository's Security tab, use that private reporting channel. Otherwise contact the maintainer through the contact details published on [Pragma Learning Institute](https://pragmalearninginstitute.com/) and request a private channel before sharing sensitive details. Do not put exploitable details, credentials or participant data into a public issue. No response-time guarantee is made by this file.

Provide the affected version or commit, component, prerequisites, expected security property and a minimal demonstration using synthetic data. Explain the impact separately from assumptions. Never test against the hosted PLI service without separate authorization.

## Operating boundaries

Run demonstrations locally with fictional data. Protect server credentials outside Git, keep dependencies current and restrict access to locally saved files. Browser third-party assets may require network access. Review optional telemetry and sensors before enabling them. The applications are research and educational tools, not validated clinical or diagnostic instruments.
