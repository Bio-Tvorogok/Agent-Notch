#!/bin/sh
# Invoked with the freshly compiled helper; all reads and writes stay in a temporary home.
set -eu
helper="$1"
fixture=$(mktemp -d /tmp/notch-doctor.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
output=$(AGENT_NOTCH_LANG=en "$helper" doctor --home "$fixture")
printf '%s\n' "$output" | /usr/bin/grep -q 'claude: config written: no; helper alive: no; first hook received: no'
printf '%s\n' "$output" | /usr/bin/grep -q 'codex: config written: no; helper alive: no; first hook received: no'
mkdir -p "$fixture/.codex" "$fixture/.claude"
printf 'broken' > "$fixture/.codex/hooks.json"
printf '[]' > "$fixture/.claude/settings.json"
output=$(AGENT_NOTCH_LANG=en "$helper" doctor --home "$fixture")
printf '%s\n' "$output" | /usr/bin/grep -q 'config written: no'
[ "$("$helper" --test-request codex --home "$fixture")" = FAIL ]
[ -z "$(printf 'broken' | "$helper" codex)" ]
printf '%s\n' 'OK connection CLI: missing and malformed configs, failed diagnostic, hooks exit zero'
