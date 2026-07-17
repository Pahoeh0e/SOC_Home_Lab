# SOC Home Lab — Proxmox Edition

**Enterprise-grade Security Operations Center built on Proxmox VE**, demonstrating multi-layered threat detection across network, endpoint, and perimeter layers with real attack simulation.

---

## 📑 Table of Contents
- [Executive Summary](#executive-summary)
- [Architecture](#architecture)
- [Technologies Used](#technologies-used)
- [Detection Capabilities](#detection-capabilities)
- [Attack Scenarios](#attack-scenarios)
- [Security Dashboards](#security-dashboards)
- [Skills Demonstrated](#skills-demonstrated)
- [Documentation](#documentation)

---

## Executive Summary

Production-like SOC environment demonstrating:

- ✅ **Network IDS** — Snort on DMZ endpoint with custom rules
- ✅ **Endpoint Detection** — Wazuh EDR with Sysmon integration
- ✅ **SIEM Analytics** — Splunk Enterprise with custom SPL detections
- ✅ **Perimeter Firewall** — pfSense with VLAN segmentation and logging
- ✅ **MITRE ATT&CK Mapped Detections** — Full kill chain coverage
- ✅ **Live Attack Simulation** — Kali Linux red team against Windows Server & DMZ

### Lab Topology


             ┌─────────────────────────────────────────────────────────────────────────┐
             │                         Proxmox VE Host                                 │
             │                                                                         │
             │   VLAN 10 (Management)    VLAN 20 (Internal)    VLAN 30 (DMZ)           │
             │   10.0.10.0/24            10.0.20.0/24          10.0.30.0/24            │
             │                                                                         │
             │  ┌─────────────┐         ┌─────────────┐       ┌─────────────┐         │
             │  │   Kali      │         │   Windows   │       │   DMZ VM    │         │
             │  │  (Attacker) │         │   Server    │       │ (Snort IDS) │         │
             │  │  10.0.10.10 │◄───────►│  10.0.20.10 │◄─────►│  10.0.30.50 │         │
             │  │             │         │  - AD DS    │       │             │         │
             │  │  Tools:     │         │  - Sysmon   │       │  - Snort    │         │
             │  │  Nmap       │         │  - Splunk UF│       │  - Splunk UF│         │
             │  │  Metasploit │         │  - Wazuh Ag │       │  - Wazuh Ag │         │
             │  │  Hydra      │         │             │       │             │         │
             │  │  Mimikatz   │         │             │       │             │         │
             │  └──────┬──────┘         └──────┬──────┘       └──────┬──────┘         │
             │         │                       │                     │                │
             │         └───────────────────────┼─────────────────────┘                │
             │                                 │                                      │
             │  ┌──────────────────────────────┼─────────────────────────────────┐   │
             │  │                              ▼                                 │   │
             │  │              ┌─────────────────────────────┐                   │   │
             │  │              │      pfSense Firewall       │                   │   │
             │  │              │         10.0.0.1            │                   │   │
             │  │              │                             │                   │   │
             │  │              │  - Inter-VLAN routing       │                   │   │
             │  │              │  - NAT / Port Forwarding    │                   │   │
             │  │              │  - Firewall logging         │                   │   │
             │  │              │  - Suricata (optional)      │                   │   │
             │  │              └──────────────┬──────────────┘                   │   │
             │  │                             │                                  │   │
             │  │              ┌──────────────┴──────────────┐                   │   │
             │  │              │      VLAN 40 (Security)     │                   │   │
             │  │              │         10.0.40.0/24        │                   │   │
             │  │              │                             │                   │   │
             │  │    ┌─────────┴─────────┐   ┌──────────────┴────────┐          │   │
             │  │    │   Wazuh Manager   │   │   Splunk SIEM         │          │   │
             │  │    │   10.0.40.20      │   │   10.0.40.30          │          │   │
             │  │    │                   │   │                       │          │   │
             │  │    │  - EDR Dashboard  │   │  - SIEM Analytics     │          │   │
             │  │    │  - FIM / SCA      │   │  - Detection Rules    │          │   │
             │  │    │  - Vuln Detection │   │  - Dashboards         │          │   │
             │  │    │  - Custom Rules   │   │  - 90-day retention   │          │   │
             │  │    └───────────────────┘   └───────────────────────┘          │   │
             │  │                                                               │   │
             │  └───────────────────────────────────────────────────────────────┘   │
             │                                                                        │
             └────────────────────────────────────────────────────────────────────────┘
             │  │                                                               │   │
             │  └───────────────────────────────────────────────────────────────┘   │
             │                                                                        │
             └────────────────────────────────────────────────────────────────────────┘



---

## Technologies Used

| Layer | Tool | Version | Purpose |
|-------|------|---------|---------|
| **Hypervisor** | Proxmox VE | 9.2 | VM orchestration, VLANs, resource management |
| **SIEM** | Splunk Enterprise | 10.2 | Log aggregation, detection engineering, dashboards |
| **EDR** | Wazuh | 4.14 | Endpoint detection, FIM, vulnerability scanning |
| **IDS** | Snort | 3.1 | Network intrusion detection (DMZ sensor) |
| **Firewall** | pfSense | 2.8 | Perimeter security, VLAN routing, logging |
| **Attacker** | Kali Linux | 2026.2 | Red team simulation |
| **Target** | Windows Server | 2022 | Domain services, attack target |
| **Endpoint Telemetry** | Sysmon | 15.21 | Windows process/network/file telemetry |
| **Log Forwarder** | Splunk Universal Forwarder | 10.4 | Endpoint log shipping |

---

## Detection Capabilities

| ID | Detection | MITRE Technique | Data Source | Severity | 
|----|-----------|----------------|-------------|----------|
| **DET-001** | Port Scan Detection | [T1046](https://attack.mitre.org/techniques/T1046/) | Snort / pfSense | Medium |
| **DET-002** | Brute Force RDP / SSH | [T1110](https://attack.mitre.org/techniques/T1110/) | Windows Event Logs + Wazuh | High |
| **DET-003** | Malicious PowerShell Execution | [T1059.001](https://attack.mitre.org/techniques/T1059/001/) | Sysmon + Splunk | Critical |
| **DET-004** | Lateral Movement (PsExec / WMI) | [T1021.002](https://attack.mitre.org/techniques/T1021/002/) | Sysmon + Wazuh | High |
| **DET-005** | C2 Beaconing Detection | [T1071](https://attack.mitre.org/techniques/T1071/) | Snort + Splunk | High |
| **DET-006** | Credential Dumping (Mimikatz) | [T1003](https://attack.mitre.org/techniques/T1003/) | Sysmon + Wazuh | Critical |
| **DET-007** | Persistence (Registry Run Keys) | [T1547.001](https://attack.mitre.org/techniques/T1547/001/) | Sysmon + Wazuh FIM | Medium |
| **DET-008** | Data Exfiltration | [T1041](https://attack.mitre.org/techniques/T1041/) | Snort + pfSense | High |
| **DET-009** | LOLBAS Tool Execution & Staging | [T1105](https://attack.mitre.org/techniques/T1105/), [T1218](https://attack.mitre.org/techniques/T1218/) | Sysmon + Wazuh | High |
| **DET-010** | LSASS Memory Dump (Event 10) | [T1003.001](https://attack.mitre.org/techniques/T1003/) | Sysmon + Wazuh | Critical |
| **DET-011** | PsExec Named Pipe Detection | [T1021.002](https://attack.mitre.org/techniques/T1021/002/) | Sysmon + Wazuh | High |
| **DET-012** | Event Log Clearing | [T1070.001](https://attack.mitre.org/techniques/T1070/001/) | Sysmon + Wazuh | Medium |
| **DET-013** | Firewall Modification (Netsh) | [T1562.004](https://attack.mitre.org/techniques/T1562/004/) | Sysmon + Wazuh | Medium |
| **DET-014** | Scheduled Task Creation | [T1053.005](https://attack.mitre.org/techniques/T1053/005/) | Sysmon + Wazuh | Medium |

---

## Operations

See [Operations](Operations) for full red team procedures with commands and screenshots.

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
---

## Documentation

| File | Description |
|------|-------------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Proxmox topology, VLAN config, pfSense rules, VM specs |
| [DETECTION-RULES.md](DETECTION-RULES.md) | SPL queries, Wazuh rules, Snort rules, MITRE mappings |
| [Operations.md](Operations) | Step-by-step attack procedures with expected detections |

---

## Skills Demonstrated

- **Blue Team**: SIEM rule development, IDS tuning, EDR deployment, log analysis
- **Red Team**: Attack simulation, MITRE ATT&CK framework mapping, post-exploitation
- **Network Security**: VLAN segmentation, firewall rule design, traffic analysis
- **Virtualization**: Proxmox VM management, VLAN configuration, resource allocation
- **Documentation**: Professional technical writing for security operations

---

**Last Updated**: July 2026
