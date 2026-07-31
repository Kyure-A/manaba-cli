# manaba-cli

[![CI](https://github.com/Kyure-A/manaba-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/Kyure-A/manaba-cli/actions/workflows/ci.yml)
[![Live smoke test](https://github.com/Kyure-A/manaba-cli/actions/workflows/live-smoke.yml/badge.svg)](https://github.com/Kyure-A/manaba-cli/actions/workflows/live-smoke.yml)

An OCaml CLI for the University of Tsukuba [manaba](https://manaba.tsukuba.ac.jp/),
tested against manaba 2.979 as of July 2026. It automates the same HTTPS and HTML
forms as the browser because manaba does not provide a public API.

Passwords are never stored. Session cookies are saved with mode `0600` under
`$XDG_CONFIG_HOME/manaba-cli/session.json`, or `~/.config/manaba-cli/session.json`.

## Build

```console
nix develop
dune build @all
dune runtest
dune fmt
```

Build or run directly through Nix:

```console
nix build
nix run . -- --help
```

CI builds and tests the flake and opam package on Linux and macOS. A scheduled
smoke test also checks the live SAML login entry point.

## Authentication

```console
manaba auth login -u USERNAME
Password:
manaba auth status
logged in
manaba auth logout
```

Use `--password-stdin` for automation or `--password-clipboard` on macOS. Set
`MANABA_SESSION` or pass `--session FILE` to change the session path.

## Commands

```console
manaba courses
manaba tasks
manaba course COURSE_ID
manaba news COURSE_ID
manaba quizzes COURSE_ID
manaba surveys COURSE_ID
manaba reports COURSE_ID
manaba projects COURSE_ID
manaba topics COURSE_ID
manaba contents COURSE_ID
manaba grades COURSE_ID
manaba submissions
manaba portfolio
manaba reminders
manaba memos
manaba settings
```

List commands support `--json`. Other browser features are available through:

- `get`, `links`, and `download` for pages and attachments
- `report submit/cancel` for report submission and withdrawal
- `thread create`, `memo set`, and `profile set` for content changes
- `favorite`, `display-count`, and `registration` for preferences and enrollment
- `forms`, `submit`, and `flow` for HTML forms without a dedicated command

Run `manaba COMMAND --help` for arguments and options.

### Examples

```console
manaba download 'course_123_page_456/file.pdf' -o file.pdf
manaba report submit COURSE_ID REPORT_ID answer.pdf
manaba report cancel COURSE_ID REPORT_ID
manaba thread create COURSE_ID 'Subject' 'Body'
manaba registration search --code GE --name 'Seminar'
```

Inspect and submit an unsupported form:

```console
manaba forms --json 'course_123_topics?action=newthread'
manaba submit 'course_123_topics?action=newthread' --form 1 \
    --field 'Title=Subject' --field 'Body=Message'
```

`forms` hides token values. `submit` carries hidden fields forward automatically;
use `--file NAME=PATH` for uploads and `--button NAME` when a form has multiple
submit buttons. When `--button` is set, the form is selected by that button name
(useful when form 1 is a Google Calendar widget). Use `flow PATH PLAN.json` for
multi-page confirmation flows.

For multi-step quizzes/drills whose answer form appears only after `スタート`:

```console
manaba submit --yes --forms-json --button action_DrillStudent_querystart \
  'course_123_drill_456'
manaba flow --yes 'course_123_drill_456' plan.json
```

Flow plan steps may include `"auto": "first-choice"` to pick the first
radio/select option, and `--forms-json` on `submit`/`flow` prints the response
forms as JSON instead of page text.

Mutating commands ask for confirmation unless `--yes` is supplied.

## Security and limitations

- Requests are restricted to the configured manaba origin.
- Cookies are stored locally; passwords are not.
- HTML changes or institution-specific pages may require parser updates.
- JavaScript-only actions need a corresponding HTML form to be automated.

## License

GPL-3.0-only
