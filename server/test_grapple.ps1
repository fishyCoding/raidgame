# A hook fired in a real session, watched from the other end.
#
#   powershell -File server\test_grapple.ps1
#
# Client 1 grapples; client 2 only looks. A hook that works on the machine that
# fired it and nowhere else passes every single-player check there is.

$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\Computer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP 'raid-grapple-test'
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host '== starting server on 27781'
$server = Start-Process -FilePath $godot -PassThru -NoNewWindow `
	-ArgumentList '--headless', '--path', $project, '--', '--server=27781' `
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
		$c = Start-Process -FilePath $godot -PassThru -NoNewWindow `
			-ArgumentList '--headless', '--path', $project, `
				'--script', 'res://tools/grapple_net_test.gd', '--', "--peer=$n", '--port=27781' `
			-RedirectStandardOutput "$out\client$n.log" -RedirectStandardError "$out\client$n.err"
		$null = $c.Handle
		$clients += $c
		Start-Sleep -Seconds 2
	}

	foreach ($c in $clients) { [void]$c.WaitForExit(180000) }

	foreach ($n in 1, 2) {
		Write-Host ''
		Write-Host "== client $n"
		Get-Content "$out\client$n.log" -ErrorAction SilentlyContinue | Select-String '\|'
		Get-Content "$out\client$n.err" -ErrorAction SilentlyContinue | Select-String 'SCRIPT ERROR|ERROR' | Select-Object -First 5
	}

	$failed = 0
	foreach ($c in $clients) { if ($c.ExitCode -ne 0) { $failed++ } }

	# The check neither client can make: that the rope ends in the same place on
	# both machines. Two raycasts half a frame apart bite the same wall a step
	# further along, which is why the anchor is sent rather than agreed.
	$anchors = @()
	foreach ($n in 1, 2) {
		$line = Get-Content "$out\client$n.log" -ErrorAction SilentlyContinue |
			Select-String '\| anchor ' | Select-Object -First 1
		if ($line) { $anchors += ($line.ToString() -replace '^.*\| anchor ', '') }
		else { $anchors += '<none>' }
	}
	Write-Host ''
	if ($anchors[0] -ne '<none>' -and $anchors[0] -eq $anchors[1]) {
		Write-Host "== both machines put the anchor in the same place: $($anchors[0])"
	} else {
		Write-Host '== THE ANCHOR DIFFERS between the two clients'
		Write-Host "   client 1: $($anchors[0])"
		Write-Host "   client 2: $($anchors[1])"
		$failed++
	}

	Write-Host ''
	if ($failed -eq 0) { Write-Host 'PASS - the hook bit, pulled, and was seen from both ends' }
	else { Write-Host "FAIL - $failed client(s) failed" }
	exit $failed
}
finally {
	if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
