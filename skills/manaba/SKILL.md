---
name: manaba
description: Operate Kyre's University of Tsukuba manaba account through the canonical GitHub Nix flake. Use whenever a request mentions manaba, courses, pending assignments, reports, quizzes, surveys, submissions, grades, course news or content, attachments, reminders, portfolio, registration, bulletin-board posts, memos, profile settings, favorites, or asks to submit, cancel, download, post, enroll, or change anything in manaba. Resolve human names to CLI IDs, prefer structured reads, and handle account mutations safely.
---

# manaba

Use the canonical GitHub flake of `manaba` as the execution layer. Begin with
the requested operation instead of rereading the repository or README.

## Use only the canonical GitHub flake

Prefix every direct command with:
`nix run github:Kyure-A/manaba-cli --`

- Never run the PATH/global `manaba`, probe it with `command -v`, or use a local
  checkout or local flake. Kyre's installed binary is a known legacy CLI with
  an incompatible interface.
- Require both Nix and resolution of `github:Kyure-A/manaba-cli`. If Nix is
  unavailable or the GitHub flake cannot be resolved, report that exact blocker
  instead of substituting another binary or checkout.
- Treat the GitHub flake's `COMMAND --help=plain` output as the source of truth
  for exact arguments. Consult source files only when the help is insufficient.

Do not change `--base-url` unless the user explicitly requests another manaba
instance or a test server. Preserve `MANABA_SESSION` when it is already set.

## Authenticate

Run canonical `auth status` once before the first authenticated operation in a
task. If the session is logged out, expired, or an authenticated request reports
that login is required, recover it through Kyre's existing Bitwarden Secrets
Manager adapter:

```sh
cd /Users/kyre/ghq/github.com/Kyure-A/self
nix develop -c npm run self -- secrets exec -- \
  npm run self -- university login
```

Then verify canonical `auth status` and resume the original request.

- Never ask Kyre to log in manually or re-provide credentials while this
  recovery path is available.
- Never request or display a password, inspect the session file, print secret
  environment variables, or put credentials directly in shell arguments.
- If recovery fails, report the exact failing layer only after the managed path
  has actually been attempted. Do not replace it with an interactive login.
- The CLI stores only session cookies, normally under
  `~/.config/manaba-cli/session.json`.

## Read data

Execute read-only requests without extra confirmation. Prefer `--json` wherever
the command supports it, then interpret the result rather than exposing raw JSON.

Use these direct mappings:

- courses or a course name: `courses --json`
- pending work or deadlines: `tasks --json`
- course overview: `course COURSE_ID --json`
- news: `news COURSE_ID --json`
- quizzes or drills: `quizzes COURSE_ID --json`
- surveys: `surveys COURSE_ID --json`
- reports: `reports COURSE_ID --json`
- projects: `projects COURSE_ID --json`
- topics: `topics COURSE_ID --json`
- course content: `contents COURSE_ID --json`
- grades: `grades COURSE_ID`
- submission history: `submissions`
- portfolio, reminders, memos, or settings: use the same-named command
- self-registerable course search: `registration search` with filters from its
  `--help=plain`
- links on a page: `links --json PATH`
- page text: `get PATH`

When the user supplies a course name rather than `COURSE_ID`, run `courses
--json` and resolve it. When the user supplies an assignment name rather than an
ID, list the relevant course items and resolve it. Ask the user to choose only
when multiple plausible matches remain; never guess an ambiguous target.

Preserve exact course names, assignment names, statuses, and deadlines in the
answer. Clearly distinguish values returned by manaba from any inference.

## Download files

Use `links --json PATH` to discover the exact attachment path when needed, then
use `download PATH --output FILE`. Confirm the intended output path when it is
ambiguous, avoid overwriting an existing file without authorization, and return
a clickable absolute path to the downloaded file.

## Change data

Treat report submission or cancellation, thread creation, memo or profile
updates, favorite changes, display count changes, registration by key, generic
form submission, and flows as account mutations. Treat `registration search` as
read-only.

Before a mutation:

1. Resolve and verify every target ID.
2. Inspect any local upload file and confirm that it exists.
3. Present the exact course, item, file, and requested change when the user's
   request has not already authorized that exact operation.
4. After authorization, pass `--yes` so the non-interactive command does not
   wait at its own confirmation prompt.
5. Report the CLI result. Do not retry a failed mutation unless the result makes
   it clear that no change occurred.

Use dedicated commands when available, such as:

```text
report submit COURSE_ID REPORT_ID FILE
report cancel COURSE_ID REPORT_ID
thread create COURSE_ID SUBJECT BODY
```

For an unsupported action, inspect the page with `forms --json PATH` first.
Use `submit` or `flow` only when no dedicated command exists and the requested
mutation is explicit. Let the CLI carry hidden fields forward; never attempt to
extract or reveal hidden token values.

When `--button NAME` is passed to `submit`, the CLI selects the form that
contains that button. Do not assume form index 1 is the assignment form; many
course pages put a Google Calendar widget first.

### Handle multi-step quizzes and drills

Treat a quiz/drill that exposes only `スタート` on `GET` as a multi-step form.
The answer form may exist only in the response to that start `POST`; running
`get` or `forms --json` against the original path afterward can return the
start page again. This is an inspection limitation, not evidence that the
question or saved attempt disappeared.

- Prefer one `flow` from the original quiz/drill path so cookies, hidden
  controls, intermediate response bodies, and changed form actions carry
  forward.
- Do not split the attempt into unrelated `submit` calls, guess `qid*` names or
  button names, or inspect the session cookie.
- To inspect the post-start answer form without guessing, use
  `submit --yes --forms-json --button START_BUTTON PATH` or
  `flow --yes --forms-json PATH PLAN.json`. `--forms-json` prints the response
  forms as JSON instead of main text. Unchecked radios expose their wire
  values under each control's `options` array.
- Flow steps may set `"auto": "first-choice"` to pick the first radio/select
  option for each unanswered field before applying explicit `fields`. Use this
  only when exact answers are not required.
- Observed quiz sequence (verify per target):
  `action_QueryStudent_querystart` → answer field such as `qid1` plus
  `action_QueryStudent_queryshow_confirm` → `action_QueryStudent_querydone`.
- Observed drill sequence (INFOSS-style, verify per target):
  `action_DrillStudent_querystart` → `qid*` answers plus
  `action_DrillStudent_next_queryshow` → `action_DrillStudent_querydone`.
- Before the final step, verify that the confirmation response contains the
  complete answer and satisfies any length or pass-score requirement. After
  submission, run `get PATH` and `tasks --json`; require the target state
  (`提出済み` / `合格済み`) and that it no longer appears as an open task when
  that was the goal.

## Handle failures

- On an argument error, inspect only the relevant `COMMAND --help=plain` and
  retry after correcting the invocation.
- On an authentication error, stop and request a fresh login.
- On a parser or unexpected-page error, report the affected command and page;
  do not improvise a write through another form.
- Never read or print the cookie jar while debugging.
