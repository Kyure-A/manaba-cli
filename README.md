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

### Structured assignment and submission details

```console
manaba quiz show COURSE_ID QUIZ_ID --json
manaba drill show COURSE_ID DRILL_ID --json
manaba survey show COURSE_ID SURVEY_ID --json
manaba report show COURSE_ID REPORT_ID --json
manaba assignment 'course_123_query_456' --json
manaba assignment --from-state /tmp/quiz.json --json
```

The shared view includes `kind`, IDs, `title`, `deadline`, `resubmission`,
`status`, `submitted_at`, `answer_count`, `file_count`, `submitted_files`,
`questions`, `facts`, public `forms`, and `warnings`. Metadata comes from
recognized labels in two-column table rows or definition lists. Unknown or
conflicting values are `null`; a missing file/answer count is never assumed to
be zero. Dates remain the server's original text, without a guessed timezone.
`facts` retains observed label/value pairs for diagnosing unsupported labels.

Question groups use the observed `qidN` control names. Prompts and option labels
are included when semantic labels or fieldset legends identify them; unobserved
prompts stay `null`. Hidden/password control values are redacted. A page may
contain only some questions, or only a start button. These commands do not start
an attempt or claim all questions have been collected. `assignment --from-state`
reads a saved post-start response without network requests or consuming it.

`report submit --json COURSE_ID REPORT_ID FILE` verifies the requested basename
on the upload preview, confirms once, then independently fetches the report.
Success requires a submitted status and the exact preview file-name set; file
counts must agree whenever displayed. An unchanged observed submission time or
an indistinguishable earlier same-name submission is rejected. The result's
`verification` is `fresh_status_and_files_match`, with `expected_files`, nullable
`timestamp_changed`, and the structured `assignment`. Missing server timestamps
and counts remain explicitly flagged; this does not verify file bytes or prove
a unique receipt ID. A failure after upload/commit may have changed the server:
inspect the current state instead of retrying automatically.

Parser regression tests use synthetic semantic HTML and local HTTP fixtures;
they do not claim coverage of every institution's markup. Unrecognized submitted
file markup stops automatic report confirmation instead of claiming success.

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

`flow` re-runs its whole plan from a fresh fetch, so its first step presses
`スタート` again. manaba mints new hidden tokens on every entry and restarts the
quiz's 経過時間 from that entry, so a plan that enters and submits in one run
records only the seconds the run itself took. To spend real time on a quiz
between entering it and submitting, save the response and resume from it:

```console
manaba submit --yes --button action_QueryStudent_querystart \
  --save-state /tmp/quiz.json 'course_123_query_456'
# read the material and write the answer here; the clock is running
manaba submit --yes --from-state /tmp/quiz.json --form 1 \
  --button action_QueryStudent_queryshow_confirm --field "qid1=$(cat answer.txt)" \
  --save-state /tmp/quiz-confirm.json
manaba submit --yes --from-state /tmp/quiz-confirm.json --form 1 \
  --button action_QueryStudent_querydone
```

`--from-state` submits the form held in the saved response instead of fetching
`PATH` again, so the quiz is never re-entered and the recorded 経過時間 covers
the work. `PATH` and `--from-state` are mutually exclusive. State files are
written with mode 0600 because the saved page carries its hidden form tokens;
they are single-use, since submitting invalidates those tokens.

Mutating commands ask for confirmation unless `--yes` is supplied.

## Security and limitations

- Requests are restricted to the configured manaba origin.
- Cookies are stored locally; passwords are not.
- Each HTTP request (including redirects and body reading) has a 30-second
  timeout, with no automatic retry. A timed-out write may already have applied.
- HTML changes or institution-specific pages may require parser updates.
- JavaScript-only actions need a corresponding HTML form to be automated.

## License

GPL-3.0-only
