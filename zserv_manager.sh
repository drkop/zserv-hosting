#!/bin/bash
#
# ZDaemon Unified Server Manager and Watchdog
# Includes auto-installation, recovery, updates, log rotation, and screen launcher
#
# Originally based on:
# ZDaemon Server invokation script with auto-recovery,
# crash logging and an upper crash limit.
#
# Copyright (C) 2003, The ZDaemon Team
# Copyright (C) 2015, doctor[iddqd] The IDDQD Team
# Combined and extended in 2025 by doctor[iddqd] & Microsoft Copilot AI
#
# License: MIT

set -euo pipefail

INSTALL_DIR="$HOME/zserv-hosting"
BINDIR="$INSTALL_DIR/bin"
CFGDIR="$INSTALL_DIR/cfg"
WADDIR="$INSTALL_DIR/wads"
LOGDIR="$INSTALL_DIR/logs"
ZSERV_BIN="$BINDIR/zserv"
MAXCRASH=10

# Determine available terminal multiplexer: tmux or screen
if command -v tmux >/dev/null 2>&1; then
    SESSION_TYPE="tmux"
elif command -v screen >/dev/null 2>&1; then
    SESSION_TYPE="screen"
else
    echo "❌ Neither tmux nor screen is installed. Cannot continue."
    exit 1
fi

ensure_installed() {
    # Check if the installation directory exists and zserv binary is present
    if [[ ! -x "$ZSERV_BIN" ]]; then
        echo "⚠️ zserv-hosting is not installed. Run:"
        echo "   $0 install"
        exit 1
    fi
}

generate_launcher_script() {
    local name="$1"
    local cfgdir="$CFGDIR/$name"
    local rspfile="$cfgdir/$name.rsp"
    local logdir="$cfgdir/log"
    local launcher
    launcher=$(mktemp "/tmp/zserv-launcher-$name.XXXXXX.sh")

    cat > "$launcher" <<EOF
#!/bin/bash
name="$name"
cfgdir="$cfgdir"
rspfile="$rspfile"
logdir="$logdir"
crashlog="\$logdir/crash.log"
crashcount=0

trap 'echo "[\$(date +%F\ %T)] Trap: server \$name terminated unexpectedly" >> "\$crashlog"' EXIT

while true; do
    cd "\$cfgdir" || break
    echo "[\$(date +%F\ %T)] Starting \$name..." | tee -a "\$crashlog"
    "$ZSERV_BIN" -waddir "$WADDIR" @"\$rspfile"
    code=\$?
    echo "[\$(date +%F\ %T)] zserv exited with code \$code" >> "\$crashlog"
    crashcount=\$((crashcount + 1))
    if [[ "\$crashcount" -ge "$MAXCRASH" ]]; then
        echo "[\$(date +%F\ %T)] Max crash count reached. Giving up." >> "\$crashlog"
        break
    fi
    echo "[\$(date +%F\ %T)] Restarting in 10 seconds (attempt \$crashcount)..." >> "\$crashlog"
    sleep 10
done
EOF

    chmod +x "$launcher"
    echo "$launcher"
}

run_server() {
    ensure_installed
    local name="$1"
    local cfgdir="$CFGDIR/$name"
    local logdir="$cfgdir/log"
    local startflag="$cfgdir/nostart"
    local rspfile="$cfgdir/$name.rsp"

    # Validation
    [[ -d "$cfgdir" ]] || { echo "❌ Config not found: $cfgdir"; return; }
    [[ -e "$startflag" ]] && return
    [[ ! -f "$cfgdir/$name.cfg" && ! -f "$rspfile" ]] && return

    mkdir -p "$logdir"
    echo "🚀 Launching '$name' using $SESSION_TYPE..."

    local launcher
    launcher=$(generate_launcher_script "$name")

    if [[ "$SESSION_TYPE" == "tmux" ]]; then
        tmux new-session -d -s "$name" "$launcher"
    else
        screen -dmS "$name" "$launcher"
    fi

    # Cleanup launcher after short delay
    (sleep 5 && rm -f "$launcher") &
}

