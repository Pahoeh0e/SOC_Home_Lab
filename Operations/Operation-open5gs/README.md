# Containerised 5G Standalone 

A self-directed lab project deploying a full 5G Standalone network in Docker, using Open5GS and UERANSIM, on a Proxmox-hosted Ubuntu VM. Built to develop familiarity with 5G Core architecture (SBA, NGAP, PFCP, GTP-U) and to practice systematic debugging of a multi-component containerised system.

## 1. Motivation

This project was built to gain exposure to the technologies referenced in UKTL Associate Security and Privacy Researcher vacancy that uses 5G Service-Based Architecture, NGAP/SCTP signalling, and Linux based container operations. The goal was to get a working deployment and more importantly understand why each component behaves the way it does while documenting the debugging process.

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

All network functions communicate over Docker's internal bridge network (`172.22.0.0/24`), with each NF discovering the others via the NRF where functions register and discover each other over REST/HTTP2 rather than being statically wired together as in legacy telecom architectures.

## 3. Environment

- **Host:** Proxmox VE 
- **Guest:** Ubuntu 24.04, minimal server install
- **Container runtime:** Docker CE + Compose v2 (official Docker repo)

## 4. Build Log (Issues Encountered and Resolved)

First I consulted the documentation of open5gs.
```bash
cat TROUBLESHOOTING.md | less
```
Where I found and chose to use the prepared docker images.

![prepared-images.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/precompiled-images-open5gs.png)
![ueransim-image](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/ueransim-open5gs-precompiled.png)

Also the documentation of what to edit in .env

![env-docs.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/open5gs-troubleshooting-editting-conf.png)

Then building the open5gs container

![build-set-a.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/open5gs-precompiled-instructions.png)

![sa-deploy.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/sa-deploy.yaml-build.png)

### 4.1 MongoDB crash — CPU feature (AVX) not exposed to the VM

MongoDB 5.0+ requires AVX CPU instructions. So the container failed on start:

```
WARNING: MongoDB 5.0+ requires a CPU with AVX support, and your current system does not appear to have that!
```

![mongo-avx-error.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/mongo-avx-error-cat-avx.png)

`cat /proc/cpuinfo | grep avx` on the guest returned nothing, despite the physical host CPU supporting AVX. Root cause: Proxmox's default virtual CPU type (`kvm64`) does not pass through all host CPU features.

**Fix:** Proxmox VM → Hardware → Processors → CPU type set to `host` (full passthrough), followed by a full VM shutdown/restart (CPU model is only renegotiated on cold boot, not reboot).

**Trade off:** `host` CPU type prevents live migration to a node with a different physical CPU because it exposes the exact instruction set and flags of the source physical CPU to the virtual machine, which is not a best practice for a production multi-node cluster (where a named baseline model, e.g. `x86-64-v3`, would be the standard middle ground).

![host-passthrough.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/host-passthrough-hardware.png)

### 4.2 SMF/UPF subnet misconfiguration

SMF crashed on startup:

