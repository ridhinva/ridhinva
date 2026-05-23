#!/usr/bin/env bash
# pushall.sh — push all git repos on the system to their GitHub origin
# Finds repos with https://github.com/ remotes and pushes the current branch.
# Reads GITHUB_TOKEN from env, ~/.github_token (~/.ghp), or gokey.
#
# NEVER hardcode a real token here — GitHub will block the push.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Resolve token from env, then ~/.github_token, then ~/.ghp
TOKEN="${GITHUB_TOKEN:-}"
[ -z "$TOKEN" ] && [ -f "$HOME/.github_token" ] && TOKEN="$(cat "$HOME/.github_token")"
[ -z "$TOKEN" ] && [ -f "$HOME/.ghp" ] && TOKEN="$(cat "$HOME/.ghp")"
[ -z "$TOKEN" ] && which gokey >/dev/null 2>&1 && TOKEN="$(gokey show ridhinva 2>/dev/null || true)"

if [ -z "$TOKEN" ]; then
    echo "[ERROR] No GitHub token set. Export GITHUB_TOKEN or write it to ~/.github_token"
    exit 1
fi

set +e

SLOW=2

ok()    { printf '  [OK]   %-50s\n' "$1"; }
fail()  { printf '  [FAIL] %s\n'   "$1"; }
skip()  { printf '  [SKIP] %s\n'   "$1"; }

repo_count=0
push_count=0
fail_count=0
skip_count=0

while IFS= read -r gitdir; do
    path="$(dirname "$gitdir")"
    name="$(basename "$path")"

    # Skip self / hermes infra
    [ "$name" = "pushall.sh" ] && continue
    [ "$name" = "hermes-agent" ] && continue
    [ "$name" = "hermes-vuln-tools" ] && continue

    # Get origin URL
    remote="$(git -C "$path" remote get-url origin 2>/dev/null)" || {
        skip "$name (no remote)"
        ((skip_count++))
        continue
    }

    # Only ridhinva GitHub repos
    case "$remote" in
        *github.com/ridhinva/*) ;;
        *) skip "$name (owner mismatch)"
           ((skip_count++))
           continue ;;
    esac

    user_repo="$(echo "$remote" | grep -oP 'github\.com[:/]\K(ridhinva/[^.]*)' | grep -oP 'ridhinva/\S+')"
    [ -z "$user_repo" ] && {
        skip "$name (cannot parse user_repo)"
        ((skip_count++))
        continue
    }

    token_url="https://${TOKEN}@github.com/${user_repo}.git"
    git -C "$path" remote set-url origin "$token_url" 2>/dev/null

    branch="$(git -C "$path" branch --show-current 2>/dev/null || echo main)"
    [ -z "$branch" ] && branch="main"

    output="$(git -C "$path" push origin "$branch" 2>&1)"
    rc=$?

    if [ $rc -eq 0 ]; then
        ok "$name@$branch"
        ((push_count++))
    elif echo "$output" | grep -qi "everything up-to-date\|already up to date"; then
        ok "$name@$branch (synced)"
        ((push_count++))
    else
        fail "$name@$branch — ${output%%$'\n'*}"
        ((fail_count++))
    fi

    git -C "$path" remote set-url origin "$remote" 2>/dev/null

    ((repo_count++))
    sleep "$SLOW"
done < <(find /data/data/com.termux/files/home /root /tmp -maxdepth 6 -type d -name ".git" 2>/dev/null |
    grep -v '/\.git$' |
    grep -vE '(\.oh-my|FlashUSDTSender|hermes-agent|hermes-vuln-tools)' |
    sort)

echo ""
echo "=============================="
printf 'Done: %d repos | pushed: %d | failed: %d | skipped: %d\n' \
       "$repo_count" "$push_count" "$fail_count" "$skip_count"
echo "=============================="
