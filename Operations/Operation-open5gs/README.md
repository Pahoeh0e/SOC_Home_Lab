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

**Trade off:** `host` CPU type prevents live migration to a node with a different physical CPU — acceptable for a single-node lab, not for a production multi-node cluster (where a named baseline model, e.g. `x86-64-v3`, would be the standard middle ground).

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

- **Debugging note:** the initial `apt-get install wazuh-agent` failed with `Unable to locate package`, because the Wazuh APT repository had not actually been added yet — a piping mistake (`sudo` applied to the wrong side of an `echo | tee` pipeline) meant the repo file was never written to `/etc/apt/sources.list.d/`. Re-running the `tee` step with `sudo` correctly applied resolved it; `sudo apt-get update` then correctly listed the Wazuh repository and the install succeeded. Kept as an example of a silent, non-obvious failure mode (the shell gave no error, it just didn't do what was intended).
- Confirmed connectivity via the agent's own log (`/var/ossec/logs/ossec.log`) and cross-checked in the manager's **Discover** dashboard, which showed the agent (`5gserver`, agent ID `009`) actively reporting.

### 7.2 Security Configuration Assessment (SCA)

Out of the box, Wazuh's SCA module benchmarked the host against the **CIS Ubuntu Linux 24.04 LTS Benchmark v1.0.0**, surfacing configuration hygiene findings (e.g. duplicate UID/GID checks, disabled filesystem modules) and an overall compliance score. This runs automatically and required no additional configuration — useful as a baseline hardening check on the VM hosting the 5G core.

![SCA-benchmark-dashboard](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/SCA-wazuh-dashboard-open5gs.png)

### 7.3 File Integrity Monitoring (FIM) on the 5G Core configuration

To tie the SOC monitoring directly to the 5G lab itself, rather than leaving it as a generic bolt-on, Wazuh's **syscheck** (FIM) module was configured to watch the Open5GS SMF configuration directory:

![direcoties-syscheck.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-09-12%2017-13-05.png)
```xml
<syscheck>
  ...
  <directories realtime="yes">/home/open5gs/docker_open5gs/smf</directories>
</syscheck>
```
*(Path is the SMF config directory identified in Section 4.3, the same file involved in the subnet-configuration bug — monitoring it here closes the loop between the build and the security-monitoring layer.)*

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

This confirms Wazuh correctly detects and hashes-out unauthorised changes to core network configuration in real time, and automatically maps the event to a MITRE ATT&CK technique (T1565.001, Stored Data Manipulation) without any custom rule-writing required — the mapping comes from Wazuh's default ruleset for file integrity events.

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

This integration is intentionally scoped as **host-level** security monitoring, process activity and configuration compliance on the VM running the 5G core. Wazuh does not natively parse 5G signalling protocols (NGAP/PFCP/GTP); protocol-level analysis remains the separate, packet-capture-based exercise documented in Section 6. Combined, the two give complementary coverage where Wireshark shows what's happening on the 5G signalling environment and Wazuh shows what's happening on the infrastructure hosting it.


## 8. SBI Fuzzing Test (py5sig)

To extend the project from deployment and passive protocol analysis into active security testing, I evaluated [`py5sig`](https://github.com/ANSSI-FR/py5sig), an open-source SBA/SBI fuzzer published by ANSSI (the French national cybersecurity agency), against the deployed core's internal HTTP/2-based Service-Based Interfaces.

### 8.1 Motivation

The NRF/AMF/SMF/etc. communicate over `nnrf-nfm`, `nnrf-disc`, and `nsmf-pdusession` REST-style APIs. Rather than only observing this traffic passively (as in Section 6), the goal here was to actively test how the core's SBI implementations handle malformed or adversarial input — a natural extension of the protocol analysis already done, and a closer match to a "vulnerability researcher" testing methodology than a purely deployment-and-observe exercise.

### 8.2 Setup and Connectivity Debugging

py5sig was installed in a Python virtual environment on the host VM (outside the Docker network) and pointed at the NRF's exposed SBI port. Establishing basic connectivity required working through several protocol-level misdiagnoses in sequence:

| Attempt | Result | Diagnosis |
|---|---|---|
| `curl http://<nrf-ip>:7777/nnrf-nfm/v1/nf-instances` | `Received HTTP/0.9 when not allowed` | Looked like a TLS mismatch at first |
| `curl -k https://<nrf-ip>:7777/...` | `OpenSSL: wrong version number` | Confirmed it was *not* TLS either |
| `curl --http2-prior-knowledge http://<nrf-ip>:7777/...` | Clean `HTTP/2 400`, JSON error body | Correct protocol: Open5GS's SBI runs **HTTP/2 cleartext (h2c)**, which neither plain HTTP/1.1 nor TLS negotiation matched |

The `400` response itself (`"title":"Invalid API name"`) was also informative: `nnrf-nfm` only supports operations on a specific `nfInstanceId` (register/update/deregister), not a bulk list. The correct discovery call uses the separate **`Nnrf_NFDiscovery`** service:

```bash
curl --http2-prior-knowledge \
  "http://<nrf-ip>:7777/nnrf-disc/v1/nf-instances?target-nf-type=AMF&requester-nf-type=SMF"
```

This returned the full registered NF topology (AMF, SMF, UDM, UDR, AUSF, PCF, BSF, NSSF, SCP), confirming both the correct transport (h2c) and the correct API surface before py5sig itself was tested against the same target.

**Takeaway:** three consecutive failures (HTTP/0.9, TLS version mismatch, then a 400) each looked like a different category of problem, but methodically changing one variable at a time (transport, then encryption, then API path) isolated the actual cause rather than guessing.

### 8.3 Bug Found: Malformed YAML in py5sig's Bundled Specs

Running py5sig's own discovery mode succeeded and returned the same NF topology as the manual `curl` check. However, invoking `--fuzzing` initially crashed with:

ruamel.yaml.scanner.ScannerError: while scanning for the next token
found character '\t' that cannot start any token
in "<unicode string>", line 1081, column 18


A clean reinstall (fresh venv, fresh `pip install .`) reproduced the identical crash, ruling out a local environment issue. `grep -rlP '\t'` against py5sig's installed package located the fault in two of its bundled 3GPP OpenAPI spec files:

- `specs/TS29122_MonitoringEvent.yaml`
- `specs/TS29512_Npcf_SMPolicyControl.yaml`

Both contained literal tab characters, which `ruamel.yaml` (YAML forbids tabs for indentation) refused to parse. This is a genuine upstream bug in the shipped tool, not a configuration error on my part. Fixed locally with:

```bash
sed -i 's/\t/  /g' <path>/TS29122_MonitoringEvent.yaml
sed -i 's/\t/  /g' <path>/TS29512_Npcf_SMPolicyControl.yaml
```

**Takeaway:** running from a deliberately clean reinstall before debugging further is what distinguished "bug in the tool" from "mistake in my setup" — worth doing before assuming a self-inflicted cause, especially after an accidental double-install earlier in the session.

### 8.4 Fuzzing Run and Observations

With the spec files patched, `py5sig --fuzzing` was run against the AMF→SMF SBI pairing for approximately 6 minutes, with NRF logs tailed live in a separate SSH session (`docker compose -f sa-deploy.yaml logs -f nrf`) and saved to file for later review.

**Example payload observed** (SQL-injection-style strings injected into subscriber identity fields on `POST /nsmf-pdusession/v1/sm-contexts`):

```json
{
  "pei": "' or username like '%",
  "supi": "' or username like '%",
  "unauthenticatedSupi": "' or username like '%",
  "n1SmMsg": { "contentId": "n1SmMsg" }
}
```

**Result:** clean `400 Bad Request` — no injection behaviour, no crash, no unhandled exception.

**NRF logs during the run** showed a consistent pattern of malformed discovery requests (invalid combined `scope=nnrf-disc nnrf-nfm` parameters, non-existent `nfInstanceId` values) being rejected cleanly at the parser level:

[sbi] ERROR: JSON parse error [nfInstanceId=...&targetNfType=NRF&scope=nnrf-disc nnrf-nfm&grant_type=client_credentials]
[sbi] ERROR: parse_content() failed
[sbi] ERROR: cannot parse HTTP message


**Post-run verification:** container health (`docker compose ps`) showed all services remained `Up` throughout, with no restarts. A before/after `Nnrf_NFDiscovery` capture, diffed with `diff`, showed **zero differences** in the registered NF topology — confirming the fuzzing run caused no observable state corruption in addition to causing no crash.

**Methodology note:** my first before/after diff attempt returned a `0a1,604` diff (i.e. "add all 604 lines") — not because fuzzing changed 604 lines, but because my baseline capture file was empty due to an earlier failed command. I caught this by checking file line counts (`wc -l`) rather than trusting the diff output at face value, redid the baseline capture, and confirmed a genuine zero-diff result. Kept here as a reminder that a "no differences" result is only meaningful once the comparison itself is verified to be valid.

### 8.5 Outcome and Limitations

**Findings:**
- No crash or state corruption observed under mutation-based SBI fuzzing of the AMF/SMF/NRF pairing over this test window
- SQL-injection-style payloads in subscriber identity fields were correctly rejected
- Malformed SBI query parameters were correctly rejected at the NRF's parser level
- One real upstream bug identified and worked around in py5sig's shipped OpenAPI spec files

**Limitations, stated explicitly:**
- This was a short (~6 minute), single-session run against one NF pairing (AMF↔SMF) — not a long-running or coverage-guided campaign, and a longer run or different NF pairings could surface different results
- py5sig's mutations are not coverage-guided (no binary instrumentation), so a negative result here indicates "no bug found within this mutation strategy and time window," not "no bugs exist"
- Testing was limited to the SBI/HTTP2 layer; the N2/NGAP interface (RAN-to-AMF) was not covered by this tool and remains a separate, harder fuzzing target for future work (see `5Greplay`/stateful-NGAP-fuzzing research)

## 9. Skills Demonstrated

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
