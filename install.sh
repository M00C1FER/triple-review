#!/usr/bin/env bash
# triple-review — interactive install wizard with CLI registration.
set -euo pipefail

if [ -t 1 ]; then C_BOLD="$(tput bold)"; C_RESET="$(tput sgr0)"; C_GREEN="$(tput setaf 2)"; C_YELLOW="$(tput setaf 3)"; C_RED="$(tput setaf 1)"; else C_BOLD=""; C_RESET=""; C_GREEN=""; C_YELLOW=""; C_RED=""; fi
say()  { printf "%s%s%s\n" "$C_BOLD" "$1" "$C_RESET"; }
info() { printf "  %s\n" "$1"; }
ok()   { printf "  %s✓%s %s\n" "$C_GREEN" "$C_RESET" "$1"; }
warn() { printf "  %s!%s %s\n" "$C_YELLOW" "$C_RESET" "$1"; }
fail() { printf "  %s✗%s %s\n" "$C_RED" "$C_RESET" "$1" >&2; exit 1; }
prompt_yn() { local q="$1" def="${2:-y}" ans; if [ "$def" = "y" ]; then read -r -p "  $q [Y/n]: " ans; ans="${ans:-y}"; else read -r -p "  $q [y/N]: " ans; ans="${ans:-n}"; fi; [[ "$ans" =~ ^[Yy] ]]; }
prompt_default() { read -r -p "  $1 [$2]: " ans; echo "${ans:-$2}"; }

detect_os() { OS_ID=unknown; OS_LIKE=""; OS_VERSION=""; OS_WSL=0; OS_TERMUX=0; [ -f /etc/os-release ] && { . /etc/os-release; OS_ID="${ID:-}"; OS_LIKE="${ID_LIKE:-}"; OS_VERSION="${VERSION_ID:-}"; }; [ "$(uname)" = "Darwin" ] && OS_ID=macos; grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null && OS_WSL=1 || true; [ -n "${TERMUX_VERSION:-}" ] && { OS_TERMUX=1; OS_ID=termux; }; }
pkg_install() {
    case "$OS_ID" in
        debian|ubuntu) sudo apt-get update -qq && sudo apt-get install -y "$@";;
        fedora|rhel|centos) sudo dnf install -y "$@";;
        arch|manjaro) sudo pacman -S --noconfirm "$@";;
        alpine) sudo apk add --no-cache "$@";;
        opensuse*|sles) sudo zypper install -y "$@";;
        macos) brew install "$@";;
        termux) pkg install -y "$@";;
        *) warn "unknown OS — install manually: $*"; return 1;;
    esac
}

ensure_python() {
    command -v python3 >/dev/null && {
        local pyv; pyv="$(python3 -c 'import sys; print("%d.%d"%sys.version_info[:2])')"
        case "$pyv" in 3.1[0-9]|3.[2-9][0-9]) ok "Python $pyv"; return 0;; esac
    }
    if prompt_yn "Install Python 3.10+ via system package manager?"; then
        case "$OS_ID" in
            debian|ubuntu) pkg_install python3 python3-venv python3-pip;;
            fedora|rhel|centos) pkg_install python3 python3-pip;;
            arch|manjaro) pkg_install python python-pip;;
            alpine) pkg_install python3 py3-pip;;
            macos) pkg_install python@3.12;;
            termux) pkg_install python;;
            *) fail "install Python 3.10+ manually then re-run";;
        esac
    else fail "Python 3.10+ required"; fi
}

# ── CLI-registry wizard ──────────────────────────────────────────────────────
# triple-review is modular: it dispatches the same review prompt across N
# named CLIs in parallel.  This wizard generates a starter triple-review.yaml.
# Examples shown below are common cases — but ANY command-line LLM works.

