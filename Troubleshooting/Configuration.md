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
- [VM Network bridge](#VM-Network-Bridge-not-working)
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

### Proxmox VM Creation Checklist

When creating a Windows VM in Proxmox, set:

- [ ] **System → Machine:** `i440fx` or `q35`
- [ ] **Disks → Bus/Device:** `IDE` or `SATA` (for install) / `VirtIO Block` (if loading drivers)
- [ ] **Network → Model:** `Intel E1000` (for install) / `VirtIO` (after driver install)
- [ ] **Network → Firewall:** ❌ Unchecked (pfSense handles security)


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

## Lessons Learnt

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

