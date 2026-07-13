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
