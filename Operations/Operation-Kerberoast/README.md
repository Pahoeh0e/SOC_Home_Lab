## Operation Kerberoast: Active Directory Ticket-Granting Ticket Abuse

A simulated Kerberoasting attack chain demonstrating Active Directory detection via Windows Security event auditing and Wazuh, mapped to MITRE ATT&CK. Built in a domain-joined lab to replicate a realistic AD attack path from unprivileged foothold to credential compromise.

## Threat Scenario

| Phase | Technique | MITRE ID |
|-------|-----------|----------|
| Discovery	| SPN Enumeration | 	T1087.002 |
| Credential Access |	Kerberoasting (RC4 TGS Extraction) |	T1558.003 |
|Credential Access |	Offline Password Cracking |	T1110.002 |

### Detection Coverage

This repository implements detection logic for the credential access phase using:

- ** Windows Security Auditing ** (Event ID 4769 — Kerberos Service Ticket Operations)
- **Wazuh ** for real-time forwarding and alerting from the Domain Controller
- ** MITRE ATT&CK ** mapping for threat-informed prioritization, keyed specifically on ticket encryption type rather than raw event volume

### Validation

Every rule was tested against live events in a domain lab (soc.lab) running a Windows Server domain controller, a domain-joined Windows analyst workstation, and a Kali Linux VM for offline cracking, all monitored by a Wazuh manager.
---

## Discovery: SPN Enumeration

Foothold: svc-splunk (displayed in AD as "Sam") a standard, non-privileged domain user with no elevated group membership. This is the key condition for the entire attack: Kerberoasting requires no special privileges, only a valid authenticated domain account.

From the analyst workstation Sam enumerates every account in the domain with a registered Service Principal Name (SPN), since only SPN-bearing accounts can be targeted:

``` cmd
setspn -Q */*

```

This is a legitimate LDAP query available to any authenticated domain user so it cannot be restricted without breaking normal Kerberos service lookups. The Kerberoast account appeared in the results with a registered SPN.

![setspn.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Setspn-Q-kerberoast.png)

## Credential Access: Ticket Extraction (Kerberoasting)

With the target SPN identified, request a Kerberos service ticket (TGS) using Rubeus:

``` powershell
.\Rubeus.exe kerberoast /user:Kerberoast /outfile:hashes.txt /format:hashcat

```

Requesting a TGS is normal Kerberos behavior. What makes it exploitable is that the KDC encrypts the returned ticket using a key derived from the target service account's own password hash not the requester's. Because Kerberoast was configured to allow RC4 (msDS-SupportedEncryptionTypes: 0x4), the ticket came back encrypted with RC4-HMAC, a weak and fast-to-crack cipher.

![rubeus-hash-extraction.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Kerberoast-exploit.png)

## Credential Access: Offline Cracking

The extracted ticket was transferred to a Kali Linux VM and cracked offline with Hashcat. From this point forward, no further interaction with the domain is required. The remainder of the attack happens fully offline, which is what makes Kerberoasting difficult to rate-limit or block after the hash has been extracted.

```bash
hashcat -m 19700 hashes.txt /usr/share/wordlists/rockyou.txt
```

![hashcat-kerberoast.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Hashcat-kerberoast1.png)
![hashcat-kerberoast-cracked.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Kerberoast-hashcat-cracked.png)

## Detection Coverage
Windows Auditing Configuration
Step 1: Enable Kerberos Service Ticket Auditing

On the Domain Controller:

```powershell
auditpol /set /subcategory:"Kerberos Service Ticket Operations" /success:enable /failure:enable
```

Without this, Event ID 4769 is not generated.

Step 2: Confirm the Wazuh Agent Reads the Security Channel

Edit ossec.conf on the DC's Wazuh agent to confirm no filter is silently dropping 4769 from the query:

xml
<localfile>
  <location>Security</location>
  <log_format>eventchannel</log_format>
</localfile>

![no4769ruleossec.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/kerberoast-ossec-no-4769.png)

Note: During setup, this environment shipped with a default query excluding a range of high-volume event IDs for noise reduction. Event ID 4769 was inadvertently included in that exclusion list, which meant the DC logged the event locally but never forwarded it to Wazuh — the event existed, but was invisible to the SIEM. Removing 4769 from the exclusion list resolved this.

Restart the agent:

```powershell
Restart-Service -Name Wazuh
```
Step 3: Add Custom Rule

For all custom rules view the [Custom-Detection-Rules](https://github.com/Pahoeh0e/SOC_Home_Lab/tree/main/Custom_Rules)

Add this to /var/ossec/etc/rules/local_rules.xml on the Wazuh manager:

```xml
<group name="det012_kerberoasting,windows_security,">
  <rule id="110300" level="12">
    <if_group>windows_security</if_group>
    <field name="win.system.eventID">^4769$</field>
    <field name="win.eventdata.ticketEncryptionType">^0x17$</field>
    <description>Possible Kerberoasting: RC4 TGS ticket requested for $(win.eventdata.serviceName) by $(win.eventdata.targetUserName)</description>
    <mitre>
      <id>T1558.003</id>
    </mitre>
  </rule>
</group>
```

Kerberoasting Detection (RC4 TGS Request)

Wazuh Rule 110300 fires when a service ticket is requested with RC4 encryption, detecting:

TGS ticket requested for an SPN-bearing account (serviceName)
Ticket encryption type 0x17 (RC4-HMAC) — deliberately excludes AES-encrypted tickets and routine machine-account traffic to avoid alert fatigue on normal domain activity

Alert Level: 12
Event: Windows Security 4769
MITRE: T1558.003

Triage

## Remediation

Force the Kerberoast account to AES-only encryption (Set-ADUser Kerberoast -KerberosEncryptionType AES256) 0x12 instead of 0x17 and that rule 110300 correctly does not fire on it, since the RC4 weakness it targets no longer exists. This demonstrates the rule is precise to the actual risk indicator rather than alerting on ticket requests generally.

## Kill Chain Timeline
|Time |	MITRE ID	| Phase	| Detection |
|-----|-----------|-------|-----------|
| T+0s |	T1087.002	| Discovery	| svc-splunk enumerates SPNs |
|T+0s	| T1558.003	| Credential Access	| Rubeus requests RC4 TGS for Kerberoast account |
|T+0s	| 110300 | Credential Access	| Wazuh fires on RC4-encrypted 4769 for Kerberoast |
|T+[X]s |	T1110.002	| Credential Access |	Password cracked offline via Hashcat |
