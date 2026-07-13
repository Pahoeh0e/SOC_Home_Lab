<#
.SYNOPSIS
    Operation Feeding_Time - Test Event Generator
.DESCRIPTION
    Triggers a simulated kill chain across 10 Wazuh custom rules.
    Run as Administrator. Clean up after each phase with -Cleanup.
.NOTES
    Author: Pahoeh0e
    Lab: Proxmox SOC (VLAN 10 internal, VLAN 30 DMZ)
#>

param([switch]$Cleanup)

$Events = @(
    @{
        Phase = "Initial Access"
        RuleID = "100006"
        Description = "Office application spawning cmd.exe"
        Action = { Start-Process -FilePath "cmd.exe" -ArgumentList "/c echo Feeding_Time-InitialAccess" -WindowStyle Hidden }
        Cleanup = { }
    },
    @{
        Phase = "Execution"
        RuleID = "100005"
        Description = "PowerShell with encoded command"
        Action = { powershell -Command "Write-Host 'Feeding_Time-Execution'" }
        Cleanup = { }
    },
    @{
        Phase = "Persistence"
        RuleID = "100014"
        Description = "Scheduled task creation"
        Action = { schtasks /create /tn "Feeding_Time-Persist" /tr "calc.exe" /sc once /st "23:59" /f | Out-Null }
        Cleanup = { schtasks /delete /tn "Feeding_time-Persist" /f | Out-Null }
    },
    @{
        Phase = "Defense Evasion"
        RuleID = "100010"
        Description = "Netsh firewall modification"
        Action = { netsh advfirewall firewall add rule name="Feeding_Time-Evasion" dir=in action=allow protocol=TCP localport=9999 | Out-Null }
        Cleanup = { netsh advfirewall firewall delete rule name="Feeding_Time-Evasion" | Out-Null }
    },
    @{
        Phase = "Credential Access"
        RuleID = "100015"
        Description = "Credential dumping tool execution"
        Action = { 
            if (Test-Path "C:\Tools\procdump.exe") {
                & "C:\Tools\procdump.exe" -accepteula -ma lsass.exe C:\Temp\lsass.dmp 2>$null
            } else {
                Write-Host "[!] ProcDump not found - simulating with certutil" -ForegroundColor Yellow
                certutil -urlcache -split -f http://example.com/test.txt C:\Temp\test.txt | Out-Null
            }
        }
        Cleanup = { Remove-Item "C:\Temp\lsass.dmp","C:\Temp\test.txt" -ErrorAction SilentlyContinue }
    }
)

if ($Cleanup) {
    Write-Host "`n[+] Cleaning up test artifacts..." -ForegroundColor Green
    foreach ($Event in $Events) {
        Write-Host "    [-] $($Event.Phase): $($Event.Description)"
        & $Event.Cleanup
    }
    Write-Host "[+] Cleanup complete.`n" -ForegroundColor Green
    exit
}

Write-Host "`n[!] Operation Feeding_Time - Test Event Generator" -ForegroundColor Cyan
Write-Host "[!] Ensure Wazuh agent is Active before proceeding.`n"

foreach ($Event in $Events) {
    Write-Host "[+] Phase: $($Event.Phase)" -ForegroundColor Yellow
    Write-Host "    Rule ID: $($Event.RuleID)"
    Write-Host "    Description: $($Event.Description)"
    Write-Host "    Triggering..."
    
    & $Event.Action
    
    Write-Host "    [OK] Event triggered. Waiting 15 seconds for Wazuh ingestion..."
    Start-Sleep -Seconds 15
    Write-Host ""
}

Write-Host "[+] All phases triggered. Check Splunk dashboard: Operation Feeding_Time" -ForegroundColor Green
Write-Host "[+] Run with -Cleanup switch to remove artifacts.`n"
