# Configuration Troubleshooting

## Format

Each guide follows the same structure:
- **What went wrong** — Symptomshat you see when the issue occurs
- **The Problem** — why it happens
- **How I Figured It Out** — commands and checks to confirm
- **Fix/Fixes** — step-by-step resolution
- **How to Check It's Working** - Confirming the fix works
- **lessons learnt** — how to avoid it next time


## Index:
- [VM Network Bridge](#VM-Network-Bridge)
- [Wazuh Agent Enrollment](#Wazuh-Agent-Enrollment-for-Windows-&-Linux)
- [Splunk Web UI not Accessbible](#Splunk-Web-UI-Not-Accessible)
- [Splunk Dashboard Field Errors](#Splunk-Dashboard-Field-Errors)



# VM Network Bridge

**Category:** Proxmox / VM Setup  
**Lab Context:** Windows VM has no internet or network connection  
**Applies To:** Windows Server, Windows 10/11 VMs

---

## What Went Wrong

I set up a Windows Server VM in Proxmox and it booted fine, but had no network connection at all. `ipconfig` only showed the loopback adapter. Device Manager had a yellow warning on "Ethernet Controller." I spent a while checking cables and VLAN settings before realising Windows simply didn't recognise the network card.

---

## The Problem

Proxmox lets you choose different network adapter types. I had picked **VirtIO** because it was the default and sounded modern. But Windows doesn't include VirtIO drivers out of the box — it has no idea what the device is.

| Adapter Type | Does Windows Know It? | When to Use It |
|-------------|----------------------|----------------|
| **VirtIO** | ❌ No — needs extra drivers | Linux VMs, or Windows after you install drivers |
| **Intel E1000** | ✅ Yes — built in | Windows VMs, quick setup, first install |
| **Realtek RTL8139** | ✅ Yes — but old and slow | Avoid unless nothing else works |

---

## How I Figured It Out

**In Proxmox:**
1. Clicked the VM → **Hardware**
2. Looked at **Network Device**
3. Saw **Model: VirtIO (paravirtualized)**

**In Windows Device Manager:**
1. Right-clicked Start → **Device Manager**
2. Under **Network adapters** saw a yellow warning on "Ethernet Controller"
3. Status said: "Drivers for this device are not installed"

That was the giveaway. Windows knew a network card existed but had no driver for it.


## Fixes

### Fix 1 - VirtIO performs better, but you need to give Windows the driver manually.

1. In Proxmox: **VM → Hardware → Add → CD/DVD Drive**
2. Select `virtio-win.iso` from the ISO images list
3. **Start** the VM
4. In Windows Device Manager:
   - Right-click the unknown **Ethernet Controller**
   - Choose **Update driver**
   - **Browse my computer**
   - Go to the CD drive → `NetKVM\w11\amd64` (or `2k22` for Server 2022)
   - Click **OK** → **Next** → Install
5. The adapter now shows as **Red Hat VirtIO Ethernet Adapter**

---

## The Quick Fix - Change the adapter to Intel E1000.** No driver needed.

1. **Shut down the Windows VM**
2. In Proxmox: **VM → Hardware → Network Device → Edit**
3. Change **Model** from `VirtIO` to **`Intel E1000`**
4. Click **OK**
5. **Start** the VM
6. In Windows: `ipconfig` now shows the adapter and an IP address

This took 30 seconds and fixed it immediately.

---


## How to Check It's Working

In Windows Command Prompt:
```cmd
ipconfig
```

You should see:
```
Ethernet adapter Ethernet:
   IPv4 Address. . . . . . . . . . . . : 10.0.0.101
   Subnet Mask . . . . . . . . . . . . : 255.255.255.0
   Default Gateway . . . . . . . . . . : 10.0.0.1
```

Then test:
```cmd
ping 10.0.0.1
ping 8.8.8.8
```

Both should reply.

---

## Lessons Learned

- **If Windows has no network, check Device Manager first.** It tells you whether the OS even sees the hardware.
- **VirtIO is great for Linux, but Windows needs help.** Use E1000 for Windows unless you have a reason not to.
- **The fix is usually the simple one.** I checked VLANs, bridges, and firewall rules before realising it was just a missing driver.
- **For quick lab setups, E1000 + IDE is fine.** You can optimise later once everything is working.



# Wazuh Agent Enrollment for Windows & Linux

**Category:** Wazuh / Agent Setup  
**Lab Context:** Adding endpoints to Wazuh SIEM for monitoring  
**Applies To:** Windows Server, Ubuntu/Debian Linux

---

## What Went Wrong

I spent hours trying to get my Windows and Linux VMs to show up as active agents in the Wazuh Dashboard. They either:
- Did not appear in the agent list at all
- Showed up as **"Never connected"**
- Got stuck in a loop of reinstalling the agent with no success

I reinstalled the agent multiple times before realising the problem was not the install — it was the network path between the agent and the manager.

---

## The Two-Step Process

Getting an agent working is actually two separate steps:

1. **Enrollment** — the agent gets a security key from the manager (port 1515)
2. **Connection** — the agent starts sending data to the manager (port 1514)

Both need to work. I kept fixing one and forgetting the other.

---

## Common Causes

| Problem | What It Looks Like | Usually Caused By |
|---------|-------------------|-------------------|
| Agent not in list | Dashboard shows no agent at all | Wrong manager IP in agent config |
| "Never connected" | Agent appears but status is grey | Firewall blocking port 1514 |
| "Duplicate name" error | Enrollment fails with a warning | Old agent entry still on manager |
| "Unable to connect to enrollment service" | Agent log shows this repeatedly | Manager auth service not running, or network path blocked |

---

## Diagnosis

### Check 1 — Is the agent pointing at the right manager IP?

**On Linux:**
```bash
grep -A 2 "<server>" /var/ossec/etc/ossec.conf
```

**On Windows (PowerShell):**
```powershell
Get-Content "C:\Program Files (x86)\ossec-agent\ossec.conf" tail -20
```

![Get-content.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/ossec.log.png)

Make sure the IP matches your Wazuh Manager. I had mine pointing to an old subnet after moving the VM to a new VLAN.

---

### Check 2 — Can the agent reach the manager?

**On Linux:**
```bash
nc -zv <MANAGER_IP> 1515
nc -zv <MANAGER_IP> 1514
ip route show
```

**On Windows (PowerShell):**
```powershell
Test-NetConnection -ComputerName <MANAGER_IP> -Port 1515
Test-NetConnection -ComputerName <MANAGER_IP> -Port 1514

```

If either test fails, a firewall is blocking the path. In my lab, pfSense was dropping traffic between VLANs until I added a pass rule.

---

### Check 3 — Is the manager listening?

**On the Wazuh Manager:**
```bash
sudo ss -tlnp | grep -E "1514|1515"
```

You should see both ports listed. If 1515 is missing, the auth service is not running. Restart the manager:
```bash
sudo systemctl restart wazuh-manager
```
![psaux.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/ps-aux.png)
---

### Check 4 — Duplicate agent names

**On the Wazuh Manager:**
```bash
sudo /var/ossec/bin/agent_control -l
```
![manageagents](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/agent_control-l.png)

If the same name appears twice (especially after moving a VM to a new IP), remove the old one:
```bash
sudo /var/ossec/bin/manage_agents -R <AGENT_NUMBER>
sudo systemctl restart wazuh-manager
```

---


![duplicate.png](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Windows-agent-log.png)


## Fixes

### Fix 1 — Update the manager IP in the agent config

**Linux:**
```bash
sudo nano /var/ossec/etc/ossec.conf
# Change <address> to your manager IP
sudo systemctl restart wazuh-agent
```

**Windows:**
```powershell
# Edit with Notepad as Administrator
notepad "C:\Program Files (x86)\ossec-agent\ossec.conf"
# Restart the service
Restart-Service -Name WazuhSvc
```

---

### Fix 2 — Open the firewall path

In my lab, the agent and manager were on different VLANs. I had to add a rule in pfSense to allow traffic between them.

**What I added in pfSense:**
- Interface: LAN (where the agent lives)
- Source: LAN subnets
- Destination: MGMT subnets
- Protocol: Any
- Ports: 1514 and 1515

I also learned that pfSense is **stateful** — you only need to allow the outbound path. Return traffic is handled automatically. I had added an inbound rule on the MGMT side that was unnecessary.

---

### Fix 3 — Remove stale agents and re-enrol

**On the manager:**
```bash
sudo /var/ossec/bin/manage_agents -r <AGENT_NAME>
sudo systemctl restart wazuh-manager
```

**On Linux:**
```bash
sudo systemctl restart wazuh-agent
sudo tail -f /var/ossec/logs/ossec.log
```

**On Windows:**
```powershell
Restart-Service -Name WazuhSvc
Get-Content "C:\Program Files (x86)\ossec-agent\ossec.log" -Tail 20
```

Watch for `Connected to the server` in the log.

---

### Fix 4 — Manual enrollment if auto-enrol keeps failing

If the automatic enrollment keeps failing, do it manually.

**On the manager:**
```bash
sudo /var/ossec/bin/manage_agents
# Press A to add, E to extract key, then copy the key string
```

**On Linux:**
```bash
sudo /var/ossec/bin/manage_agents -i
# Paste the key when prompted
sudo systemctl restart wazuh-agent
```

**On Windows:**
```powershell
cd "C:\Program Files (x86)\ossec-agent"
.\manage_agents.exe -i
# Paste the key when prompted
Restart-Service -Name WazuhSvc
```

---

## Verification

| Check | Where | What to Look For |
|-------|-------|-----------------|
| Agent listed | Wazuh Dashboard → Agents | Hostname appears in the list |
| Status active | Wazuh Dashboard → Agents | Status shows **Active** (green) |
| Log confirms | Agent VM | `Connected to the server` in ossec.log |
| Ports open | Manager | `ss -tlnp` shows 1514 and 1515 listening |

---

## Lessons Learned

- **Do not reinstall the agent as a first step.** Check the IP, the firewall, and the manager first. Reinstalling without fixing the network just wastes time.
- **Moving a VM to a new VLAN means updating everything.** The agent config, the firewall rules, and sometimes the agent enrollment on the manager all need to change.
- **Check for duplicate agents after any IP change.** The manager remembers the old name and rejects the new one.
- **Stateful firewalls only need one rule.** I was adding rules on both sides of pfSense when only the source side needed one.
- **Read the agent log before guessing.** `ossec.log` on the agent tells you exactly what is failing — enrollment, connection, or authentication.



# Splunk Web UI Not Accessible

**Category:** Splunk / Access  
**Lab Context:** Kali Linux accessing Splunk via SSH tunnel  
**Applies To:** Splunk running on a separate VM

---

## What Went Wrong

I had Splunk working perfectly. I could open a browser on Kali, go to `http://localhost:8080`, and the Splunk login page appeared. Then I rebooted the Proxmox host and everything broke. The browser showed "Unable to connect." I assumed I had broken the network, but it turned out to be two much simpler things.

---

## The Two Problems

There are actually two separate things that can break, and they both happened to me:

1. **Splunk wasn't running** — the service doesn't start automatically after a reboot
2. **The SSH tunnel was gone** — tunnels disappear when you reboot

I kept checking network settings when the real issues were much simpler.

---

## Diagnosis

### Check 1 — Is Splunk actually running?

SSH into the Splunk VM and run:
```bash
sudo /opt/splunk/bin/splunk status
```

If it says:
```
Splunk is not running.
```

That's problem one.

### Check 2 — Is the web port listening? What error logs can we get

On the Splunk VM:
```bash
sudo ss -tlnp | grep 8000
tail -n 20 /home/splunk/splunk/var/log/splunk/splunkd.log 
```
![splunk.log](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/splunk-struggling-start-web.png)

If you get nothing back, the web service isn't active.

### Check 3 — Is the SSH tunnel still there?

On Kali:
```bash
ss -tlnp | grep 8080
```

If you get nothing, the tunnel died when you rebooted.

---

## Fixes

### Fix 1 — Start Splunk

On the Splunk VM:
```bash
sudo /opt/splunk/bin/splunk start
```

To stop it from happening again, enable auto-start:
```bash
sudo /opt/splunk/bin/splunk enable boot-start
```

Verify it's running:
```bash
sudo /opt/splunk/bin/splunk status
sudo ss -tlnp | grep 8000
```

### Fix 2 — Recreate the SSH Tunnel

On Kali, open a terminal and run:
```bash
ssh -L 8080:192.168.30.11:8000 ubuntu@192.168.30.11
```

Keep that terminal open. Now browse to:
```
http://localhost:8080
```

**To run it in the background** so you can close the terminal:
```bash
ssh -fN -L 8080:192.168.30.11:8000 ubuntu@192.168.30.11
```

**To stop the tunnel later:**
```bash
ps aux | grep "ssh.*8080"
kill <PID>
```

---

## A Script to Make It Easier

I got tired of typing the tunnel command every time, so I made a script on Kali.

Save this as `~/splunk-tunnel.sh`:
```bash
#!/bin/bash

TUNNEL_PID=$(pgrep -f "ssh.*-L 8080:192.168.30.11:8000")

if [ -n "$TUNNEL_PID" ]; then
    echo "Tunnel already running (PID: $TUNNEL_PID)"
else
    echo "Starting Splunk tunnel..."
    ssh -fN -L 8080:192.168.30.11:8000 ubuntu@192.168.30.11
    echo "Done. Browse to http://localhost:8080"
fi
```

Make it runnable:
```bash
chmod +x ~/splunk-tunnel.sh
```

Run it after every reboot:
```bash
~/splunk-tunnel.sh
```

---

## Verification

| Check | Where | What to Look For |
|-------|-------|-----------------|
| Splunk running | Splunk VM | `splunk status` says "running" |
| Web port open | Splunk VM | `ss` shows `0.0.0.0:8000` |
| Tunnel active | Kali | `ss` shows `127.0.0.1:8080` |
| Page loads | Browser on Kali | Splunk login appears at `localhost:8080` |

---

## Lessons Learned

- **Rebooting breaks more than you think.** Services don't auto-start unless you tell them to. SSH tunnels definitely don't survive reboots.
- **Check the obvious first.** I spent time checking VLANs and firewalls when Splunk was simply not running.
- **Write a script for anything you do more than twice.** The tunnel command is annoying to remember. A 10-line script saves time every reboot.
- **Boot-start is your friend.** `splunk enable boot-start` means one less thing to forget.



# Splunk Dashboard Field Errors

> **Lab:** Home SOC Lab (Proxmox)  
> **Tools:** Wazuh, Splunk, Sysmon  
> **Goal:** Build a kill-chain dashboard ("Operation Feeding Time") to track custom Wazuh alerts

---

## What I Was Trying to Do

I built a Splunk dashboard to visualise an end-to-end kill chain:

**Phishing → Macro → PowerShell → Credential Dump → Lateral Movement → Exfiltration**

Some panels worked straight away, but others broke or stayed blank. I had to figure out whether my Wazuh rules weren't firing, or whether Splunk just couldn't read the fields properly.

---

## Problem 1: Type Error in Risk Score

**What I saw:** The *Host Risk Score* panel showed this error:

> `Error in 'EvalCommand': Type checking failed. The '>=' operator received different types.`

![Type_error](https://github.com/Pahoeh0e/SOC_Home_Lab/tree/main/Operations/Screenshots/Splunk-Dashboard-Errors13.png)

**My thought process:** I thought `rule.level` was a number because it looks like one (e.g. `10`, `12`). But Splunk extracts it as a **string** (text). You can't do `>=` on text.

**How I Figured It Out:**
```spl
index=wazuh sourcetype=wazuh rule.id=100105
| eval level_type=typeof(rule.level)
| table rule.level, level_type
```

**The fix:** Wrap it in `tonumber()` before comparing:
```spl
| eval severity=case(
    tonumber(rule.level)>=12, "Critical",
    tonumber(rule.level)>=8, "High",
    1=1, "Low"
  )
```

---

## Problem 2: MITRE Panel Showed `0`

**What I saw:** The *MITRE ATT&CK Coverage* panel showed a big `0`, even though my rules had MITRE tags.

![MITRE1](https://github.com/Pahoeh0e/SOC_Home_Lab/tree/main/Operations/Screenshots/Splunk-Dashboard-Errors3.png)

**My thought process:** I was searching for `rule.mitre.id`, but when I looked at the raw event fields, the actual name had curly braces on the end.

**How I Figured It Out:**
```spl
index=wazuh sourcetype=wazuh rule.id="100105"
| head 1
| table rule.mitre*
```

![MITRE2](https://github.com/Pahoeh0e/SOC_Home_Lab/tree/main/Operations/Screenshots/Splunk-Dashboard-Errors1.png)

The field is called `rule.mitre.id{}` — those two characters `{}` matter because it's a **multivalue** field.

**The fix:**
```spl
| eval mitre_id=mvindex('rule.mitre.id{}', 0)
| stats dc(mitre_id) as techniques
```

> **Note:** In Splunk dashboard XML, you must wrap curly-brace fields in **single quotes**.

I also checked `fieldsummary` to confirm the field existed, which showed the MITRE fields but with zero counts — that was a red herring because `fieldsummary` after `head 1` only sees one event.

![MITRE_count](https://github.com/Pahoeh0e/SOC_Home_Lab/tree/main/Operations/Screenshots/Splunk-Dashboard-Errors2.png)

---

## Problem 3: `rule_id` Column Was `Null`

**How I Figured It Out:** In the *Endpoint Alert* table, the `rule_id` column showed `Null` for every row, but `rule.description` was fine.

![rule_id](https://github.com/Pahoeh0e/SOC_Home_Lab/tree/main/Operations/Screenshots/Splunk-Dashboard-Errors11.png)

**My thought process:** The dashboard XML or search was referencing a field name that didn't match what Splunk extracted. I needed to make sure `rule.id` was explicitly passed through to the table.

**The fix:** Explicitly create the field in the search:
```spl
| eval rule_id=rule.id
| table _time, rule_id, rule.description, endpoint_ip, uri, status, user_agent
```

---

## Problem 4: Empty Map and "No Results Found"

**What I saw:** The *Staging Server Activity* panel said "No results found" and the *Source IPs Hitting Staging Server* map was completely blank.

![Empty_map](https://github.com/Pahoeh0e/SOC_Home_Lab/tree/main/Operations/Screenshots/Splunk-Dashboard-Errors4.png)

**My thought process:** Two things were wrong here:
1. I was using `win.eventdata.sourceIp` but that field didn't exist in these events.
2. My dashboard filter (`rule.id IN (...)`) was missing some of the rule IDs that actually had data.

**How I checked which IP field had data:**
```spl
index=wazuh sourcetype=wazuh rule.id=100105
| eval ip_1=agent.ip
| eval ip_2=data.srcip
| eval ip_3=win.eventdata.sourceIp
| table ip_1, ip_2, ip_3
```

![Agent-IP](https://github.com/Pahoeh0e/SOC_Home_Lab/tree/main/Operations/Screenshots/Splunk-Dashboard-Errors8.png)

`agent.ip` (e.g. `10.0.0.101`) and `data.srcip` had values.

I also checked which rules had alerts in the index:
```spl
index=wazuh sourcetype=wazuh
| stats count by rule.id
| sort rule.id
```

![rule.id2](https://github.com/Pahoeh0e/SOC_Home_Lab/tree/main/Operations/Screenshots/Splunk-Dashboard-Errors6.png)

**The fix:** Use `coalesce()` to try multiple IP fields, and update the `rule.id` filter:
```spl
| eval endpoint_ip=coalesce(agent.ip, data.srcip, "unknown")
```

---

## Problem 5: Timeline Showed "Unknown"

**What I saw:** The *Kill Chain Timeline* had a legend entry called `Unknown` instead of the actual kill-chain phases.

![Timeline](https://github.com/Pahoeh0e/SOC_Home_Lab/tree/main/Operations/Screenshots/Splunk-Dashboard-Errors12.png)

**My thought process:** The field I was using to split the chart series didn't exist or wasn't populated, so Splunk defaulted everything to `Unknown`.

**The fix:** Explicitly map rule IDs to phases:
```spl
| eval phase=case(
    rule.id="100001", "Initial Access",
    rule.id="100105", "Execution",
    rule.id="100018", "Exfiltration",
    1=1, "Other"
  )
| timechart count by phase
```

After the fix, the timeline showed proper spikes with correct phase labels:

![timeline](https://github.com/Pahoeh0e/SOC_Home_Lab/tree/main/Operations/Screenshots/Splunk-Dashboard-Errors14.png)

---

## Quick Reference — Wazuh Fields in Splunk

| What You Want | Field Name | Type | Tip |
|--------------|-----------|------|-----|
| Rule ID | `rule.id` | String | Use `tonumber()` for math |
| Rule Level | `rule.level` | String | Always convert with `tonumber()` |
| MITRE ID | `rule.mitre.id{}` | Multivalue | Use `mvindex('field', 0)` |
| Agent Name | `agent.name` | String | Usually reliable |
| Agent IP | `agent.ip` | String | Fallback to `data.srcip` |
| Source IP | `data.srcip` | String | Network-based rules |
| Timestamp | `_time` | Time | Built into Splunk |

---

## Lessons Learnt

1. **Don't assume a field is a number just because it looks like one.** Always check with `typeof()`.
2. **Curly braces in field names are real.** `rule.mitre.id{}` is not the same as `rule.mitre.id`.
3. **Test in Splunk Search first.** Dashboard XML is harder to debug. Get the search working, then paste it in.
4. **Use `coalesce()` for fields that might be empty.** It stops panels showing blanks.
5. **Update your filters when you add new rules.** If `rule.id IN (...)` is stale, new alerts just vanish.
6. **`Null` in a table usually means a field name mismatch.** Splunk won't error — it'll just show `Null`.

