## Operation Auto-Sentinel]: Credential Harvesting & Domain Secrets Extraction

A simulated Active Directory attack chain demonstrating detection via Microsoft Sentinel and KQL, mapped to MITRE ATT&CK. Built in a domain-joined lab to replicate a realistic AD attack path from an unauthenticated foothold through password spraying, local credential dumping, Kerberoasting, and domain secrets replication.

## Threat Scenario

| Phase | Technique | MITRE ID |
|-------|-----------|----------|
| Credential Access | Password Spraying | T1110.003 |
| Credential Access | SAM Database Dump | T1003.002 |
| Discovery | SMB User/Share Enumeration (incl. Guest) | T1087.002 |
| Credential Access | Kerberoasting (RC4 TGS Extraction) | T1558.003 |
| Credential Access | Domain Secrets Replication (DCSync-style) | T1003.006 |
| Lateral Movement | Pass-the-Hash | T1550.002 |
| Lateral Movement | Attempted Remote Execution (PsExec) | T1021.002 |

### Detection Coverage

This repository implements detection logic across the credential access and lateral movement phases using:

- **Windows Security Auditing** (Event IDs 4625, 4769, 4662, 4624) forwarded via Azure Monitor Agent
- **Microsoft Sentinel** (Log Analytics / KQL) for scheduled analytics rules, plus **Automation Rules** for incident triage and noise reduction
- **MITRE ATT&CK** mapping for threat-informed prioritization

### Validation

Every rule was tested against live events in a domain lab (`soc.lab`) running a Windows Server 2022 domain controller, a domain-joined Windows analyst workstation, and a Kali Linux attack box, all ingesting into a Microsoft Sentinel workspace (`law-sentinel-lab`).

---

## Credential Access: Password Spraying

Starting from zero credentials, I used `crackmapexec`/`nxc` to spray a small list of guessable passwords against every known username:

```bash
crackmapexec smb 10.0.0.1/24 -u users_AD.txt -p "Winter2024" --continue-on-success
```

A few low-value accounts caught the weak passwords immediately. One hit mattered far more: the `labadmin` account authenticated successfully against a separate candidate password. That single working credential is what turned the rest of this chain from "guessing" into domain access.

**Why this works:** password spraying tries one password against *many* accounts instead of many passwords against one, avoiding per-account lockout thresholds. It only takes one weak or reused password in a large user list to get a foothold.

![password-spray.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Potential-password-spraying.png)

## Credential Access: Dumping the Local SAM

With `labadmin`'s credentials in hand, I pulled the local SAM database off the target:

```bash
crackmapexec smb 10.0.0.1/24 -u labadmin -p 'xxxxxxxx' --sam
```

This dumps locally-stored NTLM password hashes for local accounts, useful for checking password reuse across systems once you have one working login.

![sam_dump.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-10-14%2008-54-54.png)

## Discovery: Guest Account Enumeration

I also tested how much the built-in `Guest` account could see once enabled (`Enable-ADAccount -Identity "Guest"`). Null-session and anonymous-style auth attempts mostly failed, but once a usable credential was supplied, SMB user enumeration through `Guest` succeeded this showed me that even a harmless built-in account can leak directory information if it's accidently active.

![guest-enable.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-10-14%2009-15-52.png)
![guest-enum.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-10-14%2009-20-47.png)

## Credential Access: Kerberoasting

Using the `labadmin` credentials, I requested a Kerberos service ticket for the `Kerberoast` test account, which has a registered SPN (`TestSvc/corp.local`) and still allows RC4 encryption:

```bash
impacket-GetUserSPNs soc.lab/labadmin:'xxxxxxxx' -request -dc-ip 10.0.0.101
```

Because the KDC encrypts that ticket with a key derived from the service account's own password, this hands back a crackable hash, no exploit required, just normal Kerberos behavior pointed at a weak account. (Full background on this technique, including offline cracking with Hashcat, is in my earlier [Kerberoasting writeup](link-to-repo)).

