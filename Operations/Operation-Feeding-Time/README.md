## Operation Feeding Time: End-to-End Detection Engineering

### Threat Scenario
A simulated APT-style attack chain targeting a Windows Server 2022 host:
1. **Initial Access** — Spear-phishing with malicious Word macro
2. **Execution** — Macro spawns PowerShell with encoded payload
3. **Persistence** — Scheduled task created via schtasks
4. **Defense Evasion** — AMSI bypass attempt, event log clearing
5. **Credential Access** — LSASS memory dump via ProcDump
6. **Lateral Movement** — PsExec to internal VLAN host
7. **Exfiltration** — BITSAdmin file transfer to external C2

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

### Execution
When double-clicked, the script executes a series of LOLBAS techniques 
that mirror real-world APT behavior:

| Step | Action | Detection |
|------|--------|-----------|
| 1 | PowerShell with encoded command | Wazuh 100005 |
| 2 | Scheduled task creation | Wazuh 100014 |
| 3 | Firewall modification | Wazuh 100010 |
| 4 | CertUtil download | Wazuh 100001 |
| 5 | BITSAdmin exfiltration | Wazuh 100018 |

![Powershell](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Windows_macro_3.png)
![Powershell](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Windows_macro_2.png)
![Powershell](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Windows_macro_1.png)


### Safety Controls
- No actual malware or exploits
- All network connections target internal lab infrastructure
- Cleanup script removes all artifacts
- Designed for isolated SOC lab environment only


## Detection Coverage

### Immediate Detection (Execution Phase)
**Wazuh Rule 100005** (PowerShell suspicious parameters) fires immediately 
upon script execution, detecting:
- `-enc` encoded commands
- `DownloadString` web requests  
- `IEX` (Invoke-Expression) obfuscation

**Alert Level:** 10  
**MITRE:** T1059.001  

---

### Staging Server Correlation (Credential Access + Exfiltration)
**Wazuh Rule 100001** (CertUtil execution) + **Rule 100105** (LOLBAS network 
connection) fire in sequence when the payload downloads from 
`192.168.30.12:8080`.



Splunk correlates both alerts with Nginx access logs, confirming:
- Which payload was requested (`/payload.txt`, `/stage.ps1`)
- Source IP of the infected host
- HTTP status code (200 = successful download)

![Splunk](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Splunk_Feeding_Time_3.png)
![Splunk](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Splunk_Feeding_Time_4.png)
![Splunk](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Splunk_Feeding_Time_5.png)
![Splunk](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Splunk_Feeding_Time_6.png)

---

### Host Risk Scoring
Each alert contributes to a cumulative risk score:
- Level 14 alerts (Mimikatz, LSASS dump): **10 points**
- Level 12 alerts (MSHTA, Regsvr32): **7 points**  
- Level 10 alerts (CertUtil, Netsh, BITSAdmin): **5 points**
- Level 8-9 alerts (suspicious DNS): **3 points**

A host scoring **20+** is flagged **CRITICAL** in the Splunk dashboard.

---

### Kill Chain Timeline
The Splunk timeline panel visualizes phase progression:
- **10:00 PM:** Initial Access (PowerShell execution)
- **10:01 PM:** Persistence (scheduled task)
- **10:02 PM:** Defense Evasion (firewall + log clear)
- **10:03 PM:** Credential Access (CertUtil download)
- **10:04 PM:** Exfiltration (BITSAdmin transfer)

Total time from initial execution to exfiltration: **~4 minutes**
