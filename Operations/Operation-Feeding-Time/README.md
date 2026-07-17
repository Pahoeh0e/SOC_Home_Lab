## Operation Feeding Time: End-to-End Detection Engineering

### Threat Scenario
A simulated APT-style attack chain targeting a Windows Server 2022 host:
1. **Initial Access** — Spear-phishing with malicious Word macro
2. **Execution** — Macro spawns PowerShell with encoded payload
3. **Persistence** — Scheduled task created via schtasks
4. **Defense Evasion** — Netsh firewall, event log clearing
5. **Credential Access** — LSASS memory dump via comsvcs.dll + ProcDump
6. **Lateral Movement** — PsExec to internal VLAN host
7. **Exfiltration** — BITSAdmin file transfer to external C2

> **Note:** The Initial Access phase (malicious Word macro) is included in the 
> detection rules for completeness, but was not executed in this lab environment 
> as Microsoft Word is not installed on the Windows Server 2022 target. 
> Detection coverage begins from the Execution phase.

### Detection Coverage
This repository implements detection logic for each phase using:
- **Wazuh** for real-time endpoint telemetry (Sysmon integration)
- **Splunk** for correlation, timeline analysis, and dashboarding
- **MITRE ATT&CK** mapping for threat-informed prioritization

### Validation
Every rule was tested against live events in a Proxmox-based SOC lab
with VLAN-segmented networks (VLAN 10 internal, VLAN 30 DMZ).

## Delivery: Phishing Attachment

The attack begins with a spear-phishing email containing a malicious 
PowerShell script disguised as an invoice:

**Filename:** [Invoice-2026-7843.ps1](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Operation-Feeding-Time/Detection-rules/Invoice-2026-7843.ps1)  
**Subject:** URGENT: Outstanding Invoice #INV-2026-7843  
**Sender:** accounts@feeding_time-finance.com  

When the victim double-clicks the attachment, Windows Script Host executes 
the payload, triggering the full kill chain:

-    This script executes the same TTPs as a real APT attachment but uses benign commands for lab safety
-    Since Word wasn't installed on the lab VM, the macro couldn't execute, the simmulated kill chain started from the PowerShell payload stage

### Execution
When double-clicked, the script executes a series of LOLBAS techniques 
that mirror real-world APT behavior:

| Step | Action | Detection |
|------|--------|-----------|
| 1 | PowerShell IEX download from staging server | Wazuh 100005 |
| 2 | Scheduled task creation | Wazuh 100014 |
| 3 | Netsh firewall modification | Wazuh 100010 |
| 4 | Event log clearing | Wazuh 100011 |
| 5 | LSASS memory dump via comsvcs.dll | Wazuh 100400 |
| 6 | Credential dumping tool execution (ProcDump) | Wazuh 100015 |
| 7 | PsExec execution | Wazuh 100016 |
| 8 | PsExec pipe detection | Wazuh 100502 |
| 9 | CertUtil download from staging server | Wazuh 100105 |

![Powershell](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/GitHub_Sp4lunk.png)
![Powershell](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/GitHub_Sp5lunk.png)



### Safety Controls
- No actual malware or exploits
- All network connections target internal lab infrastructure
- Cleanup script used afterwards to remove all artifacts
- Designed for isolated SOC lab environment only


## Detection Coverage

### Immediate Detection (Execution Phase)
**Wazuh Rule 100005** (PowerShell suspicious parameters) fires immediately 
upon script execution, detecting:
- `IEX` Invoke-Expression obfuscation
- `DownloadString` web requests  
- `Net.WebClient` usage

**Alert Level:** 10  
**Event:** Sysmon 1   
**MITRE:** T1059.001, T1027, T1105  
---

### Persistence Detection 
**Wazuh Rule 100014** (Scheduled task creation) fires when schtasks.exe creates a new task, detecting:
- `schtasks /create` command-line usage
- `at.exe` scheduled job creation

**Alert Level:** 10  
**Event:** Sysmon 1   
**MITRE:** T1053.005, T1053.002 
---

### Defence Evasion Detection
**Wazuh Rule 100010** (Netsh firewall modification) fires when netsh modifies
the Windows firewall or adds a helper DLL, detecting:

- `advfirewall` rule additions
- `firewall` configuration changes
- `add helper` DLL registration