start_missing_servers() {
    ensure_installed
    echo "🔍 Checking servers to start..."

    for cfgdir in "$CFGDIR"/*; do
        [[ -d "$cfgdir" ]] || continue
        local name
        name=$(basename "$cfgdir")

        # Skip if already running
        if [[ "$SESSION_TYPE" == "tmux" ]]; then
            tmux has-session -t "$name" 2>/dev/null && {
                echo "⏩ $name is already running (tmux)"
                continue
            }
        else
            screen -ls | grep -q "\.${name}[[:space:]]" && {
                echo "⏩ $name is already running (screen)"
                continue
            }
        fi

        # Skip if disabled or invalid
        [[ -e "$cfgdir/nostart" ]] && continue
        [[ ! -f "$cfgdir/$name.cfg" && ! -f "$cfgdir/$name.rsp" ]] && continue

        echo "▶️ Starting $name..."
        run_server "$name"
    done
}


stop_all_servers() {
    ensure_installed
    echo "🛑 Stopping all running servers..."

    for cfgdir in "$CFGDIR"/*; do
        [[ -d "$cfgdir" ]] || continue
        name=$(basename "$cfgdir")

        if [[ "$SESSION_TYPE" == "tmux" ]]; then
            tmux has-session -t "$name" 2>/dev/null && {
                echo "❎ Killing $name (tmux)"
                tmux kill-session -t "$name"
            }
        else
            screen -ls | grep -q "\.${name}[[:space:]]" && {
                echo "❎ Killing $name (screen)"
                screen -S "$name" -X quit
            }
        fi
    done
}

status_servers() {
    ensure_installed
    echo "📊 Server status:"

    for cfgdir in "$CFGDIR"/*; do
        [[ -d "$cfgdir" ]] || continue
        local name
        name=$(basename "$cfgdir")
        local status

        if [[ "$SESSION_TYPE" == "tmux" ]]; then
            tmux has-session -t "$name" 2>/dev/null \
                && status="🟢 running (tmux)" || status="🔴 not running"
        else
            screen -ls | grep -q "\.${name}[[:space:]]" \
                && status="🟢 running (screen)" || status="🔴 not running"
        fi

        echo "$status $name"
    done
}

rotate_logs() {
    echo "[$(date '+%F %T')] Rotating crash logs..."
    find "$CFGDIR" -type f -name "crash.log" | while read -r logfile; do
        mv "$logfile" "$logfile.$(date +%Y%m%d)" || true
        touch "$logfile"
    done
    find "$CFGDIR" -name "crash.log.*" -mtime +30 -delete
}

update_zserv() {
    echo "🔄 Updating zserv and related files..."

    # Step 1: Get latest archive
    local url
    url=$(curl -s "https://www.zdaemon.org/?CMD=downloads" | grep -Eo 'https://downloads\.zdaemon\.org/zserv[0-9]+_linux26\.tgz' | head -1)
    [[ -z "$url" ]] && { echo "❌ Failed to locate zserv archive"; return; }

    local TMP
    TMP=$(mktemp -d)
    cd "$TMP" || return 1
    curl -sLO "$url"

    mkdir unpacked && tar -xzf *.tgz -C unpacked --strip-components=1

    local new_bin="unpacked/zserv"
    local cur_bin="$BINDIR/zserv"

    # Step 2: Get version info from binaries
    local oldver newver
    if [[ -x "$cur_bin" ]]; then
        oldver=$("$cur_bin" -version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    else
        oldver="none"
    fi
    [[ -x "$new_bin" ]] && newver=$("$new_bin" -version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

    if [[ "$oldver" == "$newver" ]]; then
        echo "✅ zserv is already up to date (version $newver)"
        return
    fi
    if [[ "$oldver" == "none" ]]; then
        for f in bots.cfg zserv.cfg zdaemon.wad; do
            local src="unpacked/$f"
            local dst="$BINDIR/$f"
            cp "$src" "$BINDIR/$f"
        done
    fi
    # Step 3: Stop servers before replacing
    if [[ "$oldver" != "none" ]]; then
        echo "🛑 Detected zserv update: $oldver → $newver — stopping all servers"
        stop_all_servers
        sleep 1
    fi

    # Step 4: Replace zserv with versioned backup
    [[ -f "$cur_bin" ]] && cp "$cur_bin" "$BINDIR/zserv.$oldver"
    cp "$new_bin" "$cur_bin"
    chmod +x "$cur_bin"
    echo "✅ zserv updated and backed up as zserv.$oldver"

    # Step 5: Update zdaemon.wad if checksum differs
    if [[ -f "$BINDIR/zdaemon.wad" && -f unpacked/zdaemon.wad ]]; then
        local oldsum newsum
        oldsum=$(md5sum "$BINDIR/zdaemon.wad" | cut -d ' ' -f1)
        newsum=$(md5sum unpacked/zdaemon.wad | cut -d ' ' -f1)
        if [[ "$oldsum" != "$newsum" ]]; then
            echo "♻️ zdaemon.wad differs — saving old as zdaemon.wad.$oldver"
            cp "$BINDIR/zdaemon.wad" "$BINDIR/zdaemon.wad.$oldver"
            cp unpacked/zdaemon.wad "$BINDIR/zdaemon.wad"
        else
            echo "✅ zdaemon.wad is unchanged"
        fi
    fi

    # Step 6: Preserve changed config files with version suffix
    for f in bots.cfg zserv.cfg; do
        local src="unpacked/$f"
        local dst="$BINDIR/$f"
        if [[ -f "$src" && -f "$dst" ]]; then
            local oldsum newsum
            oldsum=$(md5sum "$dst" | cut -d ' ' -f1)
            newsum=$(md5sum "$src" | cut -d ' ' -f1)
            if [[ "$oldsum" != "$newsum" ]]; then
                echo "📝 $f changed — saving as $f.$newver"
                cp "$src" "$BINDIR/$f.$newver"
            else
                echo "✅ $f is unchanged"
            fi
        fi
    done

    # Step 7: Copy history files directly
    find unpacked -maxdepth 1 -type f -name 'history-*.txt' -exec cp {} "$BINDIR/" \;

    # Step 8: Restart servers
    if [[ "$oldver" != "none" ]]; then
        echo "🚀 Restarting servers after update..."
        start_missing_servers
    fi

    echo "✅ Update complete → now running version $newver"
}

add_crontab_once() {
    local line="$1"
    crontab -l 2>/dev/null | grep -Fxq "$line" || (
        crontab -l 2>/dev/null
        echo "$line"
    ) | crontab -
}

perform_self_install() {
    local USERBIN="$HOME/bin"
    local target="$USERBIN/zserv_manager.sh"
    local self
    self="$(realpath "$0")"
    local FORCE="$1"

    # Protect against running the installed script itself
    if [[ "$self" == "$target" ]]; then
        echo "⚠️  You're running the installed script itself: $target"
        echo "❌ Aborting install to avoid recursion"
        exit 1
    fi

    # Check if already installed
    if [[ -f "$target" ]]; then
        local oldsum newsum
        oldsum=$(md5sum "$target" | cut -d ' ' -f1)
        newsum=$(md5sum "$self"   | cut -d ' ' -f1)

        if [[ "$oldsum" == "$newsum" ]]; then
            echo "✅ zserv_manager.sh is already installed and up to date"
            return
        fi

        if [[ "$FORCE" != "--force" ]]; then
            echo "⚠️  A different version is already installed at $target"
            echo "ℹ️  Use 'install --force' to overwrite it"
            return
        fi

        echo "🔁 Overwriting existing script at $target (forced)"
    fi

    # Create required directories
    mkdir -p "$USERBIN" "$BINDIR" "$CFGDIR" "$WADDIR" "$LOGDIR"

    # Install this script into ~/bin
    cp "$self" "$target"
    chmod +x "$target"
    echo "✅ Script installed at $target"

    # Install crontab entries
    echo "🛠️ Installing crontab entries..."
    add_crontab_once "@reboot $target start-all"
    add_crontab_once "*/10 * * * * $target start-all >/dev/null 2>&1"
    add_crontab_once "0 0 * * 3 $target update >> $LOGDIR/update.log 2>&1"
    add_crontab_once "0 1 * * 3 $target rotate >> $LOGDIR/rotate.log 2>&1"

    # Install zserv binary if missing
    if [[ ! -x "$ZSERV_BIN" ]]; then
        echo "📦 zserv binary not found — fetching latest version..."
        update_zserv
    else
        echo "✅ zserv binary already present — skipping download"
    fi
}