```
[pfcp] FATAL: ogs_pfcp_subnet_add: Assertion `rv == OGS_OK' failed
```

![crash-.env.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-09-11%2020-14-15.png)

![subnet-error.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-09-11%2019-47-18.png)

Root cause: `.env` defined `UE_IPV4_INTERNET` using a specific host address in CIDR form (`10.0.0.105/12`) rather than a proper network address, and the range also overlapped the VM's real LAN subnet creating routing ambiguity even once parsing succeeded.

**Fix:** Verified against the project's official `.env.example` and set the UE address pools to a distinct, non-overlapping private range:
```
UE_IPV4_INTERNET=10.45.0.0/24
UE_IPV4_IMS=10.46.0.0/24
```

**Takeaway:** verified the fix against the upstream repository rather than trusting a plausible-sounding but incorrect first attempt. My assumption about variable naming was initially wrong and was corrected by checking the source.

### 4.3 UE authentication failure (SQN synchronisation)

UE registration failed:
```
[nas] [error] Initial Registration failed [FIVEG_SERVICES_NOT_ALLOWED]
```
then, after provisioning a subscriber:
```
[nas] [debug] Sending Authentication Failure due to SQN out of range
```
![.env-11111111-number](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/111111-32-subscriber-open5gs.png)

First failure: no subscriber existed for the UE's IMSI in the core's database. Second failure: the subscriber's security fields (K / Operator Key) were mistyped when hand-entering into the WebUI (no clipboard access to the headless VM), a value intended for the OP field was mistakenly entered into the K field, and vice versa, corrupting the AKA authentication vectors.

**Fix:** Deleted and correctly re-created the subscriber, carefully matching each field to its `.env` defined value, and verified key length (32 hex characters) via `wc -c` before re-entry.


**Takeaway:** SQN failures during AKA authentication are not always literal SQN desync they can also surface as the resulting symptom of a K/OP key mismatch, since AKA's automatic resync mechanism itself depends on those same keys being correct.

![success-subscriber.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/subcriber-correct.png)

## 5. Result (Working End-to-End Data Path)

Following the fixes above, the UE:

![successful-start-containers.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/all-15-containers-open5gs.png)
![deploy-success-logs.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/sa-deploy-logs-success-open5gs.png)

1. Completed NAS registration (`Registration accept received`)
2. Established a PDU session (`PDU Session establishment is successful PSI[1]`)
3. Received a tunnel IP from the configured pool (`TUN interface[uesimtun0, 10.45.0.2] is up`)
4. Successfully routed real traffic through the core to the internet:


![docker-exec.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/docker-exec-ping-success.png)
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
![wireshark-first-open5gs.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-09-12%2012-29-31.png)

### 6.1 Registration sequence observed

![wireshark-long-ngap-pdu.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/InitialEUMessage-longshot-wireshark.png)

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

![longshot-wireshark.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/InitialEUMessage-long-wireshark.png)
![longshot-wireshark-2.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/InitialEUMessage-long-wireshark-2.png)
![![longshot-wireshark-2.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/InitialEUMessage-long-wireshark-3.png)


**PFCP Session Establishment Request** (packet 3223) — this is the message SMF sends to instruct UPF to set up a new data session. Decoding it showed:

- Subscriber identity fields — `IMSI 001011234567895`, `IMEI`, `MCC/MNC (001/01)` — carried in the PFCP User ID Information Element. This confirms SMF isn't just telling UPF what to do with the traffic, it's also telling UPF whose traffic this is. Checking this against 3GPP TS 29.244 spec confirmed this is a legitimate field though the spec marks it as optional and controlled by a defined policy so that UP function must be in a trusted environment before containing `User ID`. Open5GS enables it by default.
- `APN/DNN: internet`, `S-NSSAI: SST 01, SD ffffff` — confirms the session's network slice and access point identity travel with it, so UPF knows not just who the subscriber is but what kind of session and slice they're connecting through.
- `Create PDR / FAR / URR / QER / BAR`— the actual forwarding rules: how UPF should detect the UE's packets (PDR), where to forward them (FAR), how to measure usage (URR), how to police/rate-limit (QER), and how to buffer them if needed (BAR).
- `F-SEID` — the unique session ID binding this specific PFCP session between SMF and UPF, so future messages about this session can reference it unambiguously.

Significance: this confirmed, at the packet level, that subscriber and slice context go through through the core's internal signalling (SMF→UPF) not only at the RAN-facing edge where the UE first presents its identity to the AMF. Identity and context don't just enter the network once at the entrance, they are actively carried between internal network functions as the session is built.


### 6.3 Traffic identified and excluded as non-signalling noise

![PFCP-heartbeat.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-09-12%2012-29-31.png)

Periodic `PFCP Heartbeat Request/Response` (SMF↔UPF) and `SCTP HEARTBEAT/HEARTBEAT_ACK` (gNB↔AMF) were identified as routine liveness checks between already-associated network functions, and excluded from the analysis as they are not part of the registration procedure itself.

## 7. SOC Tooling Integration (Wazuh + Custom Log Parser)

To extend the project beyond protocol analysis and into a security monitoring context, a Wazuh agent was deployed and pointed at the lab, with a custom [Python analyser](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Automation/Log-parser.md) used to process the resulting alert stream.

### 7.1 Deployment

- **Wazuh agent** installed on the `5gserver` VM (the Open5GS host) via the official DEB repository, enrolled against a separate Wazuh manager instance.

- **Debugging note:** the initial `apt-get install wazuh-agent` failed with `Unable to locate package`, because the Wazuh APT repository had not actually been added yet, a piping mistake (`sudo` applied to the wrong side of `echo | tee`) meant the repo file was never written to `/etc/apt/sources.list.d/`. Re-running the `tee` step with `sudo` correctly applied resolved it. `sudo apt-get update` then correctly listed the Wazuh repository and the install succeeded.
- 
- Confirmed connectivity via the agent's own log (`/var/ossec/logs/ossec.log`) and cross-checked in the manager's **Discover** dashboard, which showed the agent (`5gserver`, agent ID `009`) actively reporting.

### 7.2 Security Configuration Assessment (SCA)

Out of the box, Wazuh's SCA module benchmarked the host against the **CIS Ubuntu Linux 24.04 LTS Benchmark v1.0.0**, surfacing configuration hygiene findings (e.g. duplicate UID/GID checks, disabled filesystem modules) and a compliance score. This runs automatically and required no additional configuration, which is useful as a baseline hardening check.

![SCA-benchmark-dashboard](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/SCA-wazuh-dashboard-open5gs.png)

### 7.3 File Integrity Monitoring (FIM) on the 5G Core configuration

To tie the SOC monitoring directly to the 5G lab itself Wazuh's **syscheck** (FIM) module was configured to watch the Open5GS SMF configuration directory:

![direcoties-syscheck.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-09-12%2017-13-05.png)
```xml
<syscheck>
  ...
  <directories realtime="yes">/home/open5gs/docker_open5gs/smf</directories>
