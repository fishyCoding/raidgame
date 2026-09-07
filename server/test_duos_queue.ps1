# A duos queuer must not deploy alone - see tools/duos_queue_test.gd for the
# bug this guards against.
#
#   powershell -File server\test_duos_queue.ps1
#
# Peer 1 sits alone long enough that a solo queuer in its place already would
# have deployed (test_queue.ps1's countdown is 10s; this waits 15s). Peer 2
# then arrives, and both should pair and deploy together.

$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\Computer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP 'raid-duos-queue-test'
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host '== starting server on 27784'
$server = Start-Process -FilePath $godot -PassThru -NoNewWindow `
	-ArgumentList '--headless', '--path', $project, '--', '--server=27784' `
	-RedirectStandardOutput "$out\server.log" -RedirectStandardError "$out\server.err"
$null = $server.Handle

try {
	Start-Sleep -Seconds 6
	if ($server.HasExited) {
		Write-Host '== server died before any client connected:'
		Get-Content "$out\server.log", "$out\server.err" -ErrorAction SilentlyContinue
		exit 1
	}

	Write-Host '== client 1 (duos, alone - must not deploy)'
	$c1 = Start-Process -FilePath $godot -PassThru -NoNewWindow `
		-ArgumentList '--headless', '--path', $project, `
			'--script', 'res://tools/duos_queue_test.gd', '--', '--peer=1', '--port=27784' `
		-RedirectStandardOutput "$out\client1.log" -RedirectStandardError "$out\client1.err"
	$null = $c1.Handle

	Start-Sleep -Seconds 18
	Write-Host '== client 2 (duos - should pair with client 1)'
	$c2 = Start-Process -FilePath $godot -PassThru -NoNewWindow `
		-ArgumentList '--headless', '--path', $project, `
			'--script', 'res://tools/duos_queue_test.gd', '--', '--peer=2', '--port=27784' `
		-RedirectStandardOutput "$out\client2.log" -RedirectStandardError "$out\client2.err"
	$null = $c2.Handle

	foreach ($c in $c1, $c2) { [void]$c.WaitForExit(240000) }

	foreach ($n in 1, 2) {
		Write-Host ''
		Write-Host "== client $n"
		Get-Content "$out\client$n.log" -ErrorAction SilentlyContinue | Select-String '\|'
		Get-Content "$out\client$n.err" -ErrorAction SilentlyContinue |
			Select-String 'SCRIPT ERROR|ERROR' | Select-Object -First 5
	}
	Write-Host ''
	Write-Host '== server'
	Get-Content "$out\server.log" -ErrorAction SilentlyContinue | Select-String 'server\]'

	$failed = 0
	foreach ($c in $c1, $c2) { if ($c.ExitCode -ne 0) { $failed++ } }

	Write-Host ''
	if ($failed -eq 0) { Write-Host 'PASS - nobody deployed without a squadmate' }
	else { Write-Host "FAIL - $failed client(s) failed" }
	exit $failed
}
finally {
	if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
