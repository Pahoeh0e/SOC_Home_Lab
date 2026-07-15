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

**Filename:** `Invoice-2026-7843.ps1`  
**Subject:** URGENT: Outstanding Invoice #INV-2026-7843  
**Sender:** accounts@shadowdrop-finance.com  

When the victim double-clicks the attachment, Windows Script Host executes 
the payload, triggering the full kill chain:

```powershell
# Simulated phishing payload - Operation ShadowDrop
# This script executes the same TTPs as a real APT attachment
# but uses benign commands for lab safety

.\test-events.ps1
