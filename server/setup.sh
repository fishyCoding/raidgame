#!/usr/bin/env bash
# Turns a fresh Oracle Cloud VM into a Raid server. Run it once, on the VM:
#
#   curl -fsSLO https://.../setup.sh   # or just scp it up
#   bash setup.sh
#
# It installs Godot for whatever architecture this machine is, makes a home for
# the game, opens the port in the local firewall, and installs a systemd unit so
# the server comes back up on its own after a reboot.
#
# It does NOT touch the Oracle side of the network. The VCN security list has to
# let udp/27015 in as well, and that is a click in the console - see README.md.
# Forgetting it is the single most common reason a server that looks perfectly
# healthy in `systemctl status` cannot be reached from outside.

set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.1}"
PORT="${PORT:-27015}"
GAME_DIR="${GAME_DIR:-/opt/raid}"
GODOT_DIR="/opt/godot"
SERVICE_USER="${SUDO_USER:-$USER}"

say() { printf '\n== %s\n' "$*"; }

# --- Godot, for this machine's architecture ----------------------------------
#
# The free tier gives out two very different machines - an Ampere A1 (arm64) if
# there is capacity, an E2.1.Micro (x86_64) if there is not - and you do not
# always get to choose. Reading it off the machine means this script does not
# care which one you ended up with.

case "$(uname -m)" in
	aarch64) ARCH="linux.arm64" ;;
	x86_64)  ARCH="linux.x86_64" ;;
	*) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac
say "architecture $(uname -m) -> Godot ${ARCH}"

say "installing packages"
if command -v apt-get >/dev/null; then
	sudo apt-get update -qq
	# unzip for the release, fontconfig because Godot wants a font even with
	# nothing to draw it on, the X libraries because the binary links them even
	# in --headless and refuses to start without them.
	sudo apt-get install -y -qq unzip curl fontconfig \
		libx11-6 libxcursor1 libxinerama1 libxrandr2 libxi6 libxext6 libgl1
elif command -v dnf >/dev/null; then
	sudo dnf install -y -q unzip curl fontconfig libX11 libXcursor libXinerama \
		libXrandr libXi libXext mesa-libGL
else
	echo "no apt-get or dnf - install unzip, fontconfig and the libX11 family by hand" >&2
fi

# --- swap, on the small shape ------------------------------------------------
#
# The free x86 shape has 1 GB of RAM, which is plenty to *run* the server and not
# always enough to *import* it - and importing happens on every deploy. Without
# swap the importer is killed partway through by the kernel's OOM reaper and
# leaves a half-built .godot behind, which then fails on start in a way that says
# nothing about memory. Two gigabytes of file costs nothing on a 46 GB disk.

MEM_MB=$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)
if [ "$MEM_MB" -lt 2048 ] && [ ! -f /swapfile ]; then
	say "only ${MEM_MB} MB of RAM - adding a 2 GB swapfile"
	sudo fallocate -l 2G /swapfile 2>/dev/null || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
	sudo chmod 600 /swapfile
	sudo mkswap /swapfile
	sudo swapon /swapfile
	grep -q '^/swapfile' /etc/fstab \
		|| echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

say "installing Godot ${GODOT_VERSION} to ${GODOT_DIR}"
ZIP="Godot_v${GODOT_VERSION}-stable_${ARCH}.zip"
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${ZIP}"
sudo mkdir -p "$GODOT_DIR"
cd "$(mktemp -d)"
curl -fsSL -o "$ZIP" "$URL"
unzip -q -o "$ZIP"
sudo install -m 755 "Godot_v${GODOT_VERSION}-stable_${ARCH}" "${GODOT_DIR}/godot"
"${GODOT_DIR}/godot" --version

# --- somewhere to live -------------------------------------------------------
#
# Owned by the login user rather than a locked-down service account, so that
# deploying is a plain scp with no sudo dance. This is a game server for people
# you know, on a machine that does nothing else; a separate user would buy
# almost nothing and cost a step every single deploy.

say "making ${GAME_DIR}, owned by ${SERVICE_USER}"
sudo mkdir -p "$GAME_DIR"
sudo chown -R "${SERVICE_USER}:${SERVICE_USER}" "$GAME_DIR"

# --- the local firewall ------------------------------------------------------
#
# Oracle's images arrive with the door already shut: Ubuntu ships an iptables
# ruleset ending in REJECT, Oracle Linux ships firewalld. A rule appended to the
# end of the Ubuntu chain never runs, because the REJECT gets there first - so
# this inserts at the top.

say "opening udp/${PORT} in the local firewall"
if command -v firewall-cmd >/dev/null && sudo firewall-cmd --state >/dev/null 2>&1; then
	sudo firewall-cmd --permanent --add-port="${PORT}/udp"
	sudo firewall-cmd --reload
	echo "firewalld: ${PORT}/udp open"
elif command -v iptables >/dev/null; then
	if ! sudo iptables -C INPUT -p udp --dport "$PORT" -j ACCEPT 2>/dev/null; then
		sudo iptables -I INPUT 1 -p udp --dport "$PORT" -j ACCEPT
	fi
	if command -v netfilter-persistent >/dev/null; then
		sudo netfilter-persistent save
	elif [ -d /etc/iptables ]; then
		sudo sh -c "iptables-save > /etc/iptables/rules.v4"
	else
		echo "WARNING: rule added but not saved - it will not survive a reboot" >&2
	fi
	echo "iptables: ${PORT}/udp open"
fi

# --- the service -------------------------------------------------------------

say "installing the raid-server service"
sudo tee /etc/systemd/system/raid-server.service >/dev/null <<UNIT
[Unit]
Description=Raid dedicated server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${GAME_DIR}
# Godot writes its config and its import cache under HOME. Without one it falls
# back to somewhere it cannot write and dies on start with a message about
# nothing in particular.
Environment=HOME=${GAME_DIR}
Environment=XDG_DATA_HOME=${GAME_DIR}/.local/share
Environment=XDG_CONFIG_HOME=${GAME_DIR}/.config
Environment=XDG_CACHE_HOME=${GAME_DIR}/.cache
ExecStart=${GODOT_DIR}/godot --headless --path ${GAME_DIR} -- --server=${PORT}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable raid-server

say "done"
cat <<DONE
Godot is at ${GODOT_DIR}/godot and the game goes in ${GAME_DIR}.

Nothing is running yet - there is no game up there.  From your PC:

    powershell -File server\deploy.ps1 -Target ${SERVICE_USER}@<this-machine's-public-ip>

Two things still to check on the Oracle side, in the console:
  1. VCN > Security Lists > default: an ingress rule for UDP ${PORT}, source 0.0.0.0/0
  2. the instance has a public IPv4 address

Then:  sudo systemctl start raid-server && journalctl -u raid-server -f
DONE
