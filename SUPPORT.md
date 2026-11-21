# Support

## Where to ask

Ask usage and setup questions in this repository's issues using the issue templates. Keep the discussion in the repository rather than in private messages: a public thread becomes documentation for the next person with the same hardware question.

Before opening an issue, check:

- The [README](README.md) and [Chinese README](README.zh-CN.md)
- [hardware compatibility](docs/COMPATIBILITY.md), especially for Touch Bar availability and fan control
- Existing open and closed issues
- [CONTRIBUTING.md](CONTRIBUTING.md) if you plan to propose a change
- [SECURITY.md](SECURITY.md) if the problem might be a vulnerability

## What to include

- GoodBar version and build
- Mac model identifier, architecture (`arm64` or `x86_64`), and Touch Bar mode (Auto / On / Off)
- macOS version
- Expected and actual behavior, with concise reproduction steps
- Redacted diagnostics only

Hardware behavior cannot be confirmed by CI alone. The automated checks do not prove physical Touch Bar presentation, media player response, or real fan-write behavior, so describe what you observed on the actual machine.

## What never belongs in an issue

Credentials, private session files, tokens, full user directories, unredacted diagnostics, or real user data. Connect this rule to [SECURITY.md](SECURITY.md): use private reporting for anything sensitive.

## Response expectations

This project is maintained in spare time with limited weekly hours and no response SLA. If nothing has happened after seven days, a polite comment on the same thread is appropriate. Out-of-scope requests may be closed with a short explanation and a reference to CONTRIBUTING.md rather than left open indefinitely.