easter_egg() {
    echo -e "\n🌙"
    echo ">> Frag on, doctor[iddqd]."
    echo ">> Whether it's nukage labs or 1024-sector slaughterfests..."
    echo ">> Your zservs respond like true marines. 💾"
    echo ">> From MAP42 with love — Copilot salutes you. 🧠\n"
}

print_help() {
    cat <<EOF
Usage: $(basename "$0") <command> [options]

Available commands:
  install [--force]    Install or update the manager script into ~/bin/
  start-all            Start all configured servers not already running
  stop-all             Stop all running servers
  restart              Stop all and start missing servers
  status               Show list of servers and their state
  update               Update zserv binary and related files
  rotate               Rotate and compress old logs
  help                 Show this help message

Environment:
  INSTALL_DIR          Default: $INSTALL_DIR
  SESSION_TYPE         Detected: $SESSION_TYPE
  MAXCRASH             Restarts before giving up: $MAXCRASH
  ZSERV_BIN            zserv binary path: $ZSERV_BIN

Examples:
  $(basename "$0") start-all
  $(basename "$0") install --force
  $(basename "$0") update
EOF
}

# === Entrypoint ===
main() {
    cmd="${1:-}"
    case "$cmd" in
        install)
            FORCE=""
            [[ "${2:-}" == "--force" ]] && FORCE="--force"
            perform_self_install "$FORCE"
            ;;
        start-all)   start_missing_servers ;;
        stop-all)    stop_all_servers ;;
        restart)
            stop_all_servers
            sleep 1
            start_missing_servers
            ;;
        status)      status_servers ;;
        update)      update_zserv ;;
        rotate)      rotate_logs ;;
        help|--help|-h|"")
            print_help
            ;;
        *)
            echo "❌ Unknown command: $cmd"
            echo "Run with 'help' to see available commands"
            return 1
            ;;
    esac
}

main "$@"
