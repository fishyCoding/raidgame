# Live Rail across the wire: a real server, two real clients, one hot cable.
#
#   powershell -File server\test_rail.ps1
#   powershell -File server\test_rail.ps1 -Level quarry
#
# Peer 1 lights a cable and peer 2 checks it heard about it, then rides it and
# checks that cost it health inside one frame. What the solo test cannot do.
#
# This file must stay on LF endings - it sends nothing to a box, but its sibling
# deploy.ps1 does and they get edited together. See server/README.md.

param(
	[string]$Level = ''
)

$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\Computer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP 'raid-rail-test'
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host "== starting server on 27781$(if ($Level) { " (map: $Level)" })"
$server = Start-Process -FilePath $godot -PassThru -NoNewWindow `
	-ArgumentList (@('--headless', '--path', $project, '--', '--server=27781') + $(if ($Level) { "--level=$Level" } else { @() })) `
	-RedirectStandardOutput "$out\server.log" -RedirectStandardError "$out\server.err"
$null = $server.Handle

try {
	Start-Sleep -Seconds 6
	if ($server.HasExited) {
		Write-Host '== server died before any client connected:'
		Get-Content "$out\server.log", "$out\server.err" -ErrorAction SilentlyContinue
		exit 1
	}

	$clients = @()
	foreach ($n in 1, 2) {
		Write-Host "== client $n"
		$c = Start-Process -FilePath $godot -PassThru -NoNewWindow `
			-ArgumentList '--headless', '--path', $project, `
				'--script', 'res://tools/rail_net_test.gd', '--', "--peer=$n", '--port=27781' `
			-RedirectStandardOutput "$out\client$n.log" -RedirectStandardError "$out\client$n.err"
		$null = $c.Handle
		$clients += $c
		Start-Sleep -Seconds 3
	}

	foreach ($c in $clients) { [void]$c.WaitForExit(180000) }

	foreach ($n in 1, 2) {
		Write-Host ''
		Write-Host "== client $n"
		Get-Content "$out\client$n.log" -ErrorAction SilentlyContinue | Select-String '\|'
	}

	$failed = 0
	foreach ($c in $clients) { if ($c.ExitCode -ne 0) { $failed++ } }
	Write-Host ''
	if ($failed -gt 0) {
		Write-Host "FAIL - $failed client(s) failed"
		exit 1
	}
	Write-Host 'PASS'
}
finally {
	if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
