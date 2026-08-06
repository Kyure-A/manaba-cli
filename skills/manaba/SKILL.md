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

### Interpret `tasks` carefully

`tasks --json` is manaba's outstanding-task page, not a graded to-do list.

- Items may remain listed even when the course already has a completed
  alternative path (example: INFOSS English drills stay open after the Japanese
  path is complete; official guidance says both tracks are not required).
- Before treating an open task as mandatory work, open the course news /
  content / quiz description and check optionality, language track, and
  completion requirements.
- Optional noise may still need action if the user explicitly wants it gone
  from the outstanding list; say that clearly when choosing to complete it.

### Course materials and videos

Prefer materials that manaba can actually deliver:

1. Attachments on content pages (PDF/PPT via `links` + `download`)
2. Page text from `get`
3. Video **URLs** listed on the page (SharePoint / Stream / OneDrive links)

Do **not** claim to watch or transcribe lecture video through this CLI.

- manaba-cli only requests the manaba origin. SharePoint/Stream hosts are
  rejected as off-origin.
- Listing a video URL with `links` or `get` is fine; fetching the media,
  captions, or transcript is out of scope here.
- If a quiz depends on video-only content and no downloadable notes exist,
  report that blocker instead of inventing answers from the URL alone.
- Captioned videos often have a parallel PDF on the same content page; download
  that first when present.

## Download files

Use `links --json PATH` to discover the exact attachment path when needed, then
use `download PATH --output FILE`. Confirm the intended output path when it is
ambiguous, avoid overwriting an existing file without authorization, and return
a clickable absolute path to the downloaded file.

Attachment paths are often long and percent-encoded (for example
`page_…/….pdf`). Prefer the href from `links --json` or raw HTML over guessing
from the visible file name. Downloading a content page path itself can return
HTML rather than the PDF.

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

### Submit reports with multiple individual files

Do not archive or combine files merely because `report submit` accepts one
`FILE`. That command uploads one file and immediately confirms submission. For
an assignment requiring several separate files, use the report page's generic
form instead:

1. Resolve the report path as `course_COURSE_ID_report_REPORT_ID` and inspect it
   with `forms --json PATH`.
2. For each file, press the upload button separately while leaving the report
   uncommitted:

   ```text
   submit --yes --button=action_ReportStudent_submitdone \
     --file=RptSubmitFile=/absolute/path/to/file.docx PATH
   ```

3. After every upload, require the response to show the cumulative file count
   and exact names. The file control's `multiple: false` means one file per
   upload request, not one file per report.
4. Only after every required file is present, confirm once:

   ```text
   submit --yes --button=action_ReportStudent_commitdone PATH
   ```

5. Verify `提出済み`, the expected total count, and every submitted filename
   with `get PATH`; check `submissions` when useful.

If a partial report was already confirmed and the page allows resubmission,
`report cancel --yes COURSE_ID REPORT_ID` returns it to the editable state and
normally preserves uploaded files. Inspect the returned page and forms before
adding the rest, then confirm once again. Never assume preservation or retry a
mutation blindly.

For an unsupported action, inspect the page with `forms --json PATH` first.
Use `submit` or `flow` only when no dedicated command exists and the requested
mutation is explicit. Let the CLI carry hidden fields forward; never attempt to
extract or reveal hidden token values.

### Choose forms with `--button`, not form index 1

Many course pages put a Google Calendar widget as form 1. That form's action is
off-origin and will fail if submitted.

- Prefer `submit --yes --button BUTTON_NAME PATH`.
- With `--button`, the CLI selects the form that contains that button.
- Do not assume `--form 1` is the assignment form.
- Confirm button names with `forms --json PATH` on the start page, or with
  `--forms-json` on a post-start response (below).

### Inspect post-start forms with `--forms-json`

`get PATH` and `forms --json PATH` only see the **current GET** page. After a
quiz/drill start POST, the answer form often exists only in that response.
Re-GETting the original path can show the start page again. That is an
inspection limitation, not proof that the attempt vanished.

To inspect without guessing field names:

```text
submit --yes --forms-json --button START_BUTTON PATH
flow --yes --forms-json PATH PLAN.json
```