![kerberoast-request.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-10-14%2020-08-35.png)

## Credential Access: Domain Secrets Extraction (DCSync-style)

This is the part that escalates the whole exercise. Using the `DSInternals` PowerShell module and `Get-ADReplAccount`, I queried the domain controller directly for replication data on two accounts:

```powershell
Get-ADReplAccount -SamAccountName "krbtgt" -Domain "SOC" -Server "10.0.0.101"
Get-ADReplAccount -SamAccountName "kerberoast" -Domain "SOC" -Server "10.0.0.101"
```

This returned full credential material for both accounts including NT hashes and the Kerberos encryption keys used to sign tickets.

**Why this matters more than anything else in the chain:** `krbtgt` is the account that signs *every* Kerberos ticket in the domain. Getting its key material is effectively over for the domain it's what attackers need to forge Golden Tickets that impersonate any user, indefinitely, until the `krbtgt` password is rotated (twice, due to password history). This kind of query normally requires Directory Replication rights. In a real environment, seeing this succeed from a non-Domain-Admin account would be a critical finding on its own.

![dsinternals-krbtgt.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-10-14%2020-37-51.png)

## Lateral Movement: Pass-the-Hash

I used nxc, the current evolution of CME against the Guest account using the hash I gained through the credentials from krbtgt. I created some extra traffic of wrong hashes to create some alerts for sentinel show explicit alerts. 

```bash
nxc smb 10.0.0.1/24 -u Guest -H xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx -d soc.lab -users
```

This attempt failed on a malformed command, not a defensive control a good reminder to document mistakes too, since not every step in a real engagement works on the first try.

![psexec-attempt.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-10-18%2016-27-39.png)

---


## Detection Coverage

Windows Auditing Configuration

### Step 1: Confirm Required Event IDs Are Being Generated and Ingested

| Event ID | Purpose |
|---|---|
| 4625 | Failed logon — password spray detection |
| 4769 | Kerberos TGS request — Kerberoasting detection |
| 4662 | Directory object access — DCSync-style replication detection |
| 4624 | Successful logon — NTLM/pass-the-hash detection |

4769 in particular required extra attention: it's not one of the event types Sentinel flattens into native columns, so `EventData` has to be parsed as XML with `extract()` rather than `parse_json()`, which silently returns null and makes every downstream filter fail quietly. This is the same class of gap I hit in my original Kerberoasting project, where 4769 was logged locally by the DC but excluded from forwarding to Wazuh.

### Step 2: Build the Analytics Rules

**Rule 1 — Password Spraying (T1110.003)**

```kql
SecurityEvent
| where EventID == 4625
| where TimeGenerated > ago(5m)
| summarize
    FailedAttempts = count(),
    DistinctAccounts = dcount(TargetUserName),
    Accounts = make_set(TargetUserName)
    by IpAddress, WorkstationName
| where DistinctAccounts >= 3
```

Fires when one source IP generates failed logons against three or more distinct accounts within a 5-minute window the signature of a spray, as opposed to a brute force against a single account.

**Rule 2 — Kerberoasting / RC4 TGS Request (T1558.003)**

```kql
SecurityEvent
| where EventID == 4769
| extend TicketEncryptionType = extract(@'Name="TicketEncryptionType">([^<]+)', 1, EventData)
| extend ServiceName = extract(@'Name="ServiceName">([^<]+)', 1, EventData)
| extend SubjectUserName = extract(@'Name="SubjectUserName">([^<]+)', 1, EventData)
| where TicketEncryptionType == "0x17"
| where ServiceName !endswith "$"
| where ServiceName !startswith "krbtgt" // krbtgt is the Key Distribution Center service account, its password hash serves as the master key by creating a golden ticket on the Kerberos TGT (Golden Ticket exploitation (T1558.001))
| project TimeGenerated, Computer, SubjectUserName, ServiceName, TicketEncryptionType
```

Fires on RC4-encrypted (`0x17`) TGS requests, deliberately excluding AES-encrypted tickets and machine-account traffic to avoid alert fatigue on normal domain activity. If the 