**Alert Level:** 10  
**Event:** Sysmon 1   
**MITRE:** T1562.004, T1128

**Wazuh Rule 100011** (Event log clearing) fires when wevtutil.exe clears
or modifies event logs, detecting:
- `wevtutil cl` (clear log)
- `wevtutil sl` (set log)
- `clear-log` or `set-log` parameters

**Alert Level:** 12
**Event:** Sysmon 1
**MITRE:** T1070.001
---

### Staging Server Correlation (Credential Access) Detection

**Wazuh Rule 100400** (LSASS process access) fires when a known credential
dumping tool accesses lsass.exe with suspicious permissions, detecting:
- `0x1010`, `0x143A`, `0x1410`, `0x1FFFFF` (grantedAccess values)
- `procdump.exe`, `rundll32.exe`, `comsvcs.dll` (Source images)

**Alert Level:** 14
**Event:** Sysmon 10
**MITRE:** T1003.001

**Wazuh Rule 100015** (Credential dumping tool execution) fires when known
credential dumping tools are executed, detecting:
- `procdump.exe`, `procdump64.exe`
`mimikatz.exe`, `mimilib.dll`
`lsadump.exe`, `sekurlsa::`
**Alert Level:** 12
**Event:** Sysmon 1
**MITRE:** T1003, T1003.001
---

### Lateral Movement Detection

**Wazuh Rule 100016** (PsExec execution) fires when PsExec or variants are
executed, detecting:
- `psexec.exe`, `psexec64.exe`, `psexesvc.exe`
`paexec.exe`, `csexec.exe`

**Alert Level:** 10
**Event:** Sysmon 1
**MITRE:** T1569.002, T1021.002

**Wazuh Rule 100502** (PsExec pipe detection) fires when PsExec creates its
service named pipe, detecting:
- `\PSEXESVC`, `\paexec`, `\remcom`, `\csexec` Pipe names
  
**Alert Level:** 13
**Event:** Sysmon 17/18
**MITRE:** T1021.002, T1569.002
---

### Staging Server Correlation (Exfiltration)
**Wazuh Rule 100105** (LOLBAS tool making network connection) fires when
CertUtil, BITSAdmin, or EsentUtl make outbound network connections, detecting:
- `certutil.exe` downloading from remote URLs (`192.168.30.12:8080`)
- `bitsadmin.exe` transfer jobs
- `esentutl.exe` network activity

Splunk correlates the endpoint alert with nginx access logs, confirming:
Which payload was requested (`/payload.ps1`, `/stage.ps1`, `/exfil.txt`)
Source IP of the infected host
HTTP status code (200 = successful download)

**Alert Level:** 10
**Event:** Sysmon 3
**MITRE:** T1105, T1218

## Splunk Dashboards

![Splunk](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/GitHub_Sp6lunk.png)
![Splunk](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/GitHub_Sp7lunk.png)
![Splunk](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/GitHub_Sp8lunk.png)
![Splunk](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/GitHub_Sp9lunk.png)


---

### Host Risk Scoring
Each alert contributes to a cumulative risk score:
- Level 14 alerts (LSASS dump): 10 points
- Level 13 alerts (PsExec pipes): 10 points
- Level 12 alerts (event log clearing, credential tools): 7 points
- Level 10 alerts (PowerShell, scheduled tasks, netsh, CertUtil): 5 points

A host scoring **20+** is flagged **CRITICAL** in the Splunk dashboard.

![Splunk](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/GitHub_Sp10lunk.png)

---

## Kill Chain Timeline


| Phase                | Rule   | Time   |
| -------------------- | ------ | ------ |
| 1. Execution         | 100005 | T+0s   |
| 2. Persistence       | 100014 | T+15s  |
| 3. Defense Evasion   | 100010 | T+30s  |
| 3. Defense Evasion   | 100011 | T+45s  |
| 4. Credential Access | 100400 | T+60s  |
| 4. Credential Access | 100015 | T+75s  |
| 5. Lateral Movement  | 100016 | T+90s  |
| 5. Lateral Movement  | 100502 | T+105s |
| 6. Command & Control | 100105 | T+120s |

Total time from execution to C2: **~2 minutes**
![Splunk](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/GitHub_Sp11lunk.png)
