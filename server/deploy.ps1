# Pushes the current project to the Oracle box and restarts the server.
#
#   powershell -File server\deploy.ps1 -Target ubuntu@129.x.x.x
#
# Run server\setup.sh on the VM first - this assumes Godot and the service are
# already there and only replaces the game.
#
# The project goes up as one tarball rather than a recursive copy. A few hundred
# files over scp is a few hundred round trips, and on a link to Frankfurt that
# is the difference between a deploy you do casually and one you avoid.

param(
	[Parameter(Mandatory = $true)][string]$Target,
	[string]$GameDir = '/opt/raid',
	# Which map the box holds open. Empty leaves whatever it is already set to.
	# Written as a systemd drop-in rather than by rewriting the unit, so going
	# back to the world is deleting one file rather than re-running setup.sh.
	[string]$Level = '',
	[int]$Port = 27015,
	[switch]$NoRestart
)

$ErrorActionPreference = 'Stop'

$project = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $env:TEMP 'raid-deploy'
$tarball = Join-Path $env:TEMP 'raid.tar.gz'

# What the server does not need: the import cache (it is rebuilt up there, and
# ours is full of Windows paths), the test scripts and their screenshots, and
# anything already built. addons/ stays - project.godot enables the zipline
# plugin, and --import runs as the editor, which will complain if it is missing.
$exclude = @('.godot', 'build', 'server', 'tools', '.git')

Write-Host "== staging"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Get-ChildItem -Path $project -Force | Where-Object { $exclude -notcontains $_.Name } | ForEach-Object {
	Copy-Item -Path $_.FullName -Destination $stage -Recurse -Force
}

Write-Host "== packing"
if (Test-Path $tarball) { Remove-Item -Force $tarball }
# Windows' own bsdtar, by full path, and not whatever `tar.exe` happens to
# resolve to. Git for Windows ships one at /usr/bin/tar.exe, and if this script
# is launched from a Git Bash shell that PATH is inherited and wins. GNU tar
# reads the colon in `C:\Users\...` as a host separator and tries to *rsh* to a
# machine called C, which fails as "Cannot connect to C: resolve failed" - a
# message that says nothing about tar being the wrong tar.
$tarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path $tarExe)) { $tarExe = 'tar.exe' }
& $tarExe -czf $tarball -C $stage .
$size = [math]::Round((Get-Item $tarball).Length / 1MB, 1)
Write-Host "   $size MB"

Write-Host "== uploading to $Target"
scp $tarball "${Target}:/tmp/raid.tar.gz"

Write-Host "== unpacking and importing"
# The import has to happen before the server starts, not as a side effect of it:
# a first run that is still converting textures is a first run that is not
# answering anybody, and the client that dialled in during it just times out.
$remote = @"
set -e
sudo systemctl stop raid-server 2>/dev/null || true
mkdir -p '$GameDir'
find '$GameDir' -maxdepth 1 -mindepth 1 ! -name '.godot' ! -name '.config' ! -name '.cache' ! -name '.local' -exec rm -rf {} +
tar -xzf /tmp/raid.tar.gz -C '$GameDir'
rm -f /tmp/raid.tar.gz
HOME='$GameDir' XDG_CONFIG_HOME='$GameDir/.config' XDG_CACHE_HOME='$GameDir/.cache' XDG_DATA_HOME='$GameDir/.local/share' /opt/godot/godot --headless --path '$GameDir' --import
"@
ssh $Target $remote

if ($Level) {
	Write-Host "== holding open the '$Level' map"
	$drop = @"
set -e
sudo mkdir -p /etc/systemd/system/raid-server.service.d
sudo tee /etc/systemd/system/raid-server.service.d/level.conf >/dev/null <<'CONF'
[Service]
ExecStart=
ExecStart=/opt/godot/godot --headless --path $GameDir -- --server=$Port --level=$Level
CONF
sudo systemctl daemon-reload
"@
	ssh $Target $drop
}

if (-not $NoRestart) {
	Write-Host "== restarting"
	ssh $Target 'sudo systemctl restart raid-server && sleep 3 && systemctl is-active raid-server'
	Write-Host ''
	Write-Host '== last few lines of the log'
	ssh $Target 'journalctl -u raid-server -n 15 --no-pager'
}

$ip = $Target.Split('@')[-1]
Write-Host ''
Write-Host "Deployed to $ip."
Write-Host 'In the game: JOIN MATCHMAKING. There is no address to type - the'
Write-Host 'client dials Net.MATCHMAKING_HOST, so if that is not the box you just'
Write-Host 'deployed to, the clients need rebuilding as well as the server.'