- `--forms-json` prints response forms as JSON instead of main text.
- Unchecked radios expose wire values under each control's `options` array
  (for example `"value": "1"`); the control's top-level `value` stays null
  until selected.
- For 〇/× items, the first radio is commonly 〇=`1` and the second ×=`2`, but
  always verify against the rendered option order in page text.

### Multi-step quizzes and drills

Prefer one `flow` from the original quiz/drill path so cookies, hidden
controls, intermediate bodies, and changed form actions carry forward. Do not
split an attempt into unrelated `submit` calls, invent `qid*` names, or inspect
the session cookie.

Exception — when the answer has to be written between entering the quiz and
submitting it. `flow` restarts its plan from a fresh fetch, so its first step
presses `スタート` again; manaba reissues that screen's hidden tokens on every
entry and restarts 経過時間 from it, so an enter-and-submit run records only its
own seconds. Chain `submit --save-state FILE` / `submit --from-state FILE`
instead: enter once, do the reading and drafting, then submit against the saved
response. The quiz is never re-entered and 経過時間 covers the actual work.
State files hold the page's hidden tokens, are written 0600, and are single-use
because submitting invalidates those tokens. Never pad the interval with idle
waiting to make 経過時間 look larger — that fabricates engagement telemetry;
only real work belongs in that window.

Flow plan steps may include:

- `"button": "NAME"` — submit control to press
- `"fields": { "qid1": "2", ... }` — explicit answers
- `"auto": "first-choice"` — fill first radio/select option per field, then
  apply explicit `fields` on top. Use only when exact answers are not required
  (optional noise clearance, exploratory runs).
- `"form": N` — only when button disambiguation is insufficient

#### Observed sequences (verify per target)

**Single-page quiz (descriptive answer):**

1. `action_QueryStudent_querystart`
2. fields such as `qid1` + `action_QueryStudent_queryshow_confirm`
3. `action_QueryStudent_querydone`

**INFOSS-style drill (all questions on one page):**

1. `action_DrillStudent_querystart`
2. `qid*` answers + `action_DrillStudent_next_queryshow`
3. `action_DrillStudent_querydone`

**Multi-page quiz (page buttons `p1`…`pN`):**

1. `action_QueryStudent_querystart`
2. Jump or advance with
   `action_QueryStudent_queryshow_pK` / `_next` / `_prev` while posting that
   page's `qid*` fields
3. `action_QueryStudent_queryshow_confirm` with the last page's fields
4. `action_QueryStudent_querydone`

Collect every page's questions before final submit when correctness matters:
partial flows that answer with `"auto": "first-choice"` and jump pages are fine
for discovery; do not treat those exploratory answers as the real submission
unless the user accepted low-stakes completion.

Checkbox-only checklists (for example INFOSS theft-prevention check) need
explicit `qidN=1` (or the value shown in `options`) for each required box;
`"auto": "first-choice"` does not reliably check every box.

### Post-submission verification

After any quiz, drill, or report mutation intended to complete work:

1. `get PATH` (or the report/quiz page) and require the expected state text
   such as `提出済み`, `合格済み`, or a numeric score when published.
2. `tasks --json` and confirm the item is gone when clearing outstanding work
   was the goal (optional items may remain until completed or left alone).
3. For drills with a pass threshold, require a passing best score, not merely
   that an attempt exists.
4. For reports, confirm both the report page state and, when useful,
   `submissions`.
5. Record durable outcomes in Kyre's `self` life records when the surrounding
   agent workflow expects it; do not print secrets or session cookies.

If verification fails, report the exact page state. Do not re-submit blindly.

## Handle failures

- On an argument error, inspect only the relevant `COMMAND --help=plain` and
  retry after correcting the invocation.
- On an authentication error, stop and request a fresh login via the managed
  university login path above.
- On a parser or unexpected-page error, report the affected command and page;
  do not improvise a write through another form.
- On off-origin / SharePoint video errors, explain that media hosts are outside
  manaba-cli and fall back to downloadable notes when available.
- Never read or print the cookie jar while debugging.
