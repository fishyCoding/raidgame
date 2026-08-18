# Builds the web export and serves it on the local network, so the game can be
# opened on a phone's browser without an App Store, an account or a Mac.
#
#   powershell -File server\serve_web.ps1
#   powershell -File server\serve_web.ps1 -NoBuild     # serve what is already there
#
# Print the URL it gives you into Safari on the phone. Both devices have to be on
# the same Wi-Fi, and Windows will likely ask to allow the port through the
# firewall the first time - say yes for private networks.
#
# What this is good for: the touch controls, movement, the feel of the camera -
# anything you can check alone. **Not multiplayer.** ENet is UDP and browsers
# cannot open a UDP socket, so JOIN MATCHMAKING will not connect from a browser.
# Use TEST DRIVE or PLAY ALONE.

param(
	[int]$Port = 8080,
	[switch]$NoBuild
)

$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\Computer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $project 'build\web'

if (-not $NoBuild) {
	Write-Host '== exporting the web build (this takes a minute)'
	New-Item -ItemType Directory -Force -Path $out | Out-Null
	& $godot --headless --path $project --export-release 'Web' (Join-Path $out 'index.html') | Out-Null
	if (-not (Test-Path (Join-Path $out 'index.wasm'))) {
		Write-Host '== export produced no wasm - is the Web export template installed?'
		exit 1
	}
}

# The address the phone has to dial. Link-local and loopback are no use to it.
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
	Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
	Sort-Object -Property SkipAsSource, InterfaceMetric |
	Select-Object -First 1).IPAddress

Write-Host ''
Write-Host '== serving' $out
Write-Host ''
Write-Host "   On the phone, open:   http://${ip}:${Port}/index.html"
Write-Host ''
Write-Host '   Both devices on the same Wi-Fi. Ctrl+C here to stop.'
Write-Host '   Multiplayer will not connect from a browser - use TEST DRIVE.'
Write-Host ''

# Godot's no-threads web build needs no cross-origin isolation, so a plain static
# server is enough - which is the whole reason thread_support is off in the
# preset. Threaded builds would need COOP/COEP headers and this would not do.
python -m http.server $Port --directory $out --bind 0.0.0.0
