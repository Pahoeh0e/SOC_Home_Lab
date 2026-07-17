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
| **Hypervisor** | Proxmox VE | 8.x | VM orchestration, VLANs, resource management |
| **SIEM** | Splunk Enterprise | 9.x | Log aggregation, detection engineering, dashboards |
| **EDR** | Wazuh | 4.7.x | Endpoint detection, FIM, vulnerability scanning |
| **IDS** | Snort | 3.x | Network intrusion detection (DMZ sensor) |
| **Firewall** | pfSense | 2.7.x | Perimeter security, VLAN routing, logging |
| **Attacker** | Kali Linux | 2024.x | Red team simulation |
| **Target** | Windows Server | 2022 | Domain services, attack target |
| **Endpoint Telemetry** | Sysmon | 15.x | Windows process/network/file telemetry |
| **Log Forwarder** | Splunk Universal Forwarder | 9.x | Endpoint log shipping |

---

## Detection Capabilities

| ID | Detection | MITRE Technique | Data Source | Severity |
|----|-----------|----------------|-------------|----------|
| **DET-001** | Port Scan Detection | T1046 | Snort / pfSense | Medium |
| **DET-002** | Brute Force RDP / SSH | T1110 | Windows Event Logs + Wazuh | High |
| **DET-003** | Malicious PowerShell Execution | T1059.001 | Sysmon + Splunk | Critical |
| **DET-004** | Lateral Movement (PsExec / WMI) | T1021.002 | Sysmon + Wazuh | High |
| **DET-005** | C2 Beaconing Detection | T1071 | Snort + Splunk | High |
| **DET-006** | Credential Dumping (Mimikatz) | T1003 | Sysmon + Wazuh | Critical |
| **DET-007** | Persistence (Registry Run Keys) | T1547.001 | Sysmon + Wazuh FIM | Medium |
| **DET-008** | Data Exfiltration | T1041 | Snort + pfSense | High |

### Detection Coverage by Kill Chain Phase

Reconnaissance → Initial Access → Execution → Persistence → Privilege Escalation → Lateral Movement → C2 → Exfiltration
↓              ↓               ↓            ↓                ↓                    ↓            ↓        ↓
(DET-001)     (DET-002)      (DET-003)    (DET-007)        (DET-006)            (DET-004)    (DET-005) (DET-008)
Port Scan     Brute Force    PowerShell   Registry         Mimikatz             PsExec       Beacon   Exfil



---

## Operations

See [Operations](Operations) for full red team procedures with commands and screenshots.

| Scenario | Tools | Target | Detections Triggered |
|----------|-------|--------|---------------------|
| **1. Network Reconnaissance** | Nmap | DMZ / Windows Server | DET-001 |
| **2. RDP Brute Force** | Hydra | Windows Server | DET-002 |
| **3. Reverse Shell (MSF)** | Metasploit | Windows Server | DET-003, DET-005 |
| **4. Credential Dumping** | Mimikatz | Windows Server | DET-006 |
| **5. Lateral Movement** | PsExec | DMZ VM | DET-004 |
| **6. Data Exfiltration** | Netcat / DNS | External via DMZ | DET-008 |

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
