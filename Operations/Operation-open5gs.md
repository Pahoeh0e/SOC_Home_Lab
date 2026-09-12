# Containerised 5G Standalone Core — Lab Build & Analysis

A self-directed lab project deploying a full 5G Standalone (SA) core network in Docker, using Open5GS and UERANSIM, on a Proxmox-hosted Ubuntu VM. Built to develop hands-on familiarity with 5G Core architecture (SBA, NGAP, PFCP, GTP-U) and to practice systematic debugging of a multi-component containerised system.

## 1. Motivation

This project was built to gain practical exposure to the technologies referenced in UKTL's Graduate/Placement scheme — 5G Service-Based Architecture, NGAP/SCTP signalling, and Linux-based container operations — rather than approaching them only from documentation. The goal was not just to get a working deployment, but to understand *why* each component behaves the way it does, and to document the debugging process as evidence of investigative method.

## 2. Architecture

The deployment uses [`docker_open5gs`](https://github.com/herlesupreeth/docker_open5gs), which containerises:

- **Open5GS** — 5G Core network functions: AMF, SMF, UPF, NRF, SCP, UDM, UDR, AUSF, PCF, BSF, NSSF
- **UERANSIM** — simulated gNB and UE, used in place of real radio hardware
- **MongoDB** — subscriber data store, backing UDM/UDR
- **Open5GS WebUI** — subscriber provisioning interface

```
UE (UERANSIM) ──radio (simulated)── gNB (UERANSIM)
                                        │
                                   N2 (NGAP/SCTP)   N3 (GTP-U)
                                        │                │
                                       AMF ──SBI(HTTP2)── SMF ──PFCP── UPF ── Internet (NAT)
                                        │                 │
                                       AUSF/UDM/UDR ── PCF/NRF/SCP
```

All network functions communicate over Docker's internal bridge network (`172.22.0.0/24`), with each NF discovering the others via the NRF — a direct example of 5G's Service-Based Architecture, where functions register and discover each other over REST/HTTP2 rather than being statically wired together as in legacy telecom architectures.

## 3. Environment

- **Host:** Proxmox VE (KVM)
- **Guest:** Ubuntu 24.04 LTS (Noble), minimal server install
- **Container runtime:** Docker CE + Compose v2 (official Docker repo, not the distro's `docker.io` package)

## 4. Build Log — Issues Encountered and Resolved

Documenting the debugging process, since this is where most of the actual learning happened.

### 4.1 Docker installation — package conflict

Initial install via `sudo apt install docker.io` did not include the Compose v2 plugin required by the project's compose files. Resolved by removing `docker.io` and installing from Docker's official APT repository (`docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-compose-plugin`).

**Takeaway:** Ubuntu's own repo and Docker's official repo package Docker differently; mixing them causes silent feature gaps rather than an obvious error.

### 4.2 MongoDB crash — CPU feature (AVX) not exposed to the VM

MongoDB 5.0+ requires AVX CPU instructions. The container failed on start:

```
WARNING: MongoDB 5.0+ requires a CPU with AVX support, and your current system does not appear to have that!
```

`cat /proc/cpuinfo | grep avx` on the guest returned nothing, despite the physical host CPU supporting AVX. Root cause: Proxmox's default virtual CPU type (`kvm64`) does not pass through all host CPU features.

**Fix:** Proxmox VM → Hardware → Processors → CPU type set to `host` (full passthrough), followed by a full VM shutdown/restart (CPU model is only renegotiated on cold boot, not reboot).

**Trade-off noted:** `host` CPU type prevents live migration to a node with a different physical CPU — acceptable for a single-node lab, not for a production multi-node cluster (where a named baseline model, e.g. `x86-64-v3`, would be the standard middle ground).

### 4.3 SMF/UPF subnet misconfiguration

SMF crashed on startup:

```
[pfcp] FATAL: ogs_pfcp_subnet_add: Assertion `rv == OGS_OK' failed
```

Root cause: `.env` defined `UE_IPV4_INTERNET` using a specific host address in CIDR form (`10.0.0.105/12`) rather than a proper network address, and the range also overlapped the VM's real LAN subnet — creating routing ambiguity even once parsing succeeded.

**Fix:** Verified against the project's official `.env.example` and set the UE address pools to a distinct, non-overlapping private range:
```
UE_IPV4_INTERNET=10.45.0.0/24
UE_IPV4_IMS=10.46.0.0/24
```

**Takeaway:** verified the fix against the upstream repository rather than trusting a plausible-sounding but incorrect first attempt — an assumption about variable naming was initially wrong and was corrected by checking the source.

### 4.4 UE authentication failure — SQN synchronisation

UE registration failed:
```
[nas] [error] Initial Registration failed [FIVEG_SERVICES_NOT_ALLOWED]
```
then, after provisioning a subscriber:
```
[nas] [debug] Sending Authentication Failure due to SQN out of range
```

First failure: no subscriber existed for the UE's IMSI in the core's database. Second failure: the subscriber's security fields (K / Operator Key) were mistyped when hand-entering into the WebUI (no clipboard access to the headless VM) — a value intended for the OP field was mistakenly entered into the K field, and vice versa, corrupting the AKA authentication vectors.

**Fix:** Deleted and correctly re-created the subscriber, carefully matching each field to its `.env`-defined value, and verified key length (32 hex characters) via `wc -c` before re-entry.

**Takeaway:** SQN failures during AKA authentication are not always literal SQN desync — they can also surface as the resulting symptom of a K/OP key mismatch, since AKA's automatic resync mechanism itself depends on those same keys being correct.

## 5. Result — Working End-to-End Data Path

Following the fixes above, the UE:

1. Completed NAS registration (`Registration accept received`)
2. Established a PDU session (`PDU Session establishment is successful PSI[1]`)
3. Received a tunnel IP from the configured pool (`TUN interface[uesimtun0, 10.45.0.2] is up`)
4. Successfully routed real traffic through the core to the internet:

```
$ docker exec -it nr_ue ping -I uesimtun0 8.8.8.8
13 packets transmitted, 13 received, 0% packet loss
rtt min/avg/max/mdev = 26.068/31.053/74.514/12.600 ms
```

(Achieved via a NAT masquerade rule on the host, allowing UPF's internal tunnel interface to route the UE's private address pool out to the internet:)
```
sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/24 ! -o ogstun -j MASQUERADE
```

## 6. Protocol Analysis (Wireshark)

Captured traffic on the Docker bridge network during a fresh UE registration cycle, isolated with:
```
sctp || ngap || pfcp || gtpv2
```

### 6.1 Registration sequence observed

| Packet | NGAP/PFCP Procedure | Significance |
|---|---|---|
| InitialUEMessage | Registration request | UE's first message to AMF; carries nested NAS Registration Request |
| Downlink/Uplink NAS Transport | Authentication | AKA challenge/response |
| Downlink/Uplink NAS Transport | Security Mode Command/Complete | NAS integrity algorithm agreed |
| UEContextReleaseCommand/Complete | — | AMF clearing a stale context from a prior test run |
| PFCP Session Deletion Req/Resp | — | SMF/UPF clearing a stale session, same cause as above |
| InitialContextSetupRequest/Response | — | AMF instructs gNB to establish UE context |
| PFCP Session Establishment Request/Response | — | SMF/UPF establishing the new session and its forwarding rules |
| PDUSessionResourceSetupRequest/Response | — | RAN-side resources allocated for the data session |

### 6.2 Key fields inspected

**InitialUEMessage** protocol IEs (packet 2809): `RAN-UE-NGAP-ID`, `NAS-PDU`, `UserLocationInformation`, `RRCEstablishmentCause`, `UEContextRequest` — confirming the message structure matches the 3GPP NGAP specification for this procedure.

**PFCP Session Establishment Request** (packet 3223) — decoded fields included:
- Subscriber identity propagated from SMF to UPF: `IMSI 001011234567895`, `IMEI`, `MCC/MNC (001/01)`
- `APN/DNN: internet`, `S-NSSAI: SST 01, SD ffffff` — confirming network slice information travels with the session
- `Create PDR / FAR / URR / QER / BAR` — the actual packet-handling rules instructing UPF how to detect, forward, and police the UE's traffic
- `F-SEID` — the session identifier binding this PFCP session between SMF and UPF

This confirmed, at the packet level, that subscriber and slice context genuinely propagate through the core's internal signalling (SMF→UPF) — not just at the RAN-facing edge.

### 6.3 Traffic identified and excluded as non-signalling noise

Periodic `PFCP Heartbeat Request/Response` (SMF↔UPF) and `SCTP HEARTBEAT/HEARTBEAT_ACK` (gNB↔AMF) were identified as routine liveness checks between already-associated network functions, and excluded from the analysis as they are not part of the registration procedure itself.

## 7. SOC Tooling Integration — Wazuh + Custom Log Parser

To extend the project beyond deployment/protocol analysis and into a security-monitoring context, a Wazuh manager/agent pair was deployed and pointed at the lab, with a custom-built Python analyser used to process the resulting alert stream.

### 7.1 Deployment

- **Wazuh agent** installed on the `5gserver` VM (the Open5GS host) via the official DEB repository, enrolled against a separate Wazuh manager instance.
- **Debugging note:** the initial `apt-get install wazuh-agent` failed with `Unable to locate package`, because the Wazuh APT repository had not actually been added yet — a piping mistake (`sudo` applied to the wrong side of an `echo | tee` pipeline) meant the repo file was never written to `/etc/apt/sources.list.d/`. Re-running the `tee` step with `sudo` correctly applied resolved it; `sudo apt-get update` then correctly listed the Wazuh repository and the install succeeded. Kept as an example of a silent, non-obvious failure mode (the shell gave no error, it just didn't do what was intended).
- Confirmed connectivity via the agent's own log (`/var/ossec/logs/ossec.log`) and cross-checked in the manager's **Discover** dashboard, which showed the agent (`5gserver`, agent ID `009`) actively reporting.

### 7.2 Security Configuration Assessment (SCA)

Out of the box, Wazuh's SCA module benchmarked the host against the **CIS Ubuntu Linux 24.04 LTS Benchmark v1.0.0**, surfacing configuration hygiene findings (e.g. duplicate UID/GID checks, disabled filesystem modules) and an overall compliance score. This runs automatically and required no additional configuration — useful as a baseline hardening check on the VM hosting the 5G core.

### 7.3 File Integrity Monitoring (FIM) on the 5G Core configuration

To tie the SOC monitoring directly to the 5G lab itself, rather than leaving it as a generic bolt-on, Wazuh's **syscheck** (FIM) module was configured to watch the Open5GS SMF configuration directory:

```xml
<syscheck>
  ...
  <directories realtime="yes">/home/open5gs/docker_open5gs/smf</directories>
</syscheck>
```
*(Path is the SMF config directory identified in Section 4.3, the same file involved in the subnet-configuration bug — monitoring it here closes the loop between the build and the security-monitoring layer.)*

After restarting the agent, a deliberate edit was made to `smf.yaml` to confirm detection. This generated a real-time FIM alert on the manager:

```
Rule: 550 — Integrity checksum changed.
File '/home/open5gs/docker_open5gs/smf/smf.yaml' modified
Mode: realtime
Changed attributes: mtime, md5, sha1, sha256
Old md5sum was: f19c559ddb9ac86c74c1e2f8bcaff23e
New md5sum is:  f26698cd38cc39d25a3d1353b170f01e
MITRE: T1565.001 - Stored Data Manipulation (Impact)
```

This confirms Wazuh correctly detects and hashes-out unauthorised changes to core network configuration in real time, and automatically maps the event to a MITRE ATT&CK technique (T1565.001, Stored Data Manipulation) without any custom rule-writing required — the mapping comes from Wazuh's default ruleset for file integrity events.

A related alert was also captured from a local authentication event on the same host:
```
Rule: 5501 — PAM: Login session opened.
MITRE: T1078 - Valid Accounts (Defense Evasion)
```

### 7.4 Custom Wazuh Alert Parser

Rather than reading raw alert JSON or relying solely on the dashboard, alerts were processed with a self-written Python script ([`wazuh_parser.py`](#), part of a broader personal automation/tooling repository) that:
- Parses each line of `/var/ossec/logs/alerts/alerts.json`
- Extracts rule level, description, agent, and any associated MITRE ATT&CK ID/tactic/technique
- Labels severity (INFO/LOW/MEDIUM/HIGH/CRITICAL) based on rule level
- Produces a consolidated report plus summary statistics (top agents, top alert types, top MITRE techniques)

Sample output against the live alert set, filtered to the MITRE-mapped, security-relevant entries (as opposed to the SCA baseline findings, which score compliance rather than mapping to adversary technique):

```
[3] PAM: Login session opened.
  Agent:  5gserver
  Rule:   5501
  MITRE:  T1078 - Valid Accounts (Defense Evasion)

[7] Integrity checksum changed.
  Agent:  5gserver
  Rule:   550
  MITRE:  T1565.001 - Stored Data Manipulation (Impact)

[7] Integrity checksum changed.
  Agent:  5gserver
  Rule:   550
  MITRE:  T1565.001 - Stored Data Manipulation (Impact)

================================================================
Total alerts: 363
================================================================
```

**Observation:** the two FIM events correspond to the same deliberate edit of `smf.yaml` (Wazuh logs both the write and the subsequent hash recomputation as separate integrity events). The bulk of the 363 total alerts remain SCA benchmark findings (Section 7.2), which — unlike the FIM and authentication events above — do not carry MITRE mappings, since SCA reports compliance posture rather than correlating to a specific adversary technique. The parser correctly distinguishes and surfaces the technique-mapped subset, which is the more actionable output for an investigation.

### 7.5 Scope and limitations

This integration is intentionally scoped as **host-level** security monitoring — process activity, configuration compliance, and file integrity on the VM running the 5G core. Wazuh does not natively parse 5G signalling protocols (NGAP/PFCP/GTP); protocol-level analysis remains the separate, packet-capture-based exercise documented in Section 6. Combined, the two give complementary coverage: Wireshark for what's happening *on the 5G signalling plane*, Wazuh for what's happening *on the infrastructure hosting it*.

## 8. Skills Demonstrated

- Linux system administration (Ubuntu, systemd, Docker/containerd internals)
- Virtualisation (Proxmox/KVM CPU passthrough configuration)
- Docker & Docker Compose (multi-container orchestration, networking, volume-mounted configuration)
- 5G Core architecture: SBA, AMF/SMF/UPF/NRF roles, NGAP, PFCP, GTP-U
- Protocol analysis with Wireshark (SCTP, NGAP, PFCP dissection)
- SOC tooling: Wazuh manager/agent deployment, Security Configuration Assessment, File Integrity Monitoring configuration
- Custom Python tooling for security log parsing and MITRE ATT&CK-mapped reporting
- Systematic debugging: isolating root cause across OS, virtualisation, application-config, and data-entry layers
- Verifying assumptions against primary/upstream sources rather than trusting first plausible explanations
