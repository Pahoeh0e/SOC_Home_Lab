# Configuration Troubleshooting

## Format

Each guide follows the same structure:
- **Symptoms** — what you see when the issue occurs
- **Root Cause** — why it happens
- **Diagnosis** — commands and checks to confirm
- **Fix** — step-by-step resolution
- **Verification** - Confirming the fix works
- **lessons learnt** — how to avoid it next time


## Index:
- [VM Network Bridge](#VM-Network-Bridge-not-working)
- [Wazuh Agent Unreachable](#Wazuh-Agent-Unreachable)
- [Splunk Web UI not Accessbible](#Splunk-Web-UI-Not-Accessible)



# VM Network Bridge not working

## Symptoms

- Windows Server or Windows 10 VM boots but shows **"Unknown device"** or **"Ethernet controller" with a yellow warning** in Device Manager
- No network connectivity inside Windows — `ipconfig` shows only loopback adapter
- Windows installer cannot download updates or drivers during setup
- Proxmox Hardware tab shows network adapter as `VirtIO` but Windows has no driver for it
- After changing from VirtIO to E1000, network works immediately

## Root Cause

Windows does **not** include VirtIO drivers by default. VirtIO is a paravirtualized driver optimized for KVM/QEMU, but the guest OS must have the driver installed to recognize the device.

| Adapter Type | Driver Included in Windows? | Performance | Use Case |
|-------------|---------------------------|-------------|----------|
| **VirtIO** | ❌ No — must load separately | Best (paravirtualized) | Linux VMs, Windows after driver install |
| **Intel E1000** | ✅ Yes — built-in since Windows XP/2003 | Good (emulated) | Windows install, quick setup |
| **Realtek RTL8139** | ✅ Yes | Poor (legacy) | Avoid |

If you choose VirtIO for a Windows VM **without** loading the `virtio-win.iso` driver disk, Windows literally cannot see the network card.

## Diagnosis

### In Proxmox Web UI

1. Click the VM → **Hardware**
2. Look at **Network Device**

**Problem configuration:**
```
Model: VirtIO (paravirtualized)
Bridge: vmbr1
```

**Working configuration:**
```
Model: Intel E1000
Bridge: vmbr1
```

### In Windows Device Manager

1. Right-click **Start** → **Device Manager**
2. Look under **Network adapters**

**Problem:**
```
⚠️ Ethernet Controller
   Status: Drivers for this device are not installed
```

**Working:**
```
✅ Intel(R) PRO/1000 MT Network Connection
```

### From Proxmox Shell

```bash
qm config <VMID> | grep net
```

**Problem:**
```
net0: virtio=XX:XX:XX:XX:XX:XX,bridge=vmbr1
```

**Working:**
```
net0: e1000=XX:XX:XX:XX:XX:XX,bridge=vmbr1
```

## Fix

### Option A: Switch to E1000 

Fastest fix — no driver needed.

1. **Shut down the Windows VM**
2. In Proxmox: **VM → Hardware → Network Device → Edit**
3. Change **Model** from `VirtIO` to **`Intel E1000`**
4. Click **OK**
5. **Start** the VM
6. In Windows: `ipconfig` should now show the adapter

### Option B: Keep VirtIO and Load Drivers

Better long-term performance, but requires extra steps.

1. **Ensure `virtio-win.iso` is attached to a CD/DVD drive**
   - VM → Hardware → Add → CD/DVD Drive
   - Select `virtio-win.iso` from ISO images
2. **Start the Windows VM**
3. In Windows Device Manager:
   - Right-click **Unknown device** → **Update driver**
   - **Browse my computer**
   - Navigate to the CD drive → `NetKVM\w11\amd64` (or `2k22` for Server 2022)
   - Click **OK** → **Next** → Install
4. **Verify:** Adapter now shows as **Red Hat VirtIO Ethernet Adapter**


```

Should show:
```
Ethernet adapter Ethernet:
   Connection-specific DNS Suffix . . . : soc.lab
   IPv4 Address. . . . . . . . . . . . : 10.0.0.101
   Subnet Mask . . . . . . . . . . . . : 255.255.255.0
   Default Gateway . . . . . . . . . . : 10.0.0.1
```

### Test Connectivity

```cmd
ping 10.0.0.1
ping 8.8.8.8
```

Both should succeed.

## Lessons Learnt

| Decision | Recommendation |
|----------|---------------|
| Installing Windows for the first time | Use **E1000** — get it working, switch later |
| Linux VMs (Kali, Ubuntu) | Use **VirtIO** — drivers are built into the kernel |
| Production/high-performance Windows | Install with E1000, add VirtIO drivers, then switch |
| Quick lab setup | Use **E1000 + IDE** everywhere — one less variable |



# Wazuh Agent Unreachable


## Symptoms

- `sudo /var/ossec/bin/agent_control -l` shows the agent as `Unknown` or `Never connected`
- Agent was previously `Active` but reverted to `Unknown` after a reboot or manager restart
- `agent-auth.exe` on Windows returns `Agent added` but the agent still shows `Never connected`
- `wazuh-authd` is not running on the manager; port 1515 is not listening
- Custom rules are loaded but no alerts appear in `alerts.log` or `alerts.json`
- Wazuh Dashboard web UI shows **"server is not ready"** or no Security Events
- Repeatedly deleting and re-registering the agent works briefly, then fails again

## Root Cause

Wazuh agent-to-manager communication involves **three separate services** and **two distinct ports**. A failure at any layer breaks the pipeline:

```
Windows Agent                          Wazuh Manager
    │                                        │
    ├──► authd (port 1515) ──► key exchange   │  [Registration]
    │      (wazuh-authd)                       │
    │                                        │
    ├──► remoted (port 1514) ──► keepalives   │  [Persistent connection]
    │      (wazuh-remoted)                     │
    │                                        │
    │         Sysmon/EventLog events ──► analysisd ──► alerts.log/json
    │                                        │  [Analysis & alerting]
    │                                        │
    │         alerts.json ──► indexer ──► dashboard
    │                                        │  [Web UI visibility]
```

Common failure points:

| Layer | Service | Port | Symptom When Broken |
|-------|---------|------|---------------------|
| Registration | `wazuh-authd` | 1515 | `agent-auth.exe` fails or times out |
| Connection | `wazuh-remoted` | 1514 | Agent shows `Never connected` after auth |
| Analysis | `wazuh-analysisd` | — | Events arrive but no alerts in `alerts.log` |
| Indexing | `wazuh-indexer` | 9200 | Alerts in `alerts.json` but not in web UI |
| Dashboard | `wazuh-dashboard` | 443 | Web UI shows "server is not ready" |

## Diagnosis

### Step 1: Check All Wazuh Services on the Manager

```bash
sudo /var/ossec/bin/wazuh-control status
```

**Problem (authd down):**
```
wazuh-authd not running...
wazuh-remoted is running...
wazuh-analysisd is running...
```

**Problem (remoted down):**
```
wazuh-authd is running...
wazuh-remoted not running...
```

**Working:**
```
wazuh-authd is running...
wazuh-remoted is running...
wazuh-analysisd is running...
wazuh-db is running...
```

### Step 2: Check Network Ports

```bash
sudo ss -tlnp | grep -E "1514|1515|9200"
```

**Problem:**
```
(nothing on 1514 or 1515)
```

**Working:**
```
LISTEN 0 128 0.0.0.0:1514 users:(("wazuh-remoted",pid=1234,fd=5))
LISTEN 0 128 0.0.0.0:1515 users:(("wazuh-authd",pid=1235,fd=3))
LISTEN 0 128 0.0.0.0:9200 users:(("java",pid=1236,fd=200))
```

### Step 3: Check Agent State on Windows

```powershell
# Check if agent service is running
Get-Service -Name WazuhSvc

# Check agent log for connection errors
Get-Content "C:\Program Files (x86)\ossec-agent\ossec.log" -Tail 30

# Test TCP to manager ports
Test-NetConnection -ComputerName 192.168.30.12 -Port 1514
Test-NetConnection -ComputerName 192.168.30.12 -Port 1515
```

### Step 4: Check for Duplicate Agent Entries

```bash
# On manager — check client.keys for duplicates
sudo cat /var/ossec/etc/client.keys

# Check agent database
sudo sqlite3 /var/ossec/queue/db/global.db "SELECT id, name, ip, status FROM agent;"
```

**Problem:**
```
001 WIN-52U4HN70935 any 192.168.30.12
001 WIN-52U4HN70935 any 192.168.30.12
```
(Duplicate entries for the same agent ID)

### Step 5: Verify Alerts Are Being Generated

```bash
# Check if ANY alerts exist (not just custom rules)
sudo tail -n 20 /var/ossec/logs/alerts/alerts.log

# Check JSON alerts (what the indexer reads)
sudo tail -n 5 /var/ossec/logs/alerts/alerts.json

# Check if Sysmon events are reaching the manager at all
sudo tail -n 20 /var/ossec/logs/archives/archives.log 2>/dev/null | grep -i "sysmon\|powershell"
```

### Step 6: Check Indexer and Dashboard Services

```bash
sudo systemctl status wazuh-indexer --no-pager
sudo systemctl status wazuh-dashboard --no-pager
```

**Problem:**
```
wazuh-indexer.service — failed
```

## Fix

### Fix 1: Start Missing Services

If `wazuh-authd` is not running:

```bash
sudo /var/ossec/bin/wazuh-authd
sudo ss -tlnp | grep 1515
```

If `wazuh-indexer` is down:

```bash
sudo systemctl enable wazuh-indexer
sudo systemctl start wazuh-indexer
sleep 30
sudo systemctl status wazuh-indexer --no-pager
```

If `wazuh-dashboard` is down:

```bash
sudo systemctl enable wazuh-dashboard
sudo systemctl start wazuh-dashboard
```

Enable **all** services to start on boot:

```bash
sudo systemctl enable wazuh-manager wazuh-indexer wazuh-dashboard
```

### Fix 2: Remove Duplicate Agent and Re-register

On the **manager**:

```bash
# Remove the agent completely
sudo /var/ossec/bin/manage_agents -r 001

# Verify it's gone
sudo cat /var/ossec/etc/client.keys

# If still there, manually edit
sudo nano /var/ossec/etc/client.keys
# Delete the line with the duplicate agent, save

# Restart manager to clear caches
sudo systemctl restart wazuh-manager
```

On **Windows**:

```powershell
# Stop agent
Stop-Service -Name WazuhSvc

# Remove old keys and state
Remove-Item "C:\Program Files (x86)\ossec-agent\client.keys" -Force
Remove-Item "C:\Program Files (x86)\ossec-agent\ossec-agent.state" -ErrorAction SilentlyContinue

# Re-register
cd "C:\Program Files (x86)\ossec-agent"
.\agent-auth.exe -m 192.168.30.12 -A WIN-52U4HN70935

# Start agent
Start-Service -Name WazuhSvc
```

Wait 30 seconds, then verify on the manager:

```bash
sudo /var/ossec/bin/agent_control -l
```

### Fix 3: Fix "Never Connected" After Successful Registration

If `agent-auth.exe` succeeded but `agent_control -l` shows `Never connected`:

1. **Check remoted is listening:**
   ```bash
   sudo ss -tlnp | grep 1514
   ```

2. **Test from Windows:**
   ```powershell
   Test-NetConnection -ComputerName 192.168.30.12 -Port 1514
   ```

3. **Restart the Windows agent service:**
   ```powershell
   Stop-Service -Name WazuhSvc
   Start-Sleep -Seconds 5
   Start-Service -Name WazuhSvc
   ```

4. **Check Windows agent log for errors:**
   ```powershell
   Get-Content "C:\Program Files (x86)\ossec-agent\ossec.log" -Tail 30
   ```

### Fix 4: Force Indexer to Pick Up New Alerts

If alerts exist in `alerts.json` but the web UI shows nothing:

```bash
# Restart indexer and dashboard
sudo systemctl restart wazuh-indexer
sleep 30
sudo systemctl restart wazuh-dashboard

# Check indexer is actually indexing
sudo curl -k -u admin:admin https://localhost:9200/_cat/indices?v | grep wazuh
```

Also check the time range in the web UI — alerts may be outside the default 24-hour window.

### Fix 5: Full Pipeline Reset (Nuclear Option)

If the agent keeps cycling between `Active` and `Unknown`:

```bash
# On manager — kill everything
sudo systemctl stop wazuh-manager wazuh-indexer wazuh-dashboard
sudo pkill -9 -f wazuh
sudo pkill -9 -f ossec

# Clean stale state
sudo rm -f /var/ossec/var/run/*.pid
sudo rm -f /var/ossec/var/run/*.lock
sudo rm -f /var/ossec/queue/db/wdb
sudo rm -f /var/ossec/queue/agents-tmp/*

# Fix permissions
sudo chown -R wazuh:wazuh /var/ossec

# Start fresh
sudo systemctl start wazuh-manager
sleep 10
sudo systemctl start wazuh-indexer
sleep 30
sudo systemctl start wazuh-dashboard
```

## Verification

| Check | Command | Expected Result |
|-------|---------|----------------|
| All services running | `sudo /var/ossec/bin/wazuh-control status` | All services show `is running` |
| Ports listening | `sudo ss -tlnp \| grep -E "1514\|1515\|9200"` | All three ports listed |
| Agent connected | `sudo /var/ossec/bin/agent_control -l` | Status shows `Active` |
| Alerts generating | `sudo tail -n 5 /var/ossec/logs/alerts/alerts.json` | JSON events with timestamps |
| Web UI ready | `curl -k https://192.168.30.12` | Returns HTML (login page) |
| Custom rules firing | `sudo grep "100001" /var/ossec/logs/alerts/alerts.log` | Alert entries found |

## Lessons Learnt

| Practice | Why |
|----------|-----|
| **Enable all Wazuh services on boot** | `systemctl enable wazuh-manager wazuh-indexer wazuh-dashboard` |
| **Use static manager IP in `ossec.conf`** | Prevents agent confusion if DHCP changes |
| **Never manually edit `client.keys`** | Use `manage_agents` to avoid corruption |
| **Check `wazuh-control status` after any manager reboot** | Catches authd/indexer failures early |
| **Monitor `agent_control -l` after agent reboots** | Detects "Never connected" before testing |



# Splunk Web UI Not Accessible

## Symptoms

- Splunk web UI was accessible at `http://localhost:8080` on Kali before reboot
- After Proxmox host restart, browser shows **"Unable to connect"** or **"Connection refused"**
- Splunk VM is running (`qm status 105` shows `running`)
- `ping 192.168.30.11` from Kali succeeds
- Direct browsing to `http://192.168.30.11:8000` from Kali fails or times out
- `sudo /opt/splunk/bin/splunk status` on Splunk VM shows **"Splunk is not running"**

## Root Cause

Nested virtualization introduces multiple layers where services can stop after a host reboot:

```
My PC
      |
      +-- SSH tunnel: localhost:8080 ──► Kali:22 ──► Splunk:8000
              |
              ▼ (BROKEN after reboot)
      Kali VM (10.0.0.50)
              |
              +-- SSH tunnel process killed by reboot
              |
              +-- OR: Splunk service not auto-started
                      |
                      Splunk VM (192.168.30.11)
                              |
                              +-- Splunk web service on port 8000
```

There are **three independent failure points**:

1. **SSH tunnel on Kali was killed** — tunnels are not persistent across reboots
2. **Splunk service did not auto-start** — may need `enable-boot-start` configuration
3. **Splunk web port not listening** — service started but web component failed

## Diagnosis

### Step 1: Check If Splunk Is Running (On Splunk VM)

SSH into Splunk VM from Proxmox console or Kali:

```bash
sudo /opt/splunk/bin/splunk status
```

**Problem:**
```
Splunk is not running.
```

**Working:**
```
Splunk is running on this machine.
```

### Step 2: Check If Splunk Web Port Is Listening

On Splunk VM:

```bash
sudo ss -tlnp | grep 8000
# or
sudo netstat -tlnp | grep 8000
```

**Problem:**
```
(nothing returned)
```

**Working:**
```
LISTEN 0 128 0.0.0.0:8000 users:(("splunkd",pid=1234,fd=89))
```

### Step 3: Check If SSH Tunnel Exists (On Kali)

```bash
ps aux | grep ssh
ss -tlnp | grep 8080
```

**Problem:**
```
(nothing on port 8080, no ssh tunnel process)
```

**Working:**
```
LISTEN 0 128 127.0.0.1:8080 users:(("ssh",pid=5678,fd=5))
```

### Step 4: Test Direct Connectivity

From Kali:

```bash
ping 192.168.30.11
curl -I http://192.168.30.11:8000
```

If `ping` works but `curl` fails, Splunk web service is down.
If `ping` fails, check network/VLAN routing.

## Fix

### Fix 1: Start Splunk Service (If Not Running)

On Splunk VM:

```bash
sudo /opt/splunk/bin/splunk start
```

To make it auto-start on boot:

```bash
sudo /opt/splunk/bin/splunk enable boot-start
```

Verify:
```bash
sudo /opt/splunk/bin/splunk status
sudo ss -tlnp | grep 8000
```

### Fix 2: Recreate SSH Tunnel (On Kali)

If Splunk is running but you access it via tunnel:

```bash
ssh -L 8080:192.168.30.11:8000 ubuntu@192.168.30.11
```

Keep this terminal open. Then browse on Kali:
```
http://localhost:8080
```

**To run in background:**
```bash
ssh -fN -L 8080:192.168.30.11:8000 ubuntu@192.168.30.11
```

**To kill the tunnel later:**
```bash
ps aux | grep "ssh -fN -L 8080"
kill <PID>
```

### Fix 3: Access Splunk Directly (No Tunnel)

If Kali and Splunk are on the same VLAN or routing is configured:

```bash
# From Kali, test direct access
curl http://192.168.30.11:8000
```

If this works, you can browse directly:
```
http://192.168.30.11:8000
```

If it fails, check:
- pfSense firewall rules allowing MGMT VLAN access
- Splunk `web.conf` binding to `0.0.0.0` not just `127.0.0.1`

### Fix 4: Check Splunk Web Bind Address

On Splunk VM:

```bash
cat /opt/splunk/etc/system/local/web.conf
```

If it contains:
```ini
[settings]
httpport = 8000
mgmtHostPort = 127.0.0.1:8089
```

The web UI should bind to all interfaces by default. If it explicitly says:
```ini
host = 127.0.0.1
```

Change to:
```ini
host = 0.0.0.0
```

Then restart Splunk:
```bash
sudo /opt/splunk/bin/splunk restart
```

## Verification

| Check | Command | Expected Result |
|-------|---------|----------------|
| Splunk running | `sudo /opt/splunk/bin/splunk status` | `Splunk is running` |
| Web port open | `sudo ss -tlnp \| grep 8000` | `0.0.0.0:8000` |
| Tunnel active | `ss -tlnp \| grep 8080` (on Kali) | `127.0.0.1:8080` |
| Web UI loads | `curl http://localhost:8080` (on Kali) | HTML response |

## 

### Make Splunk Auto-Start

```bash
sudo /opt/splunk/bin/splunk enable boot-start
```

### Create a Persistent Tunnel Script on Kali

Save as `~/splunk-tunnel.sh`:

```bash
#!/bin/bash
# Splunk SSH tunnel — run after Kali boots

TUNNEL_PID=$(pgrep -f "ssh.*-L 8080:192.168.30.11:8000")

if [ -n "$TUNNEL_PID" ]; then
    echo "Tunnel already running (PID: $TUNNEL_PID)"
else
    echo "Starting Splunk SSH tunnel..."
    ssh -fN -L 8080:192.168.30.11:8000 ubuntu@192.168.30.11
    echo "Tunnel started. Browse to http://localhost:8080"
fi
```

Make executable:
```bash
chmod +x ~/splunk-tunnel.sh
```

Run after each reboot:
```bash
~/splunk-tunnel.sh
```

### Alternative: Use Proxmox Port Forwarding

Instead of SSH tunnels, configure pfSense or Proxmox to forward a port directly to Splunk:

**pfSense:**
- Firewall → NAT → Port Forward
- Interface: WAN (or LAN)
- Protocol: TCP
- Destination: WAN address
- Destination Port: 8000
- Redirect Target IP: 192.168.30.11
- Redirect Target Port: 8000

Then access from my PC directly:
```
http://<pfSense-LAN-IP>:8000
```

