# 🕹️ zserv-hosting

A robust, cron-friendly ZDaemon server manager that supports multiple configurations, automatic restarts, log rotation, and clean integration with `tmux` or `screen`.

---
### IMPORTANT!
https://www.zdaemon.org/?CMD=downloads

```
IMPORTANT for 64-bit Linux users: to run the Linux server on a 64-bit Linux distribution, 
the 32-bit compatibility libraries need to be present. 
Here are the commands to install those libraries for some common 64-bit releases:

Fedora/CentOS:
      yum install glibc.i686 libstdc++.i686
Debian (up to 6):
      apt-get install ia32-libs
Debian (7 and later):
      dpkg --add-architecture i386
      apt-get update
      apt-get install libc6-i386 libstdc++6:i386
Ubuntu (up to 13.04):
      sudo apt-get install ia32-libs
Ubuntu (13.10 and later):
      sudo dpkg --add-architecture i386
      sudo apt-get update
      sudo apt-get install libc6-i386 libstdc++6:i386
The kernel must also be built with IA32_EMULATION enabled (this will be the case by default).`
```
___

## 📦 Installation

Install from a remote script:

```bash
curl -fsSL https://raw.githubusercontent.com/drkop/zserv-hosting/main/zserv_manager.sh -o zserv_manager.sh
chmod +x zserv_manager.sh && ./zserv_manager.sh install && rm -f zserv_manager.sh
~/bin/zserv_manager.sh help
```

Or clone manually:

```bash
git clone https://github.com/your-user/zserv-hosting.git
cd zserv-hosting
./zserv_manager.sh install
```

Use `--force` to reinstall or update if needed:

```bash
./zserv_manager.sh install --force
```

---

## 🚀 Usage

```bash
zserv_manager.sh <command> [options]
```

| Command           | Description                                               |
|-------------------|-----------------------------------------------------------|
| `install`         | Install the manager into `~/bin/` and setup cron jobs     |
| `install --force` | Force overwrite if script already exists                  |
| `start-all`       | Launch all configured servers that aren't already running |
| `stop-all`        | Stop all active servers                                   |
| `restart`         | Stop and start all servers                                |
| `status`          | Show current session state for all configured servers     |
| `update`          | Download latest `zserv` binary into local bin dir         |
| `rotate`          | Compress and archive old log files                        |
| `help`            | Display this help message                                 |

---

## 🧱 Directory Layout

By default, the install script sets up this structure:

```
~/zserv-hosting/
├── bin/           # zserv binary and utilities
├── cfg/           # Server configurations (1 directory per server)
│   └── ffa_ctf/
│       ├── ffa_ctf.cfg
│       ├── ffa_ctf.rsp
│       └── nostart    (optional, disables auto-start)
├── wads/          # WADs and game resources
├── log/           # Global logs (update, rotate)
└── zserv_manager.sh # Actual binary holded in ~/bin/ after install
```

---

## ⚙️ Features

- ✅ Runs via either `tmux` or `screen` (autodetected)
- 🧠 Automatic self-installation and updates
- 🔁 Auto-restart on crash, up to `MAXCRASH` attempts
- 📅 Cron integration:
  - `@reboot` → `start-all`
  - Weekly `update` + `rotate`
  - Periodic watchdog every 10 mins
- 📄 Server configs are modular and isolated
- 🧼 Temporary launchers clean up after themselves

---

## 🧪 Config Example

To define a new server:

```bash
mkdir -p ~/zserv-hosting/cfg/duel_server/
cp template.cfg cfg/duel_server/duel_server.cfg
cp template.rsp cfg/duel_server/duel_server.rsp
```
And edit `duel_server.cfg` `duel_server.rsp` with your favorite editor.

To disable auto-start for a server, create an empty `nostart` file:

```bash
touch cfg/duel_server/nostart
```

---

## 🧰 Environment

| Variable       | Description                              |
|----------------|------------------------------------------|
| `INSTALL_DIR`  | Root hosting directory                   |
| `SESSION_TYPE` | Either `tmux` or `screen`, auto-detected |
| `MAXCRASH`     | Max restart attempts per server          |
| `ZSERV_BIN`    | Full path to `zserv` binary              |

---

## 📑 License

MIT — free to use, hack, and enjoy.

---

## 📎 Author

Created with love by [@drkop](https://github.com/drkop)

```bash
Game on.
```
