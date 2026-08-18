# A player dies in a real session, and both machines have to end up with the
# same body on the same floor carrying the same kit.
#
#   powershell -File server\test_death_loot.ps1

$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\Computer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP 'raid-death-loot-test'
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host '== starting server on 27782'
$server = Start-Process -FilePath $godot -PassThru -NoNewWindow `
	-ArgumentList '--headless', '--path', $project, '--', '--server=27782' `
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
				'--script', 'res://tools/death_loot_test.gd', '--', "--peer=$n", '--port=27782' `
			-RedirectStandardOutput "$out\client$n.log" -RedirectStandardError "$out\client$n.err"
		$null = $c.Handle
		$clients += $c
		Start-Sleep -Seconds 2
	}

	foreach ($c in $clients) { [void]$c.WaitForExit(240000) }

	foreach ($n in 1, 2) {
		Write-Host ''
		Write-Host "== client $n"
		Get-Content "$out\client$n.log" -ErrorAction SilentlyContinue | Select-String '\|'
		Get-Content "$out\client$n.err" -ErrorAction SilentlyContinue |
			Select-String 'SCRIPT ERROR|ERROR' | Select-Object -First 5
	}

	$failed = 0
	foreach ($c in $clients) { if ($c.ExitCode -ne 0) { $failed++ } }

	# The check neither client can make: that the body the dead player left is
	# the same body, with the same kit, on both machines. Only the machine that
	# died knew what was in that pack - none of it was ever replicated - so a
	# manifest that agrees is the whole feature working.
	$dropped = @()
	foreach ($n in 1, 2) {
		$line = Get-Content "$out\client$n.log" -ErrorAction SilentlyContinue |
			Select-String '\| dropped ' | Select-Object -First 1
		if ($line) { $dropped += ($line.ToString() -replace '^.*\| dropped ', '') }
		else { $dropped += '<none>' }
	}
	Write-Host ''
	if ($dropped[0] -ne '<none>' -and $dropped[0] -eq $dropped[1]) {
		Write-Host "== both machines see the same body:"
		Write-Host "   $($dropped[0])"
	} else {
		Write-Host '== THE DROPPED BODY DIFFERS between the two clients'
		Write-Host "   client 1: $($dropped[0])"
		Write-Host "   client 2: $($dropped[1])"
		$failed++
	}

	# And that going through it emptied it for the man who did not.
	$left = @()
	foreach ($n in 1, 2) {
		$line = Get-Content "$out\client$n.log" -ErrorAction SilentlyContinue |
			Select-String '\| left on the body ' | Select-Object -First 1
		if ($line) { $left += ($line.ToString() -replace '^.*\| left on the body ', '') }
		else { $left += '<none>' }
	}
	Write-Host ''
	if ($left[0] -eq $left[1]) {
		Write-Host "== and agree on what is left after the search: $($left[0])"
	} else {
		Write-Host '== WHAT IS LEFT ON IT DIFFERS between the two clients'
		Write-Host "   client 1: $($left[0])"
		Write-Host "   client 2: $($left[1])"
		$failed++
	}

	Write-Host ''
	if ($failed -eq 0) { Write-Host 'PASS - dying costs you the kit, and somebody else can pick it up' }
	else { Write-Host "FAIL - $failed check(s) failed" }
	exit $failed
}
finally {
	if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
