# manaba-cli

[![CI](https://github.com/Kyure-A/manaba-cli/actions/workflows/ci.yml/badge.svg)](https://github.com/Kyure-A/manaba-cli/actions/workflows/ci.yml)
[![Live manaba smoke test](https://github.com/Kyure-A/manaba-cli/actions/workflows/live-smoke.yml/badge.svg)](https://github.com/Kyure-A/manaba-cli/actions/workflows/live-smoke.yml)

筑波大学の [manaba](https://manaba.tsukuba.ac.jp/) をターミナルから操作する
OCaml 製 CLI です。2026 年 7 月現在の manaba 2.979 を対象にしています。

公式 API ではなく、ブラウザと同じ HTTPS リクエストと HTML フォームを利用します。
パスワードは保存せず、ログイン後の Cookie のみを `0600` で保存します。

## 開発とビルド

```console
$ nix develop
$ dune build @all
$ dune runtest
$ dune fmt
```

開発シェルに入らずパッケージをビルド・実行することもできます。

```console
$ nix build
$ nix run . -- --help
```

GitHub Actions では Nix と opam の Linux/macOS ビルド、テスト、フォーマット、
パッケージメタデータを検証します。manaba の SAML 認証入口も毎日確認します。

## ログイン

```console
$ manaba auth login -u 13桁の統一認証ID
パスワード:
$ manaba auth status
logged in
```

パスワードは画面に表示されません。セッションは既定で
`$XDG_CONFIG_HOME/manaba-cli/session.json`、未設定なら
`~/.config/manaba-cli/session.json` に保存されます。
保存先は `MANABA_SESSION` または認証が必要な全コマンド共通の `--session FILE` で
変更できます。認証コマンド、`--session`、`-u/--username`、`--password-stdin`、
`-y/--yes` は姉妹ツールの `twins` と同じ構成です。
貼り付けた場合も文字や `*` は表示されないため、そのまま Enter を押してください。
macOS では、パスワードだけをコピーして次のようにクリップボードから直接読めます。

```console
$ manaba auth login --password-clipboard
```

## 主なコマンド

```console
$ manaba courses                    # 履修コース
$ manaba tasks                      # 未提出課題
$ manaba course COURSE_ID           # コース内の機能・更新項目
$ manaba news COURSE_ID
$ manaba quizzes COURSE_ID
$ manaba surveys COURSE_ID
$ manaba reports COURSE_ID
$ manaba projects COURSE_ID
$ manaba topics COURSE_ID
$ manaba contents COURSE_ID
$ manaba grades COURSE_ID
$ manaba submissions                # 提出記録
$ manaba portfolio                  # ポートフォリオ
$ manaba reminders                  # リマインダ
$ manaba memos                      # メモ
$ manaba settings                   # 個人設定
$ manaba registration search --name '情報検索'
$ manaba flow PATH PLAN.json        # 複数画面のフォーム操作
```

一覧コマンドは `--json` に対応しています。

## GUI 機能との対応

| manaba の画面 | CLI |
| --- | --- |
| ログイン、状態確認、ローカルログアウト | `auth login/status/logout` |
| コース、未提出課題、コースニュース | `courses`、`tasks`、`course`、`news` |
| 小テスト、アンケート、レポート、プロジェクト | `quizzes`、`surveys`、`reports`、`projects` |
| 掲示板、コンテンツ、成績、提出記録 | `topics`、`contents`、`grades`、`submissions` |
| ポートフォリオ、リマインダ、メモ、設定 | `portfolio`、`reminders`、`memos`、`settings` |
| 添付ファイル | `links`、`download` |
| レポート提出、提出取消 | `report submit/cancel` |
| 掲示板投稿、個人メモ、プロフィール | `thread create`、`memo set`、`profile set` |
| お気に入り、表示件数、自己登録 | `favorite`、`display-count`、`registration` |
| その他のリンク・フォーム | `get`、`links`、`forms`、`submit`、`flow` |

### 閲覧・ダウンロード

各一覧に表示された相対 URL はそのまま次のコマンドへ渡せます。

```console
$ manaba get course_123_report_456
$ manaba links course_123_page
$ manaba download \
    'course_123_report_456_af_789/material.pdf?action=full&view=full' \
    -o material.pdf
```

### レポート提出

```console
$ manaba report submit COURSE_ID REPORT_ID answer.pdf
$ manaba report cancel COURSE_ID REPORT_ID
```

送信前に確認します。自動処理では `--yes` を付けられます。フォームの隠し値と
送信ボタン名は毎回 manaba から取得するため、セッショントークンの手入力は不要です。

### その他のフォーム

専用コマンドがない学生・教員機能も、フォームを調べて 1 ステップずつ送信できます。

```console
$ manaba forms --json course_123_topics?action=newthread
$ manaba submit course_123_topics?action=newthread --form 1 \
    --field 'Title=件名' --field 'Body=本文'
```

`forms` は入力欄の `name`、現在値、選択肢を表示し、隠しトークンの値は表示しません。
`submit` は画面から取得した隠し値を自動的に引き継ぎます。ファイル欄は
`--file NAME=PATH`、複数の submit ボタンがある場合は `--button NAME` で指定します。
同じ `NAME` の `--field` は複数指定できます。

確認画面などを挟む処理は、レスポンスを引き継ぐ `flow` で実行できます。

```json
[
  {
    "button": "action_example_confirm",
    "fields": {
      "Answer": "1",
      "Tags": ["a", "b"]
    }
  },
  {
    "button": "action_example_commit"
  }
]
```

```console
$ manaba flow course_123_query_456 plan.json
```

各ステップでは `form`（1 始まり）、`button`、`fields`、`files` を指定できます。
`button` だけを指定した場合は、そのボタンを持つフォームを自動選択します。

### 投稿・設定・自己登録

```console
$ manaba thread create COURSE_ID '件名' '本文'
$ manaba memo set --class 0 '自分だけが読めるメモ'
$ manaba profile set 'プロフィール本文' --image avatar.png
$ manaba display-count 50
$ manaba registration search --code GE --name '演習'
$ manaba registration key REGISTRATION_KEY
```

書き込みや設定変更は実行直前に確認します。自動処理では `--yes` を指定できます。

## 安全性と制約

- 通信先は設定した manaba ホストに限定します。
- 投稿・提出などは明示的なコマンドと確認なしには実行しません。
- `auth logout` は保存 Cookie を削除します。統一認証全体のログアウトはブラウザを閉じて行います。
- manaba の HTML 変更や組織固有オプションによって、解析できない画面があり得ます。
- JavaScript のみで生成される操作は、対応する HTML フォームがなければ実行できません。

## ライセンス

GPL-3.0-only
