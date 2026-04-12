#!/usr/bin/env bash
# KWallet helper for pomodoro-todo CalDAV sync.
# Adapted from plasma-meets-helper.sh.
# Uses qdbus6 to access KWalletd6 via D-Bus.
set -euo pipefail

if command -v qdbus6 &>/dev/null; then
    _qdbus=qdbus6
elif command -v qdbus-qt6 &>/dev/null; then
    _qdbus=qdbus-qt6
else
    echo "qdbus6 not found" >&2
    exit 1
fi

wallet_service="org.kde.kwalletd6"
wallet_path="/modules/kwalletd6"
wallet_iface="org.kde.KWallet"
wallet_name="kdewallet"
wallet_folder="pomodoro-todo"
wallet_app="pomodoro-todo"

cmd="${1:-}"

wallet_handle() {
    $_qdbus "$wallet_service" "$wallet_path" "$wallet_iface.open" \
        "$wallet_name" 0 "$wallet_app"
}

wallet_ensure_folder() {
    local handle="$1"
    local has_folder
    has_folder="$($_qdbus "$wallet_service" "$wallet_path" \
        "$wallet_iface.hasFolder" "$handle" "$wallet_folder" "$wallet_app" | tr -d '\r')"
    if [[ "$has_folder" != "true" ]]; then
        $_qdbus "$wallet_service" "$wallet_path" \
            "$wallet_iface.createFolder" "$handle" "$wallet_folder" "$wallet_app" >/dev/null
    fi
}

wallet_read() {
    local entry="$1"
    local handle value
    handle="$(wallet_handle 2>/dev/null)" || { printf ''; return; }
    wallet_ensure_folder "$handle"
    value="$($_qdbus "$wallet_service" "$wallet_path" \
        "$wallet_iface.readPassword" "$handle" "$wallet_folder" "$entry" "$wallet_app" \
        2>/dev/null || true)"
    printf '%s' "$value"
}

wallet_write() {
    local entry="$1" value="$2"
    local handle
    handle="$(wallet_handle)"
    wallet_ensure_folder "$handle"
    $_qdbus "$wallet_service" "$wallet_path" \
        "$wallet_iface.writePassword" "$handle" "$wallet_folder" "$entry" "$value" \
        "$wallet_app" >/dev/null
}

wallet_clear() {
    local entry="$1"
    local handle
    handle="$(wallet_handle 2>/dev/null)" || return 0
    wallet_ensure_folder "$handle"
    $_qdbus "$wallet_service" "$wallet_path" \
        "$wallet_iface.removeEntry" "$handle" "$wallet_folder" "$entry" \
        "$wallet_app" >/dev/null 2>/dev/null || true
}

wallet_has() {
    local entry="$1"
    local handle has
    handle="$(wallet_handle 2>/dev/null)" || { printf 'false'; return; }
    wallet_ensure_folder "$handle"
    has="$($_qdbus "$wallet_service" "$wallet_path" \
        "$wallet_iface.hasEntry" "$handle" "$wallet_folder" "$entry" \
        "$wallet_app" 2>/dev/null || echo 'false')"
    printf '%s' "${has:-false}"
}

case "$cmd" in
    wallet-read)  wallet_read  "${2:-}" ;;
    wallet-write) wallet_write "${2:-}" "${3:-}" ;;
    wallet-clear) wallet_clear "${2:-}" ;;
    wallet-has)   wallet_has   "${2:-}" ;;
    *)
        echo "Usage: $0 wallet-read|wallet-write|wallet-clear|wallet-has <key> [value]" >&2
        exit 1
        ;;
esac
