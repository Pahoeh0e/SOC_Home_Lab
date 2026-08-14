# Network Troubleshooting 

See [Network Architecture](ARCHITECTURE.md) for the full architecture 

# Format

Each guide follows the same structure:
- **Symptoms** — what you see when the issue occurs
- **Root Cause** — why it happens
- **Diagnosis** — commands and checks to confirm
- **Fix** — step-by-step resolution
- **lessons learnt** — how to avoid it next time


Index:
- [pfSense Web UI access](#Accessing-pfSense-Web-UI) 
- [Proxmox pool storage](#Proxmox-Storage)


# Accessing pfSense Web UI

## Symptoms

- pfSense console shows WAN IP as `192.168.122.x/24` instead of your home network (e.g., `192.168.1.x/24`)
- Proxmox host also has IP `192.168.122.x` on `vmbr0`
- Your laptop (on `192.168.1.x`) cannot ping or browse to the pfSense web UI
- pfSense installation may fail at package fetch (68/182) because it cannot reach the internet
- From Proxmox, `ping 8.8.8.8` fails

## Root Cause

Your Proxmox VM (running nested inside QEMU/KVM on your Linux host) is attached to **libvirt's default NAT network** (`virbr0`, `192.168.122.0/24`) instead of being bridged to your physical network interface. This creates a double-NAT situation:

```
Laptop (192.168.1.x)  --X-->  Proxmox (192.168.122.x)  -->  pfSense WAN (192.168.122.x)
       Home LAN                    Libvirt NAT                     No internet
```

pfSense gets its WAN IP from libvirt's internal DHCP server, not from your home router. Your laptop is on a completely different subnet with no route to `192.168.122.0/24`.

## Diagnosis

### On Proxmox

```bash
ip addr show vmbr0
```

**Bad output:**
```
inet 192.168.122.42/24 brd 192.168.122.255
```

**Good output:**
```
inet 192.168.1.x/24 brd 192.168.1.255
```

### On pfSense Console

```
WAN (vtnet0) -> v4/DHCP4: 192.168.122.x/24
```

**Should be:** `192.168.1.x/24` (or whatever your home router subnet is)

### On Your Laptop

**Windows:**
```cmd
ipconfig
```

**Linux/Mac:**
```bash
ip addr show
```

Confirmed my PC is on a different subnet (e.g., `192.168.1.x`) than Proxmox/pfSense.

## Fix

### Option 1: Change QEMU/virt-manager Network to MacVTap (Recommended)

This gives Proxmox a direct layer-2 connection to your physical network, so it gets an IP from your home router just like any other device.

1. **Shut down the Proxmox VM** from virt-manager
2. Open **virt-manager** → right-click your Proxmox VM → **Open**
3. Click the **lightbulb icon** (Show virtual hardware details)
4. Click **NIC** (network interface)
5. Change **Network source** from `Virtual network 'default': NAT` to **MacVTap device...**
6. Select your physical interface:
   - Wired: `eno1`, `ens33`, `eth0`, `enp3s0`, etc.
   - **Note:** WiFi interfaces (`wlp5s0`, etc.) often do not work with MacVTap due to wireless limitations
7. Click **Apply**
8. Start Proxmox VM
9. Verify: `ip addr show vmbr0` should now show `192.168.1.x`

### Option 2: Create a Linux Bridge on Your Host

If MacVTap is unavailable or you need multiple VMs on the same network:

```bash
# Find your physical interface
ip link show

# Create bridge (replace eno1 with your interface)
sudo ip link add name br0 type bridge
sudo ip link set br0 up
sudo ip link set eno1 master br0

# In virt-manager, set NIC Network source to: Bridge 'br0'
```

**Note:** You may lose host network connectivity until you assign an IP to `br0` instead of the physical interface.

### Option 3: Access pfSense From the Linux Host (Quick Workaround)

Since your Linux host IS on `192.168.122.0/24` (libvirt adds it to that network), you can access pfSense directly from the host without changing any network settings.

```bash
# On your Linux host, open a browser
firefox https://192.168.122.x/
# Replace 192.168.122.x with pfSense's actual WAN IP
```

Or use an SSH tunnel to forward pfSense to your laptop:

```bash
# On Linux host
ssh -L 8443:192.168.122.x:8443 user@your-laptop-ip
```

Then on laptop: `https://localhost:8443/`

### Option 4: Port Forward from Host to pfSense

Forward host port 8443 to pfSense's web UI:

```bash
# Replace 192.168.122.x with pfSense's actual WAN IP
sudo iptables -t nat -A PREROUTING -p tcp --dport 8443 -j DNAT --to-destination 192.168.122.x:8443
sudo iptables -t nat -A POSTROUTING -j MASQUERADE
```

Access from laptop:
```
https://<LINUX-HOST-IP>:8443/
```

## Verification

After applying Option 1 or 2:

1. On Proxmox:
   ```bash
   ip addr show vmbr0
   ```
   Should show `192.168.1.x/24` (home network)

2. On pfSense console:
   ```
   WAN (vtnet0) -> v4/DHCP4: 192.168.1.x/24
   ```

3. From your laptop:
   ```bash
   ping <pfSense-WAN-IP>
   ```
   Should reply successfully.

4. Browse to:
   ```
   https://<pfSense-WAN-IP>:8443/
   ```
   Should load the pfSense login page.

## Prevention

When creating the Proxmox VM in virt-manager for the first time, always set the network to bridge/MacVTap mode instead of the default NAT:

| Setting | Wrong | Right |
|---------|-------|-------|
| Network source | `Virtual network 'default': NAT` | `MacVTap device 'eno1'` or `Bridge 'br0'` |
| Result | `192.168.122.x` — isolated | `192.168.1.x` — on home LAN |

If you are on **WiFi only** and MacVTap does not work with your wireless card, consider:
- Using a USB-to-Ethernet adapter for the Linux host
- Creating a routed network in libvirt instead of NAT
- Using Option 3/4 as a permanent workaround

## Related Issues

- [ ] pfSense install fails at package fetch (68/182) — caused by no internet access due to this NAT issue
- [ ] Proxmox cannot reach internet for updates — same root cause
- [ ] Cannot access Proxmox web UI from laptop — Proxmox is also on `192.168.122.x`



# Proxmox Storage

## Symptoms

- Cannot create new VMs: "unable to create swap volume" or "no space left on device"
- `vgs` shows `VG pve` with very little or no free space (e.g., `8.88G` free on `71.50G` total)
- `lvs` shows thin pool `data` at 100% full
- Warning: "Sum of all thin volume sizes (80.00 GiB) exceeds size of thin pool"
- Existing VMs crash or fail to write: pfSense shows `ZFS error 5`, `mounting from zfs:pfsense/root/default failed`
- `qemu-img info` on the Proxmox VM disk file shows `virtual size: 272 GiB` but `disk size: 53 GiB` — the virtual disk is large but the filesystem inside hasn't been expanded

## Root Cause

Your Proxmox VM (nested inside QEMU) was created with a virtual disk that is larger than what Proxmox's LVM thin pool was configured to use during installation. The underlying QEMU disk file has plenty of virtual space, but Proxmox only allocated ~72 GB to its LVM physical volume (`/dev/vda3`), leaving the rest of the virtual disk unclaimed.

Additionally, thin provisioning allowed you to over-allocate VM disk space (promising 80 GB+ to VMs on ~72 GB of real backing space). When VMs actually wrote enough data to fill the pool, writes failed — causing filesystem corruption in ZFS-based VMs like pfSense.

```
QEMU virtual disk file: 272 GB
    |
    +-- /dev/vda3 partition: 71.5 GB (what Proxmox sees)
            |
            +-- VG pve: 71.5 GB
                    |
                    +-- Thin pool data: ~24 GB (over-provisioned)
                            |
                            +-- VM disks: 80 GB promised -> pool runs out
```

## Diagnosis

### On Proxmox

```bash
vgs
```

**Bad output:**
```
  VG  #PV #LV #SN Attr   VSize   VFree
  pve   1   4   0 wz--n-  71.50g 8.88g
```

**Good output:**
```
  VG  #PV #LV #SN Attr   VSize    VFree
  pve   1   4   0 wz--n- 271.50g 220.00g
```

```bash
lvs
```

**Bad output:**
```
  LV    VG  Attr       LSize   Pool Origin Data%  Meta%
  data  pve twi-aotz--  24.75g             100.00  43.12
```

```bash
pvesm status
```

Shows `local-lvm` at or near 100% usage.

### On QEMU Host (Linux)

```bash
qemu-img info /var/lib/libvirt/images/pve.soc.lab.qcow2
```

Shows `virtual size: 272 GiB` but Proxmox only sees a fraction of it.

## Fix

### Step 1: Confirm the QEMU Disk File Has Free Virtual Space

On your **Linux host** (where QEMU runs):

```bash
qemu-img info /var/lib/libvirt/images/pve.soc.lab.qcow2
```

If `virtual size` is already large (e.g., 272 GB), skip to Step 3.

If `virtual size` is small (e.g., 72 GB), resize it first:

```bash
qemu-img resize /var/lib/libvirt/images/pve.soc.lab.qcow2 +200G
```

### Step 2: Reboot Proxmox VM

After resizing the disk file, reboot Proxmox so it sees the new space:

```bash
virsh reboot pve.soc.lab
# or
qm reboot <proxmox-vm-id>
```

### Step 3: Expand the Partition Inside Proxmox

On Proxmox:

```bash
# Check current partition layout
fdisk -l /dev/vda
```

You should see `/dev/vda3` with the old size and free space after it.

```bash
# Install growpart if not present
apt install cloud-guest-utils

# Grow partition 3 to fill remaining space
growpart /dev/vda 3
```

**Alternative using fdisk manually:**
```bash
fdisk /dev/vda
# d -> 3 (delete partition 3)
# n -> 3 (new partition 3, same start sector, use all remaining space)
# t -> 3 -> 8e (Linux LVM)
# w (write and exit)
```

### Step 4: Resize LVM Physical Volume

```bash
pvresize /dev/vda3
pvs
```

`PSize` for `/dev/vda3` should now show ~271 GB.

### Step 5: Expand the Thin Pool

```bash
lvextend -l +100%FREE /dev/pve/data
lvs
```

Thin pool `data` should now have significant free space.

### One-Liner (If You're Feeling Lucky)

```bash
growpart /dev/vda 3 && pvresize /dev/vda3 && lvextend -l +100%FREE /dev/pve/data && vgs
```

## Verification

```bash
vgs
```

Expected:
```
  VG  #PV #LV #SN Attr   VSize    VFree
  pve   1   4   0 wz--n- 271.50g 220.00g
```

```bash
lvs
```

Expected: `data` pool `Data%` should be well under 100%.

```bash
pvesm status
```

Expected: `local-lvm` shows plenty of available space.

Try creating a test VM to confirm:
```bash
qm create 999 --name test-vm --memory 512 --cores 1 --virtio0 local-lvm:10
qm destroy 999
```

## Prevention

| Mistake | Fix |
|---------|-----|
| Creating QEMU VM with small disk | Allocate 250 GB+ from the start for a multi-VM lab |
| Over-provisioning thin pool | Monitor `lvs` Data% regularly; don't promise more than you have |
| Ignoring thin pool warnings | Set up Proxmox alerts when `local-lvm` exceeds 80% |
| Force-stopping VMs when pool is full | Always check storage before hard-rebooting VMs — full pools cause corruption |

### Recommended Disk Sizes for SOC Lab

| VM | Disk | Notes |
|----|------|-------|
| pfSense | 16 GB | Keep small, reinstall if corrupted |
| Kali Linux | 32 GB | Can shrink from default 64 GB |
| Windows Server (DC01) | 25 GB | Trimmed down |
| Windows 10 (WKST01) | 25 GB | Lab workstation |
| Splunk Enterprise | 40 GB | Logs grow fast |
| Wazuh SIEM | 40 GB | If using instead of/in addition to Splunk |
| **Total** | **~176 GB** | Fits comfortably in 250-300 GB |

## Recovery: If ZFS Corruption Already Occurred

If a VM (like pfSense) was corrupted due to the full pool:

1. **Fix the storage first** using the steps above
2. **Rebuild the corrupted VM from ISO** — ZFS corruption from failed writes is usually unrecoverable
3. **Do not restore from backup** until you are certain the pool has stable free space

```bash
# Example: rebuild pfSense
qm destroy 100
qm create 100 --name pfsense-firewall --memory 1024 --cores 1 \
  --net0 virtio,bridge=vmbr0 --net1 virtio,bridge=vmbr1 \
  --virtio0 local-lvm:16
# Attach ISO and reinstall
```

## Related Issues

- [ ] [pfSense WAN Gets `192.168.122.x`](network-pfsense-wan-libvirt-nat.md) — may occur while troubleshooting storage if network settings are changed
- [ ] Windows Server install fails with "No drives found" — can happen if thin pool is too full to allocate VM disk


