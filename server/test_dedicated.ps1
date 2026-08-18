# Runs the dedicated server and two clients against it, locally, and reports.
#
# This is the rehearsal for the Oracle box: the server is started with exactly
# the command the systemd unit uses, so if this passes here the only things left
# that can go wrong on the VM are the network and the firewall.
#
#   powershell -File server\test_dedicated.ps1

$ErrorActionPreference = 'Stop'

$godot = 'C:\Users\Computer\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe'
$project = Split-Path -Parent $PSScriptRoot
$out = Join-Path $env:TEMP 'raid-dedicated-test'
New-Item -ItemType Directory -Force -Path $out | Out-Null

Write-Host '== starting server on 27778'
$server = Start-Process -FilePath $godot -PassThru -NoNewWindow `
	-ArgumentList '--headless', '--path', $project, '--', '--server=27778' `
	-RedirectStandardOutput "$out\server.log" -RedirectStandardError "$out\server.err"

try {
	# The server has a level to load before it can answer anybody.
	Start-Sleep -Seconds 6

	if ($server.HasExited) {
		Write-Host '== server died before any client connected:'
		Get-Content "$out\server.log", "$out\server.err" -ErrorAction SilentlyContinue
		exit 1
	}

	$clients = @()
	foreach ($n in 1, 2) {
		$client = Start-Process -FilePath $godot -PassThru -NoNewWindow `
			-ArgumentList '--headless', '--path', $project, `
				'--script', 'res://tools/dedicated_test.gd', '--', "--peer=$n" `
			-RedirectStandardOutput "$out\client$n.log" -RedirectStandardError "$out\client$n.err"
		# Touching Handle caches it. Without that, PowerShell 5.1 hands back a
		# process object whose ExitCode is null forever, and a client that passed
		# reads as a client that failed.
		$null = $client.Handle
		$clients += $client
		Start-Sleep -Milliseconds 700
	}

	# WaitForExit() on the object rather than Wait-Process: the pipeline version
	# leaves ExitCode null, which reads as a failure for a client that passed.
	$clients | ForEach-Object { [void]$_.WaitForExit(120000) }

	foreach ($n in 1, 2) {
		Write-Host ''
		Write-Host "== client $n"
		Get-Content "$out\client$n.log" -ErrorAction SilentlyContinue
	}
	Write-Host ''
	Write-Host '== server'
	Get-Content "$out\server.log" -ErrorAction SilentlyContinue

	$clients | ForEach-Object { Write-Host "exit code: $($_.ExitCode)" }
	$failed = @($clients | Where-Object { $_.ExitCode -ne 0 }).Count
	Write-Host ''
	if ($failed -eq 0) { Write-Host 'PASS - both clients played on the dedicated server' }
	else { Write-Host "FAIL - $failed of 2 clients failed" }
	exit $failed
}
finally {
	if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
}
