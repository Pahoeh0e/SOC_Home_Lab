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
- [Wazuh Agent Enrollment](#Wazuh-Agent-Enrollment—Windows-&-Linux)
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



# Wazuh Agent Enrollment — Windows & Linux

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
Get-Content "C:\Program Files (x86)\ossec-agent\ossec.conf" | Select-String -Pattern "<address>"
```

Make sure the IP matches your Wazuh Manager. I had mine pointing to an old subnet after moving the VM to a new VLAN.

---

### Check 2 — Can the agent reach the manager?

**On Linux:**
```bash
nc -zv <MANAGER_IP> 1515
nc -zv <MANAGER_IP> 1514
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

---

### Check 4 — Duplicate agent names

**On the Wazuh Manager:**
```bash
sudo /var/ossec/bin/manage_agents -l
```

If the same name appears twice (especially after moving a VM to a new IP), remove the old one:
```bash
sudo /var/ossec/bin/manage_agents -r <AGENT_NAME>
sudo systemctl restart wazuh-manager
```

---

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

### Check 2 — Is the web port listening?

On the Splunk VM:
```bash
sudo ss -tlnp | grep 8000
```

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

**Category:** Wazuh / Splunk Dashboards  
**Lab Context:** Custom Wazuh rules not showing correctly in Splunk dashboards  
**Applies To:** Splunk ingesting Wazuh alerts

---

## What Went Wrong

I built a Splunk dashboard to show my custom Wazuh alerts. Some panels worked, but others showed weird errors or just stayed blank. I thought my rules weren't firing, but the alerts were actually there — Splunk just couldn't read the fields properly.

---

## The Problems I Hit

| What I Saw | Why It Happened |
|-----------|----------------|
| `The '>=' operator received different types` | `rule.level` is a **string** (text), not a number. You can't do `>=` on text. |
| MITRE technique panel shows `0` | The field is called `rule.mitre.id{}` (with curly braces), not `rule.mitre.id` |
| IP address column is blank | The field name I used didn't exist. Wazuh calls it something else. |
| Some rules missing from dashboard | I forgot to add the new rule IDs to the dashboard filter |
| GitHub README images broken | I typed `!{}` instead of `![]` in Markdown |

---

## Diagnosis

### Check 1 — What type is the field?

In Splunk Search, run:
```spl
index=wazuh sourcetype=wazuh rule.id=100001
| eval level_type=typeof(rule.level)
| table rule.level, level_type
```

If it says **String**, that's your problem. You need to convert it before comparing.

### Check 2 — What is the actual field name?

In Splunk Search:
```spl
index=wazuh sourcetype=wazuh rule.id=100001
| fieldsummary
| search field="*mitre*"
```

Look at what Splunk actually extracted. In my case it was `rule.mitre.id{}` — the `{}` at the end matters.

### Check 3 — Which IP field has data?

Test different names:
```spl
index=wazuh sourcetype=wazuh rule.id=100001
| eval ip_1=agent.ip
| eval ip_2=data.srcip
| eval ip_3=win.eventdata.sourceIp
| table ip_1, ip_2, ip_3
```

Use whichever one actually shows a value.

---

## Fixes

### Fix 1 — Convert `rule.level` to a number

**Broken:**
```spl
| eval severity=case(rule.level>=12, "Critical", rule.level>=8, "High", 1=1, "Low")
```

**Fixed:**
```spl
| eval severity=case(tonumber(rule.level)>=12, "Critical", tonumber(rule.level)>=8, "High", 1=1, "Low")
```

`tonumber()` turns the text "10" into the number 10 so `>=` works.

### Fix 2 — Handle the MITRE field properly

**Broken:**
```spl
| stats dc(rule.mitre.id) as techniques
```

**Fixed:**
```spl
| eval mitre_id=mvindex('rule.mitre.id{}', 0)
| stats dc(mitre_id) as techniques
```

The curly braces mean it's a multivalue field. `mvindex()` pulls out the first value. And you must wrap it in **single quotes** in Splunk XML dashboards.

### Fix 3 — Use the right IP field

**Broken:**
```spl
| table win.eventdata.sourceIp
```

**Fixed:**
```spl
| eval endpoint_ip=coalesce(agent.ip, data.srcip, "unknown")
| table endpoint_ip
```

`coalesce()` tries each field and uses the first one that has a value. `"unknown"` is a fallback so the panel never stays blank.

### Fix 4 — Include all your rule IDs

If you add a new rule (e.g. 100400) but your dashboard filter only lists the old ones, the new alert won't appear.

**Check what rules actually have alerts:**
```spl
index=wazuh sourcetype=wazuh
| stats count by rule.id
| sort rule.id
```

Then make sure your dashboard includes all of them in its `rule.id IN (...)` filter.

### Fix 5 — Fix GitHub image links

**Broken:**
```markdown
!{}(screenshots/alert.png)
```

**Fixed:**
```markdown
![Wazuh Alert](screenshots/alert.png)
```

Syntax is: `![description](path)` — square brackets, not curly braces.

---

## Quick Reference — Common Wazuh Fields in Splunk

| What You Want | Field Name | Type | Tip |
|--------------|-----------|------|-----|
| Rule ID | `rule.id` | String | Use `tonumber()` if doing math |
| Rule Level | `rule.level` | String | Always convert with `tonumber()` |
| MITRE ID | `rule.mitre.id{}` | Multivalue | Use `mvindex('field', 0)` |
| Agent Name | `agent.name` | String | Usually reliable |
| IP Address | `agent.ip` or `data.srcip` | String | Use `coalesce()` as fallback |
| Timestamp | `_time` | Time | Built into Splunk |

---

## Lessons Learned

- **Don't assume field names or types.** Just because it looks like a number doesn't mean Splunk treats it as one. Always check with `typeof()`.
- **Curly braces in field names are real.** Wazuh sends `rule.mitre.id{}` not `rule.mitre.id`. Missing those two characters breaks the whole panel.
- **Test in Splunk Search first.** Dashboard XML is harder to debug. Get the search working, then paste it into the dashboard.
- **Use `coalesce()` for fields that might be empty.** It keeps your dashboard looking clean instead of showing blanks.
- **Markdown typos are embarrassing.** `![]` not `!{}`. I checked my XML for hours before realising the README was the problem.

### Wazuh-to-Splunk Field Reference (Common Mappings)

| Concept | Wazuh Field | Splunk Type | Notes |
|---------|-------------|-------------|-------|
| Rule ID | `rule.id` | String | Use `tonumber()` for math |
| Rule Level | `rule.level` | String | Use `tonumber()` for comparisons |
| MITRE ID | `rule.mitre.id{}` | Multivalue | Use `mvindex()` to extract |
| MITRE Tactic | `rule.mitre.tactic{}` | Multivalue | Use `mvindex()` to extract |
| Agent Name | `agent.name` | String | Reliable |
| Agent IP | `agent.ip` | String | May be missing; fallback to `data.srcip` |
| Source IP | `data.srcip` | String | Network-based rules |
| Process Image | `win.eventdata.image` | String | Sysmon Event ID 1 |
| Command Line | `win.eventdata.commandLine` | String | Sysmon Event ID 1 |
| Parent Image | `win.eventdata.parentImage` | String | Sysmon Event ID 1 |
| Target Image | `win.eventdata.targetImage` | String | Sysmon Event ID 10 |
| Timestamp | `_time` | Time | Splunk-native, always present |

