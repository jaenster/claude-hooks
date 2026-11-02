#!/usr/bin/env bash
# PreToolUse guard: prevent reading sensitive files that contain credentials,
# keys, or tokens. Covers Read, Bash (cat/head/tail/less/more/grep on secrets),
# and Write/Edit (which require reading first).
#
# This keeps secrets out of the conversation context where they'd be sent to
# the API. The user can always read them themselves.
set -uo pipefail

input=$(cat)
tool=$(printf '%s' "$input" | jq -r '.tool_name // ""')

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# Patterns for secret file paths (basename matching).
# .env without .example/.sample/.template/.dist suffix
# Private keys, token files, credentials, auth configs
SECRET_BASENAME='(^|/)\.env(\.[a-z]+)?$|(^|/)(\.env\.local|\.env\.production|\.env\.staging)$|id_(rsa|ecdsa|ed25519|dsa)$|\.pem$|\.key$|\.p12$|\.pfx$|\.jks$|\.keystore$|credentials\.json$|service[_-]?account.*\.json$|token\.json$|\.netrc$|\.npmrc$|\.pypirc$|\.gem/credentials$|\.docker/config\.json$|\.aws/credentials$|\.kube/config$|gcloud/.*credentials.*$|\.ssh/config$'

# Exceptions: example/template/sample/dist files are fine.
SECRET_EXCEPTION='\.(example|sample|template|dist|test|spec|mock)(\.|$)|fixtures?/|__tests__/|testdata/'

is_secret() {
  local path=$1
  printf '%s' "$path" | grep -Eiq "$SECRET_BASENAME" || return 1
  printf '%s' "$path" | grep -Eiq "$SECRET_EXCEPTION" && return 1
  return 0
}

case "$tool" in
  Read)
    path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')
    if is_secret "$path"; then
      deny "Blocked by the no-secrets-read hook: '$path' looks like a credentials file. Reading it would put secrets into the conversation context (which is sent to the API). If you need to check its structure, ask the user to describe it. If you need a value from it, ask the user to provide it or reference it via an environment variable."
    fi
    ;;

  Bash)
    cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // ""')
    # Check for common read commands targeting secret files.
    while IFS= read -r path; do
      [ -z "$path" ] && continue
      if is_secret "$path"; then
        deny "Blocked by the no-secrets-read hook: this command reads '$path', which looks like a credentials file. Reading it would put secrets into the conversation context. If you need to check its structure, ask the user to describe it or use 'wc -l' / 'file' to inspect it without reading contents."
      fi
    done < <(printf '%s' "$cmd" | grep -oE '[^[:space:];&|"'"'"']+' | grep -Ei '\.env|\.pem|\.key|credentials|\.netrc|\.npmrc|\.pypirc|\.aws/|\.ssh/|\.kube/|token\.json|service.account')
    ;;

  Write|Edit)
    path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')
    if is_secret "$path"; then
      deny "Blocked by the no-secrets-read hook: '$path' looks like a credentials file. Do not write or edit credential files directly — the user manages their own secrets. If you need to create an example file, name it with a .example or .template suffix."
    fi
    ;;
esac

exit 0
