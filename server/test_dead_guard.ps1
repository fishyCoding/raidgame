# A guard killed in a real session has to be dead on every machine in it.
#
#   powershell -File server\test_dead_guard.ps1
#
# Four processes: a server, the client that does the shooting, one that was
# there the whole time and never fired, and one that joins afterwards. The last
# two are the interesting ones - the killer's own machine has never had trouble
# believing what it just did.

$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\Computer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP 'raid-dead-guard-test'
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host '== starting server on 27784'
$server = Start-Process -FilePath $godot -PassThru -NoNewWindow `
	-ArgumentList '--headless', '--path', $project, '--', '--server=27784' `
	-RedirectStandardOutput "$out\server.log" -RedirectStandardError "$out\server.err"
$null = $server.Handle

$names = @{ 1 = 'killer'; 2 = 'watcher'; 3 = 'latecomer' }
$clients = @{}

try {
	Start-Sleep -Seconds 6
	if ($server.HasExited) {
		Write-Host '== server died before any client connected:'
		Get-Content "$out\server.log", "$out\server.err" -ErrorAction SilentlyContinue
		exit 1
	}

	foreach ($n in 1, 2) {
		Write-Host "== $($names[$n])"
		$c = Start-Process -FilePath $godot -PassThru -NoNewWindow `
			-ArgumentList '--headless', '--path', $project, `
				'--script', 'res://tools/dead_guard_test.gd', '--', "--peer=$n", '--port=27784' `
			-RedirectStandardOutput "$out\$($names[$n]).log" -RedirectStandardError "$out\$($names[$n]).err"
		$null = $c.Handle
		$clients[$n] = $c
		Start-Sleep -Seconds 2
	}

	# Late enough that the shooting is over and the guard has been on the floor a
	# while before this one has a level to put him in - and early enough that the
	# other two are still in the raid when it lands, or the server empties and
	# resets the match it was joining.
	Start-Sleep -Seconds 22
	Write-Host '== latecomer (arrives after the shooting)'
	$c = Start-Process -FilePath $godot -PassThru -NoNewWindow `
		-ArgumentList '--headless', '--path', $project, `
			'--script', 'res://tools/dead_guard_test.gd', '--', '--peer=3', '--port=27784' `
		-RedirectStandardOutput "$out\latecomer.log" -RedirectStandardError "$out\latecomer.err"
	$null = $c.Handle
	$clients[3] = $c

	foreach ($n in 1, 2, 3) { [void]$clients[$n].WaitForExit(300000) }

	foreach ($n in 1, 2, 3) {
		Write-Host ''
		Write-Host "== $($names[$n])"
		Get-Content "$out\$($names[$n]).log" -ErrorAction SilentlyContinue | Select-String '\|'
		Get-Content "$out\$($names[$n]).err" -ErrorAction SilentlyContinue |
			Select-String 'SCRIPT ERROR' | Select-Object -First 5
	}

	$failed = 0
	foreach ($n in 1, 2, 3) { if ($clients[$n].ExitCode -ne 0) { $failed++ } }

	# The check no client can make for itself: that the three of them are looking
	# at the same graveyard. Each one is perfectly self-consistent about a guard
	# who is still standing, which is why this has to be compared across logs.
	$dead = @()
	foreach ($n in 1, 2, 3) {
		$line = Get-Content "$out\$($names[$n]).log" -ErrorAction SilentlyContinue |
			Select-String '\| dead: ' | Select-Object -First 1
		if ($line) { $dead += ($line.ToString() -replace '^.*\| dead: ', '') } else { $dead += '<none>' }
	}
	Write-Host ''
	if ($dead[0] -ne '<none>' -and $dead[0] -ne '' -and $dead[0] -eq $dead[1] -and $dead[1] -eq $dead[2]) {
		Write-Host "== all three agree on who is dead: $($dead[0])"
	} else {
		Write-Host '== THEY DISAGREE ABOUT WHO IS DEAD'
		Write-Host "   killer:    $($dead[0])"
		Write-Host "   watcher:   $($dead[1])"
		Write-Host "   latecomer: $($dead[2])"
		$failed++
	}

	Write-Host ''
	if ($failed -eq 0) { Write-Host 'PASS - dead everywhere, not just where it happened' }
	else { Write-Host "FAIL - $failed check(s) failed" }
	exit $failed
}
finally {
	if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
