# Security

## Supported versions

Only the latest release gets fixes.

## Reporting a vulnerability

Report it privately through [GitHub Security Advisories](https://github.com/oddurs/common-keys/security/advisories/new), not in a public issue.

You'll get an acknowledgement within a week. If the report is confirmed, a fix ships in a new release and the advisory is published with credit, unless you'd rather stay anonymous.

LangSmart needs Accessibility access because it reads key presses through an event tap and types fixes back. It makes no network connections. What it learns stays in `~/Library/Application Support/LangSmart/` on your Mac. Reports about anything that could leak typed text, or let another process drive the event tap, are the most valuable.
