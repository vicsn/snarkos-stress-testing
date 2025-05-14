# Slack Notification CLI Tool

A lightweight Bash CLI tool for sending Slack notifications directly from scripts or the terminal.
Supports threading, rich message formatting, colored blocks, and user mentions including `@here`, `@channel`, and `@everyone`.

Its idea is to notify about the start and finish of stress test runs. It is in bash, so it can be integrated in other scripts we use,
like the manual test runs, also it can be invoked by talisker with the right options for automated test runs.

## Features

-  Simple message sending.
-  Threaded replies.
-  Message formatting: plain, bold, code blocks.
-  Colored message blocks (`good`, `warning`, `danger`, or custom HEX colors).
-  User mentions and special mentions (`@here`, `@channel`, `@everyone`).
-  Automatically returns `thread_ts` for easy threading (read bellow).

## Usage

You need to export your `SLACK_TOKEN` and `CHANNEL_ID` in the terminal/env of use:

```bash
export SLACK_TOKEN="xoxb-XXXXXXXXXXXXX-XXXXXXXXXXXXX-XXXXXXXXXXXXXXXXXXXXXXXX"
export CHANNEL_ID="CXXXXXXXXXX"
```

```bash
./notify.sh -m "Message text" [options]
```

##  Options

| Option  | Description                                      | Example                       |
|---------|--------------------------------------------------|-------------------------------|
| `-m`    | **(Required)** Message text                      | `-m "Hello, world!"`          |
| `-c`    | Channel ID (default set in script)               | `-c C1234567890`              |
| `-t`    | Thread timestamp for threaded reply              | `-t 1715580000.123456`        |
| `-f`    | Format: `plain`, `bold`, `code`                  | `-f bold`                     |
| `-o`    | Block color: `good`, `warning`, `danger`, or HEX | `-o danger` or `-o "#36a64f"` |
| `-n`    | Mentions: User IDs or `@here,@channel,@everyone` | `-n "@here,U12345678"`        |
| `-k`    | Slack Bot Token (override default)               | `-k xoxb-xxxxxxxx`            |
| `-h`    | Show help and usage                              | `-h`                          |


##  Examples

### 1. Send a Simple Message

```bash
./notify.sh -m "Deployment started"
```

### 2. Send a Bold Success Message with a Green Block and Mention @here

```bash
./notify.sh -m 'Deployment finished!' -f bold -o good -n "@here"
```

### 3. Send a Message and Capture the \`thread_ts\` for Replies

```bash
thread_ts=$(./notify.sh -m "🛠️ Starting batch processing..." -f bold -o warning -n "@channel")
./notify.sh -m "📦 Batch 1 complete" -t "$thread_ts"
./notify.sh -m "📦 Batch 2 complete" -t "$thread_ts"
```

### 4. Send an Error Notification with a Red Block and Code Formatting

```bash
./notify.sh -m '🔥 Critical error!\nCheck logs:\n/var/log/app/error.log' -f code -o danger -n "@everyone"
```

### 5. Reply in an Existing Thread

```bash
./notify.sh -m '✅ All services restarted successfully.' -t 1715580000.123456
```

## Notes

- The Slack Bot Token (`SLACK_TOKEN`) and default channel (`CHANNEL_ID`) can be set directly in the terminal or passed using `-k` and `-c`.
- To mention users, provide their Slack User IDs (Go to the profile of the user in slack, the row that starts with the "message" button ends with three vertical dots, click on them, click "Copy member ID"). Special mentions like `@here`, `@channel`, and `@everyone` are automatically handled.
- If no `-t` is provided, the script returns the `thread_ts` of the posted message for easy chaining. For example when Talisker is running its tests, it opens a new thread on a new test run, keeps the `thread_ts` and adds updates to that thread.
