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