build_yaml() {
    local out="$1"
    info "We'll generate a starter $out registering one or more LLM CLIs."
    info "Examples shown are common cases — any LLM CLI works (Claude, Gemini,"
    info "Copilot, Ollama, Mistral, your own SDK shim, etc.)."
    say ""
    : > "$out"
    echo "# triple-review CLI registry — register any LLM CLI here." >> "$out"
    echo "clis:" >> "$out"

    local added=0
    local entries=(
        "claude  | claude  -p --output-format=text"
        "gemini  | gemini  -p"
        "copilot | copilot -p"
        "ollama  | ollama run qwen2.5-coder"
    )
    for entry in "${entries[@]}"; do
        local name; name="$(echo "${entry%%|*}" | xargs)"
        local cmd;  cmd="$(echo "${entry##*|}"  | xargs)"
        if prompt_yn "Register $name (command: '$cmd')?" n; then
            {
              echo "  - name: $name"
              printf "    cmd: ["
              local first=1
              for tok in $cmd; do [ $first -eq 0 ] && printf ", "; printf "\"%s\"" "$tok"; first=0; done
              printf "]\n"
              echo "    timeout_s: 300"
            } >> "$out"
            added=$((added+1))
        fi
    done
    if prompt_yn "Add a custom CLI?" n; then
        local name cmd
        name="$(prompt_default "Name (e.g. my-llm)" "my-llm")"
        cmd="$(prompt_default "Full command (space-separated)" "my-llm -p")"
        {
          echo "  - name: $name"
          printf "    cmd: ["
          local first=1
          for tok in $cmd; do [ $first -eq 0 ] && printf ", "; printf "\"%s\"" "$tok"; first=0; done
          printf "]\n"
          echo "    timeout_s: 300"
        } >> "$out"
        added=$((added+1))
    fi
    if [ "$added" -eq 0 ]; then
        warn "No CLIs registered — falling back to bundled 3-CLI preset at runtime"
    else
        ok "Wrote $added CLI(s) to $out"
    fi
}

main() {
    say "triple-review — install wizard"
    detect_os
    info "OS: ${OS_ID}${OS_VERSION:+ $OS_VERSION}$([ "$OS_WSL" = 1 ] && echo ' (WSL2)')$([ "$OS_TERMUX" = 1 ] && echo ' (Termux)')"

    say ""; say "Step 1/4: Python 3.10+"; ensure_python

    say ""; say "Step 2/4: Install location"
    local INSTALL_HOME; INSTALL_HOME="$(prompt_default "Install root" "$HOME/.local/share/triple-review")"
    mkdir -p "$INSTALL_HOME"
    if [ -d "$INSTALL_HOME/.git" ]; then ( cd "$INSTALL_HOME" && git pull -q ); else git clone -q https://github.com/M00C1FER/triple-review.git "$INSTALL_HOME"; fi

    cd "$INSTALL_HOME"
    # Termux: python3 -m venv may need --without-pip; pip is always available via pkg
    if [ "$OS_TERMUX" = 1 ]; then
        python -m venv .venv 2>/dev/null || python3 -m venv --without-pip .venv
        .venv/bin/python -m ensurepip --upgrade 2>/dev/null || true
    else
        python3 -m venv .venv
    fi
    .venv/bin/pip install --quiet --upgrade pip
    .venv/bin/pip install --quiet -e .[dev]
    # On Termux, $HOME/.local/bin is on PATH after `pkg install python`
    local BIN="${HOME}/.local/bin"; mkdir -p "$BIN"
    cat > "$BIN/triple-review" <<EOF
#!/usr/bin/env bash
exec "$INSTALL_HOME/.venv/bin/triple-review" "\$@"
EOF
    chmod +x "$BIN/triple-review"
    ok "triple-review installed"

    say ""; say "Step 3/4: Configure CLI registry"
    local CFG_DIR CFG_FILE
    CFG_DIR="$(prompt_default "Config directory" "$HOME/.config/triple-review")"
    mkdir -p "$CFG_DIR"
    CFG_FILE="$CFG_DIR/triple-review.yaml"
    if [ -f "$CFG_FILE" ] && ! prompt_yn "$CFG_FILE exists. Overwrite?" n; then
        info "Keeping existing config"
    else
        build_yaml "$CFG_FILE"
    fi

    say ""; say "Step 4/4: Verify"
    "$BIN/triple-review" --config "$CFG_FILE" --list-clis dummy.py 2>/dev/null | sed 's/^/   /' || true
    say ""
    ok "Done. Try: triple-review --config $CFG_FILE --falsify <file.py>"
}
main "$@"
