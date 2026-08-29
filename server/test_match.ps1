# Runs a full match locally: a real server, two real clients, wait -> countdown
# -> deploy -> shoot something.
#
#   powershell -File server\test_match.ps1
#
# The second client is started ten seconds late on purpose. The first one has to
# sit there waiting, and that wait is half of what is being tested.

param(
	# Which map the server holds open. Empty means the world, as before.
	[string]$Level = ''
)

$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\Computer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP 'raid-match-test'
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host "== starting server on 27780$(if ($Level) { " (map: $Level)" })"
$server = Start-Process -FilePath $godot -PassThru -NoNewWindow `
	-ArgumentList (@('--headless', '--path', $project, '--', '--server=27780') + $(if ($Level) { "--level=$Level" } else { @() })) `
	-RedirectStandardOutput "$out\server.log" -RedirectStandardError "$out\server.err"
$null = $server.Handle

try {
	Start-Sleep -Seconds 6
	if ($server.HasExited) {
		Write-Host '== server died before any client connected:'
		Get-Content "$out\server.log", "$out\server.err" -ErrorAction SilentlyContinue
		exit 1
	}

	Write-Host '== client 1 (alone - should wait)'
	$c1 = Start-Process -FilePath $godot -PassThru -NoNewWindow `
		-ArgumentList '--headless', '--path', $project, `
			'--script', 'res://tools/match_test.gd', '--', '--peer=1', '--port=27780' `
		-RedirectStandardOutput "$out\client1.log" -RedirectStandardError "$out\client1.err"
	$null = $c1.Handle

	Start-Sleep -Seconds 10
	Write-Host '== client 2 (arrives - should start the countdown)'
	$c2 = Start-Process -FilePath $godot -PassThru -NoNewWindow `
		-ArgumentList '--headless', '--path', $project, `
			'--script', 'res://tools/match_test.gd', '--', '--peer=2', '--port=27780' `
		-RedirectStandardOutput "$out\client2.log" -RedirectStandardError "$out\client2.err"
	$null = $c2.Handle

	[void]$c1.WaitForExit(180000)
	[void]$c2.WaitForExit(180000)

	foreach ($n in 1, 2) {
		Write-Host ''
		Write-Host "== client $n"
		Get-Content "$out\client$n.log" -ErrorAction SilentlyContinue | Select-String '\|'
	}
	Write-Host ''
	Write-Host '== server'
	Get-Content "$out\server.log" -ErrorAction SilentlyContinue | Select-String 'server\]'

	$failed = 0
	foreach ($c in $c1, $c2) { if ($c.ExitCode -ne 0) { $failed++ } }

	# The one check neither client can make on its own: that the bodies on the
	# floor are the same bodies, with the same kit in them, on both machines.
	$manifest = @()
	foreach ($n in 1, 2) {
		$line = Get-Content "$out\client$n.log" -ErrorAction SilentlyContinue |
			Select-String '\| bodies ' | Select-Object -First 1
		if ($line) { $manifest += ($line.ToString() -replace '^.*\| bodies ', '') }
		else { $manifest += '' }
	}
	# Exactly one client may have been let into the shared body. Two is loot
	# duplicated; none means nobody could search anything at all.
	$granted = 0
	$after = @()
	$chose = @()
	foreach ($n in 1, 2) {
		$log = Get-Content "$out\client$n.log" -ErrorAction SilentlyContinue
		if ($log | Select-String '\| search granted') { $granted++ }
		$line = $log | Select-String '\| after ' | Select-Object -First 1
		if ($line) { $after += ($line.ToString() -replace '^.*\| after ', '') } else { $after += '<none>' }
		$line = $log | Select-String '\| chose ' | Select-Object -First 1
		if ($line) { $chose += ($line.ToString() -replace '^.*\| chose ', '') } else { $chose += '<none>' }
	}

	Write-Host ''
	# Asserted before the grant count, because it is what makes that count mean
	# anything: two clients kneeling over two different corpses are both entitled
	# to a yes, and the log then reads exactly like loot being handed out twice.
	if ($chose[0] -ne '<none>' -and $chose[0] -eq $chose[1]) {
		Write-Host "== both clients went for the same body: $($chose[0])"
	} else {
		Write-Host '== THEY PICKED DIFFERENT BODIES - the race below proves nothing'
		Write-Host "   client 1: $($chose[0])"
		Write-Host "   client 2: $($chose[1])"
		$failed++
	}

	if ($granted -eq 1) {
		Write-Host '== exactly one client was let into the shared body'
	} else {
		Write-Host "== WRONG - $granted of 2 clients were let into the same body"
		$failed++
	}
	if ($after[0] -eq $after[1]) {
		Write-Host "== and both agree on what is left on it: $($after[0])"
	} else {
		Write-Host '== SEARCHED BODY DIFFERS between the two clients'
		Write-Host "   client 1: $($after[0])"
		Write-Host "   client 2: $($after[1])"
		$failed++
	}

	Write-Host ''
	if ($manifest[0] -ne '' -and $manifest[0] -eq $manifest[1]) {
		Write-Host "== both clients see the same bodies:"
		Write-Host "   $($manifest[0])"
	} else {
		Write-Host '== BODIES DIFFER between the two clients'
		Write-Host "   client 1: $($manifest[0])"
		Write-Host "   client 2: $($manifest[1])"
		$failed++
	}

	Write-Host ''
	if ($failed -eq 0) { Write-Host 'PASS - the match ran and the shooting counted' }
	else { Write-Host "FAIL - $failed check(s) failed" }
	exit $failed
}
finally {
	if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