</syscheck>
```
*(Path is the SMF config directory identified in Section 4.3, the same file involved in the subnet-configuration bug. Monitoring it here closes the loop between the build and the security-monitoring layer.)*

After restarting the agent, a deliberate edit was made to `smf.yaml` to confirm detection. This generated a real-time FIM alert on the manager:

![wazuh-open5gs-fim](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/open5gs-wazuh-fim.png)

```
Rule: 550 — Integrity checksum changed.
File '/home/open5gs/docker_open5gs/smf/smf.yaml' modified
Mode: realtime
Changed attributes: mtime, md5, sha1, sha256
Old md5sum was: f19c559ddb9ac86c74c1e2f8bcaff23e
New md5sum is:  f26698cd38cc39d25a3d1353b170f01e
MITRE: T1565.001 - Stored Data Manipulation (Impact)
```

Wazuh correctly detects and hashes-out unauthorised changes to core network configuration in real time, and automatically maps the event to a MITRE ATT&CK technique (T1565.001, Stored Data Manipulation) without any custom rule-writing required. The mapping comes from Wazuh's default ruleset for file integrity events.

### 7.4 Custom Wazuh Alert Parser

Rather than reading raw alert JSON or relying solely on the dashboard, alerts were processed with a self-written Python script ([`wazuh_parser.py`](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Automation/Log-parser.md)), part of a broader personal automation/tooling repository) that:
- Parses each line of `/var/ossec/logs/alerts/alerts.json`
- Extracts rule level, description, agent, and any associated MITRE ATT&CK ID/tactic/technique
- Labels severity (INFO/LOW/MEDIUM/HIGH/CRITICAL) based on rule level
- Produces a consolidated report plus summary statistics (top agents, top alert types, top MITRE techniques)

Sample output against the live alert set, filtered to the MITRE-mapped, security-relevant entries (as opposed to the SCA baseline findings, which score compliance rather than mapping to adversary technique):

![log-parser-command](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/log-parser-wazuh-open5gs-fim-2.png)
![log-parser-wazuh](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/open5gs-wazuh-log-parser-fim.png)


**Observation:** the two FIM events correspond to the same deliberate edit of `smf.yaml` (Wazuh logs both the write and the subsequent hash recomputation as separate integrity events). The bulk of the 363 total alerts remain SCA benchmark findings (Section 7.2), which unlike the FIM and authentication events above do not carry MITRE mappings, since SCA reports compliance posture rather than correlating to a specific adversary technique. The parser correctly distinguishes and surfaces the technique-mapped subset.

### 7.5 Scope and limitations

This integration is intentionally scoped as **host-level** security monitoring, process activity and configuration compliance on the VM running the 5G core. Wazuh does not natively parse 5G signalling protocols (NGAP/PFCP/GTP). Wireshark shows what's happening on the 5G signalling environment and Wazuh shows what's happening on the infrastructure hosting it.


## 8. SBI Fuzzing Test (py5sig)

To extend the project from deployment and passive protocol analysis into active security testing, I evaluated [`py5sig`](https://github.com/ANSSI-FR/py5sig), an open-source SBA/SBI fuzzer published by ANSSI (the French national cybersecurity agency), against the deployed core's internal Service-Based Interfaces.

### 8.1 Motivation

The NRF/AMF/SMF/etc. communicate over `nnrf-nfm`, `nnrf-disc`, and `nsmf-pdusession` REST-style APIs. The goal here was to actively test how the core's SBI implementations handle malformed or attacker input to extend the protocol analysis in Section 6 to correlate with a "vulnerability researcher" testing process.

### 8.2 Setup and Connectivity Debugging

py5sig was installed in a Python virtual environment on the host VM (outside the Docker network) and pointed at the NRF's exposed SBI port. Establishing basic connectivity required working through several protocol-level misdiagnoses in sequence:

| Attempt | Result | Diagnosis |
|---|---|---|
| `curl http://<nrf-ip>:7777/nnrf-nfm/v1/nf-instances` | `Received HTTP/0.9 when not allowed` | Looked like a TLS mismatch at first |
| `curl -k https://<nrf-ip>:7777/...` | `OpenSSL: wrong version number` | Confirmed it was *not* TLS either |
| `curl --http2-prior-knowledge http://<nrf-ip>:7777/...` | Clean `HTTP/2 400`, JSON error body | Correct protocol: Open5GS's SBI runs **HTTP/2 cleartext (h2c)**, which neither plain HTTP/1.1 nor TLS negotiation matched |



