# Security policy

## Reporting a vulnerability

Please do not open a public issue. Report vulnerabilities privately through GitHub's
**Security → Report a vulnerability** on this repository. Include the affected version and steps
to reproduce. We aim to acknowledge reports within five business days.

## Supported versions

Security fixes are released for the latest minor version.

## Handling of sensitive data

- Client secrets and access tokens are kept in process memory only. They are never written to
  logs, files, caches or exception messages.
- Exception messages contain the host, HTTP status and error code only, never response bodies,
  recipients or message content.
- Do not commit tenant ids, client ids, secrets or real mailbox addresses to issues or pull
  requests.