**Rule 3 — Domain Secrets Replication / DCSync-style (T1003.006)**

```kql
SecurityEvent
| where EventID == 4662
| where ObjectType has "domainDNS"
| where AccessMask == "0x100"  
  // Replication rights
| where SubjectUserName !endswith "$"  
  // Not a machine account (DCs are machine accounts)
| project TimeGenerated,
          Computer,
          SubjectUserName,
          ObjectName,
          AccessMask
```

Fires when an account exercises AD replication rights outside of normal Domain Controller replication traffic the highest-severity rule in the set, since this is the exact right pair `Get-ADReplAccount` depends on.

**Rule 4 — NTLM Network Logon / Pass-the-Hash Indicator (T1550.002)**

```kql
let AllowedServers = dynamic(["DC01", "EXCH01"]);
SecurityEvent
| where EventID == 4624
| where LogonType == 3
| where AuthenticationPackageName == "NTLM"
| where not(Account endswith "$")
| where Account !in ("SYSTEM", "ANONYMOUS LOGON")
| summarize logons = count(), Accounts = make_set(Account), IPs = make_set(IpAddress)
```

Fires on network logons (`LogonType == 3`) authenticated via NTLM instead of Kerberos a known pass-the-hash indicator, since NTLM hashes can be replayed without ever knowing the plaintext password.

### Step 3: Automation — Tuning Out Noise

Once live, the NTLM rule generated a steady stream of Medium-severity incidents from the lab's `Guest` account, which I'd intentionally enabled earlier in the exercise legitimate detections, but not actionable noise worth sitting at the same severity as real credential theft. I built an automation rule rather than manually triaging the same false positive repeatedly:

- **Trigger:** When incident is created
- **Condition:** Analytic rule name contains "Suspicious NTLM Network Logon"
- **Actions:** Change severity → Informational, assign owner, change status → Closed, classification reason → False Positive - Inaccurate data

I applied similar logic to the password spray rule, but tuned differently: rather than suppressing it outright, low-occurrence spray incidents are downgraded to Informational automatically, while a spray that crosses a sustained volume threshold still surfaces at full severity. This reflects a real SOC tradeoff — an analyst's attention is the scarcest resource, and a rule that cries wolf gets ignored within a week.

![automation_informational.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Sentinel-incidents-automation-informational.png)

### Triage

| Rule | Alert Level | Event | MITRE |
|---|---|---|---|
| Password Spray | Medium | 4625 | T1110.003 |
| Kerberoasting (RC4) | Medium | 4769 | T1558.003 |
| DCSync-style Replication | High | 4662 | T1003.006 |
| NTLM Network Logon | Medium (auto-downgraded on known-noisy sources) | 4624 | T1550.002 |

### Remediation

- Force the `Kerberoast` account to AES-only encryption (`Set-ADUser Kerberoast -KerberosEncryptionType AES256`) ticket encryption type becomes `0x12` instead of `0x17`, and Rule 2 correctly stops firing on it, since the RC4 weakness it targets no longer exists.
- Rotate the `krbtgt` password twice (to clear password history) following any suspected replication abuse.
- Restrict Directory Replication rights to Domain Admins and Domain Controllers only.

## Kill Chain Timeline

| MITRE ID | Phase | Detection |
|---|---|---|
| T1110.003 | Credential Access | Password spray against `users_AD.txt` from 10.0.0.50 |
| T1003.002 | Credential Access | Local SAM dumped via `labadmin` |
| T1087.002 | Discovery | Guest account enumerates SMB users |
| T1558.003 | Credential Access | RC4 TGS requested for `Kerberoast` account |
| T1003.006 | Credential Access | `Get-ADReplAccount` pulls `krbtgt` and `Kerberoast` secrets |
| T1550.002 | Lateral Movement | Pass-the-hash attempted against `Guest@10.0.0.1/24` |
| T1021.002 | Lateral Movement | `psexec.py` execution attempt (failed) |