The `400` response itself (`"title":"Invalid API name"`) was informative after finding out that `nnrf-nfm` only supports operations on a specific `nfInstanceId` (register/update/deregister), not a bulk list. The correct discovery call uses the separate **`Nnrf_NFDiscovery`** service:

```bash
curl --http2-prior-knowledge \
  "http://<nrf-ip>:7777/nnrf-disc/v1/nf-instances?target-nf-type=AMF&requester-nf-type=SMF"
```
![curl-py5sig](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/successful-curl-py5sig-amf-smf.png)
![full-list-nf-instances-1](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/py5sig-full-list-nf-instances-1.png)

This returned the full registered NF topology (AMF, SMF, UDM, UDR, AUSF, PCF, BSF, NSSF, SCP), confirming both the correct transport (h2c) and the correct API surface before py5sig itself was tested against the same target.

**Takeaway:** three consecutive failures (HTTP/0.9, TLS version mismatch, then a 400) each looked like a different category of problem, but methodically changing one variable at a time (transport, then encryption, then API path) isolated the actual cause rather than guessing.

### 8.3 Bug Found: Malformed YAML in py5sig's Bundled Specs

Running py5sig's own discovery mode succeeded and returned the same NF topology as the manual `curl` check. However, invoking `--fuzzing` initially crashed with:

ruamel.yaml.scanner.ScannerError: while scanning for the next token
found character '\t' that cannot start any token
in "<unicode string>", line 1081, column 18

![py5sig-bus-output](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-09-20%2015-16-20.png)

A clean reinstall (fresh venv, fresh `pip install .`) reproduced the identical crash, ruling out a local environment issue. 

I located the fault in two of its bundled 3GPP OpenAPI spec files by using:

```
find ~/py5sig-venv -iname "*.yaml" | xargs grep -lP '\t' 2>/dev/null
```

![bug-yaml-files](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/py5sig-bug-grep-rlP.png)

Both `specs/TS29122_MonitoringEvent.yaml` and `specs/TS29512_Npcf_SMPolicyControl.yaml` contained literal tab characters, which `ruamel.yaml` (YAML forbids tabs for indentation) refused to parse. This is a genuine upstream bug, not a configuration error by me. 

This was fixed with:

```bash
sed -i 's/\t/  /g' <path>/TS29122_MonitoringEvent.yaml
sed -i 's/\t/  /g' <path>/TS29512_Npcf_SMPolicyControl.yaml
```
![bug-fixed-py5sig]((https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/py5sig-bug-found-fixed.png)

**Takeaway:** running from a deliberately clean reinstall before debugging further is worth doing before assuming a self-inflicted cause.

### 8.4 Fuzzing Run and Observations

With the spec files patched, `py5sig --fuzzing` was run against the AMF→SMF SBI pairing for about 6 minutes, with NRF logs tailed live in a separate SSH session (`docker compose -f sa-deploy.yaml logs -f nrf`) and saved to file for later review.

![fuzzing-command](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/py5sig-fuzzing-command.png)

**SQL payload:** 

A single quote breaking out of an assumed string literal, followed by an always-true boolean condition (OR 1=1) or a wildcard match (LIKE '%'), designed to manipulate a backend database query if the input were passed unsanitized into SQL. Sent against the SMF's POST /nsmf-pdusession/v1/sm-contexts endpoint, targeting the subscriber identity fields (supi, pei, unauthenticatedSupi). 
```json
{
  "pei": "' or username like '%",
  "supi": "' or username like '%",
  "unauthenticatedSupi": "' or username like '%",
  "n1SmMsg": { "contentId": "n1SmMsg" }
}
```
![fuzzing-sql-2](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/py5sig-fuzzer-sql-username.png)
![fuzzing-sql-1](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/fuzzing-sql-1.png)

**Buffer Overflow / Oversized Input Attack:** 

An abnormally long string (96 characters of repeated `A`) injected into a field expecting a short, fixed value (an NF type such as `AMF` or `SMF`). Long runs of a single repeated character are a classic technique for probing fixed-size buffer boundaries and identifying crash points or memory corruption. Sent as the `target-nf-type` query parameter against the NRF's `GET /nnrf-disc/v1/nf-instances` discovery endpoint:
```
target-nf-type=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
&requester-nf-type=SMF
```

![fuzzing-oversized-input](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/py5sig-oversized-input.png)

**Result:** clean `400`/`4xx` rejection at the SBI/HTTP layer — no crash observed here. This same underlying vulnerability class (unbounded copy into a fixed-size buffer) was later confirmed to be genuinely exploitable elsewhere in the codebase, at the PFCP configuration-parsing layer rather than the SBI/HTTP layer — see Section 10.


**NRF logs during the run** showed a consistent pattern of malformed discovery requests (invalid combined `scope=nnrf-disc nnrf-nfm` parameters, non-existent `nfInstanceId` values) being rejected cleanly at the parser level:

[sbi] ERROR: JSON parse error [nfInstanceId=...&targetNfType=NRF&scope=nnrf-disc nnrf-nfm&grant_type=client_credentials]
[sbi] ERROR: parse_content() failed
[sbi] ERROR: cannot parse HTTP message


**Post-run verification:** container health (`docker compose ps`) showed all services remained `Up` throughout, with no restarts. A before/after `Nnrf_NFDiscovery` capture, diffed with `diff`, showed **zero differences** in the registered NF topology. Thus, confirming the fuzzing run caused no observable state corruption in addition to causing no crash.

## 9. Volume-Based Degradation Testing (CVE-2024-53828 / CWE-228)

### 9.1 Motivation

In April 2026, Ericsson published a security bulletin for [CVE-2024-53828](https://app.opencve.io/cve/CVE-2024-53828), affecting Packet Core Controller (PCC) versions prior to 1.38, credited to a joint disclosure by NCSC and [UKTL](https://www.ericsson.com/en/about-us/security/psirt/cve-2024-53828). The vulnerability (CWE-228: Improper Handling of Syntactically Invalid Structure) allows an attacker sending a large volume of specially crafted messages to cause service degradation (CVSS 5.3, AV:A/AC:H/PR:N/UI:N/S:U/C:N/I:N/A:H).

PCC itself is closed-source commercial equipment with no public source, binary, or lab access available, so direct reproduction isn't possible. Instead, this section tests the **same vulnerability class** CWE-228, service degradation via malformed messages at volume against the NRF's `Nnrf_NFDiscovery` SBI interface in this lab's own Open5GS deployment, to see whether the same failure mode is present here.

### 9.2 Methodology

Using `h2load` (nghttp2's benchmarking tool, chosen because Open5GS's SBI server itself runs on `nghttp2_server()`, confirmed in the NRF's own startup logs), two comparable load tests were run against the NRF's discovery endpoint, differing only in the validity of the `target-nf-type` query parameter:

**Test A — malformed input** (oversized, syntactically invalid `target-nf-type`, the same payload used in Section 8.4):
```bash
h2load -n 5000 -c 50 -m 10 --duration=15 \
  "http://172.22.0.12:7777/nnrf-disc/v1/nf-instances?target-nf-type=AAAA...[96 chars]...&requester-nf-type=SMF"
```

**Test B — control, well-formed input**:
```bash
h2load -n 5000 -c 50 -m 10 --duration=15 \
  "http://172.22.0.12:7777/nnrf-disc/v1/nf-instances?target-nf-type=AMF&requester-nf-type=SMF"
```

Both tests used identical concurrency (`-c 50`), stream multiplexing (`-m 10`), and duration (`--duration=15`), so the only variable between them is request validity. `docker stats nrf amf smf` was run continuously (not `--no-stream`) throughout each test, in a separate SSH session, to observe live CPU/memory impact per-container rather than relying on `h2load`'s client-side timing alone.

![h2load-malformed](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/h2load-malformed-run.png)
![h2load-wellformed](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/h2load-wellformed-run.png)
![docker-stats-malformed](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/docker-stats-during-malformed-flood.png)
![docker-stats-wellformed](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/docker-stats-during-wellformed-flood.png)

### 9.3 Results

| Metric | Malformed request | Well-formed request |
|---|---|---|
| Status codes | 100% `4xx` (rejected) | 100% `2xx` (succeeded) |
| Mean time/request | 147.20ms | 294.06ms |
| Max time/request | 357.21ms | 986.58ms |
| Throughput | 3327.53 req/s | 1648.93 req/s |
| Peak NRF CPU (docker stats) | ~55% | 71.33% |
| AMF/SMF CPU impact | Negligible (<1%) | Negligible (<1%) |
| Errors / timeouts / 5xx | 0 / 0 / 0 | 0 / 0 / 0 |

Results were consistent across repeated runs of both tests.

### 9.4 Interpretation

The initial hypothesis that malformed requests would degrade NRF performance disproportionately, mirroring the Ericsson PCC pattern was **not confirmed**; the result was the opposite. Well-formed requests consumed more CPU (71.33% vs ~55%) and had roughly double the latency (294ms vs 147ms mean) than malformed requests.

This has a straightforward explanation once traced through: a malformed `target-nf-type` value is caught and rejected at the input-validation stage before any further processing occurs. A valid discovery request, by contrast, requires the NRF to look up the full registered NF topology (in this lab: AMF, SMF, UDM, UDR, AUSF, PCF, BSF, NSSF, SCP see Section 8.2's discovery output) and serialise it into a response more computational work per request.

**Conclusion:** unlike the failure mode described in CVE-2024-53828, this NRF's discovery-endpoint input validation does not carry disproportionate cost rejecting invalid input is cheaper than serving a legitimate request, not more expensive. No evidence of CWE-228-class degradation was found on this specific endpoint under this test's volume/duration. Neither test produced a `5xx` response, a container crash, or unrecovered memory growth; NRF CPU usage returned to baseline (<1%) after each test concluded.

### 9.5 Limitations

- This tested one endpoint (`Nnrf_NFDiscovery`) with one malformation strategy (an oversized string in a single query parameter). Other SBI endpoints, other malformation strategies, or sustained/repeated load over longer windows could produce different results.
- `docker stats`' ~1-second polling interval limits precision on very short bursts; `--duration=15` was chosen specifically to give a wide-enough observation window.
- The Ericsson PCC vulnerability's exact mechanism is not public; this test used the CWE classification and the "volume of malformed messages" description as the closest available specification to test against, not a confirmed reproduction of the same code path.

## 10. Static and Dynamic Analysis of CVE-2025-44951 / CVE-2025-44952 (PFCP Buffer Overflow)

### 10.1 Motivation

To cover ground the fuzzing work above doesn't reach memory corruption at the binary level, rather than input validation at the API level this section reproduces a documented, disclosed Open5GS vulnerability: CVE-2025-44951 and CVE-2025-44952, buffer overflows in `ogs_pfcp_dev_add` and `ogs_pfcp_subnet_add` (`lib/pfcp/context.c`), discovered by Leonardo Sagratella and Lorenzo Cannella via static analysis with Flawfinder, affecting Open5GS SMF/UPF v2.7.2 and earlier ([open5gs/open5gs#3775](https://github.com/open5gs/open5gs/issues/3775)).

### 10.2 Independent Static Discovery

The vulnerable version was built from source with debug symbols retained, to allow direct correlation between source, disassembly, and struct layout:

```bash
git clone https://github.com/open5gs/open5gs.git open5gs-cve
cd open5gs-cve
git checkout v2.7.2
meson setup build --prefix=$(pwd)/install --buildtype=debug
ninja -C build && ninja -C build install
```

Running Flawfinder independently against the checked-out source reproduced the **same two findings**, at the same line numbers, as the original disclosure:

```bash
flawfinder lib/ | grep -i "strcpy"
```

lib/pfcp/context.c:2112: [4] (buffer) strcpy: ... (CWE-120)
lib/pfcp/context.c:2218: [4] (buffer) strcpy: ... (CWE-120)


![flawfinder-independent](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/flawfinder-independent-confirmation.png)

Manual inspection of both lines confirmed unguarded `strcpy` calls with no preceding `strlen`/length check:
```c
strcpy(dev->ifname, ifname);      // context.c:2112
strcpy(subnet->dnn, dnn);         // context.c:2218
```

### 10.3 Binary Confirmation (Ghidra)

The compiled shared library containing this code (`libogspfcp.so.2`, located via `ldd` against the built `open5gs-smfd` binary) was imported into Ghidra and analyzed with debug symbols intact.

Locating `ogs_pfcp_dev_add` in the Function List and opening its decompiled view confirmed the same unguarded call is present in the **compiled binary**, not just the source:

```c
memset(dev,0,0x48);
strcpy(dev->ifname,ifname);
```

![ghidra-decompiled-strcpy](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/ghidra-strcpy-decompiled.png)

No length check, `strlen`, or bounds comparison appears anywhere between the function's `ifname` parameter and this call — the only checks present in the function are null-pointer assertions, not size validation.

### 10.4 Struct Layout — Confirming the Overflow Target

Ghidra's Structure Editor, opened against the `ogs_pfcp_dev_s` type (resolved from DWARF debug info), shows the exact field layout:

| Offset | Length | Type | Name |
|---|---|---|---|
| 0x0 | 0x10 | `ogs_lnode_t` | `lnode` |
| 0x10 | 0x20 | `char[32]` | `ifname` |
| 0x30 | 0x4 | `ogs_socket_t` | `fd` |
| 0x38 | 0x8 | `ogs_poll_t*` | `poll` |
| 0x40 | 0x1 | `_Bool` | `is_tap` |
| 0x41 | 0x6 | `uint8_t[6]` | `mac_addr` |

![ghidra-struct-layout](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/ghidra-struct-editor-ogs-pfcp-dev-s.png)

This mathematically confirms the mechanism: `ifname` occupies exactly 32 bytes starting at offset `0x10`, and `fd` begins immediately at offset `0x30` directly adjacent. Any string longer than 32 bytes copied into `ifname` via the unbounded `strcpy` overflows directly into `fd`, and (given a sufficiently long input) continues into `poll`, an 8-byte pointer field — a materially more serious corruption target than an integer, since pointer corruption has a higher potential severity ceiling. This matches the original disclosure's empirical finding, which observed `dev->fd` change from its initialized value to a garbage value (`1853191283`) after the overflow.

### 10.5 Dynamic Confirmation (gdb) — [Planned/In Progress]

To close the loop between static analysis and actual runtime behaviour, the following live confirmation is planned:

1. A minimal `smf.yaml` config using the disclosure's documented trigger values (`dev: ogstunogstunogstunogstunogstunogstun` 38 characters; `dnn:` a 368-character string) will be used to launch `open5gs-smfd` under gdb.
2. Breakpoints will be set at `context.c:2112` and `context.c:2218` the exact vulnerable lines identified in Sections 10.2–10.3.
3. `dev->fd` and `subnet->num_of_range` will be printed immediately before and after stepping over each `strcpy` call, to directly observe the corruption occurring in memory, rather than relying solely on the original disclosure's own printf-instrumented evidence.
4. Results will be correlated explicitly against the Section 10.4 struct layout: the runtime-observed corrupted field should match what the offset table predicts.

*(This subsection to be completed and updated with results.)*

### 10.6 Summary

This reproduction combined three levels of evidence for the same vulnerability: independent static rediscovery (Flawfinder), binary-level confirmation of the vulnerable code path in the actual compiled shared library (Ghidra decompilation), and a mathematical explanation of the exact corruption mechanism via struct layout analysis (Ghidra Structure Editor) — with live runtime confirmation (gdb) to follow. Unlike the SBI fuzzing in Sections 8–9, which produced consistently negative (no-vulnerability-found) results, this reproduction confirms a genuine, disclosed memory-safety vulnerability exists in this version of the codebase, and demonstrates the ability to trace a CVE from public disclosure through source, compiled binary, and runtime behaviour.

## 11. Skills Demonstrated
- Linux system administration (Ubuntu, systemd, Docker/containerd internals)
- Virtualisation (Proxmox/KVM CPU passthrough configuration)
- Docker & Docker Compose (multi-container orchestration, networking, volume-mounted configuration)
- 5G Core architecture: SBA, AMF/SMF/UPF/NRF roles, NGAP, PFCP, GTP-U
- Protocol analysis with Wireshark (SCTP, NGAP, PFCP dissection)
- SOC tooling: Wazuh manager/agent deployment, Security Configuration Assessment, File Integrity Monitoring configuration
- Custom Python tooling for security log parsing and MITRE ATT&CK-mapped reporting
- Systematic debugging: isolating root cause across OS, virtualisation, application-config, and data-entry layers
- Verifying assumptions against primary/upstream sources rather than trusting first plausible explanations
- Fuzz testing methodology: SBI/HTTP2 mutation fuzzing, oracle design (crash detection, topology-diff verification), and honestly scoping findings against limitations
- HTTP/2 cleartext (h2c) protocol debugging, distinguishing transport-layer, TLS-layer, and API-layer failure modes
- Identifying, isolating, and working around a bug in third-party open-source security tooling
- Self-correcting a flawed verification step (invalid baseline diff) before drawing conclusions from it
