# Network Troubleshooting 

See [Network Architecture](ARCHITECTURE.md) for the full architecture 

## Format

Each guide follows the same structure:
- **What went wrong** — Symptomshat you see when the issue occurs
- **The Problem** — why it happens
- **How I Figured It Out** — commands and checks to confirm
- **Fix/Fixes** — step-by-step resolution
- **How to Check It's Working** - Confirming the fix works
- **lessons learnt** — how to avoid it next time

## Index:
- [pfSense Web UI access](#Accessing-pfSense-Web-UI) 
- [Proxmox pool storage](#Proxmox-Storage)


# Accessing pfSense Web UI

**Category:** Network / VM Setup  
**Lab Context:** Setting up pfSense firewall inside Proxmox  
**Applies To:** Proxmox running as a VM inside QEMU/KVM

---

## What Went Wrong

I installed pfSense and expected to open a browser on my laptop and go to the web UI. Instead I got "Unable to connect." I checked the pfSense console and saw the WAN IP was `192.168.122.something` — but my laptop is on `192.168.1.something`. They were on completely different networks. My laptop had no way to reach pfSense.

I also couldn't install packages during the pfSense setup because it had no internet access.

---

## The Problem

When I created the Proxmox VM in virt-manager, I left the network on the default setting: **NAT**. This puts Proxmox (and therefore pfSense) on an isolated network (`192.168.122.x`) that my home router knows nothing about. My laptop is on my home LAN (`192.168.1.x`) and has no route to that other network.

Think of it like this: pfSense was sitting in a room with a locked door, and my laptop was in a different building.

---

## How I Figured It Out

**On Proxmox:**
```bash
ip addr show vmbr0
```

It showed:
```
inet 192.168.122.42/24
```

That `122` subnet is the giveaway. It means NAT mode. It should have been `192.168.1.something` — the same subnet as my laptop.

**On the pfSense console:**
```
WAN (vtnet0) -> v4/DHCP4: 192.168.122.x/24
```

That confirmed it. pfSense got its IP from the virtual NAT network, not from my home router.

---

## The Fix

I needed to change the Proxmox VM's network from NAT to **MacVTap** (also called bridged mode). This lets Proxmox connect directly to my physical network and get an IP from my home router, just like my laptop does.

1. **Shut down the Proxmox VM** in virt-manager
2. Right-click the VM → **Open**
3. Click the **lightbulb icon** (hardware details)
4. Click **NIC**
5. Change **Network source** from `Virtual network 'default': NAT` to **`MacVTap device...`**
6. Pick your wired network interface (e.g., `eno1`, `eth0`)
7. Click **Apply**
8. Start the VM

After it boots, check the IP:
```bash
ip addr show vmbr0
```

Now it should show `192.168.1.x` — matching your home network.

**Note:** MacVTap doesn't always work with WiFi. If you're on WiFi and this fails, try plugging in an Ethernet cable or use the workaround below.

---

## The Quick Workaround (If You Can't Change the Network)

If MacVTap isn't an option, you can access pfSense from the Linux host itself — because the host IS on that `192.168.122.x` network.

On your Linux host:
```bash
firefox https://192.168.122.x/
```

Replace `192.168.122.x` with whatever IP the pfSense console shows.

Or forward the port through an SSH tunnel:
```bash
ssh -L 8443:192.168.122.x:8443 user@your-laptop-ip
```

Then on your laptop browse to:
```
https://localhost:8443/
```

---

## How to Check It's Working

1. **Proxmox IP:** `ip addr show vmbr0` should show `192.168.1.x/24`
2. **pfSense WAN:** Console should show `192.168.1.x/24`
3. **From laptop:** `ping <pfSense-IP>` should reply
4. **Browser:** `https://<pfSense-IP>:8443/` should show the login page

---

## Lessons Learned

- **NAT is the default in virt-manager, but it's wrong for this use case.** NAT isolates your VM. For a firewall that needs to be reachable from your LAN, you need bridged/MacVTap mode.
- **Check the IP before you troubleshoot anything else.** If the first three octets don't match your home network, that's the problem.
- **WiFi and MacVTap don't always get along.** If you're on WiFi, keep an Ethernet adapter handy for lab work.
- **The workaround works in a pinch.** SSH tunnels aren't pretty, but they'll get you into the web UI while you figure out the proper fix.



# Proxmox Storage

**Category:** Storage / Proxmox  
**Lab Context:** Running multiple VMs, suddenly can't create new ones  
**Applies To:** Proxmox running as a VM inside QEMU/KVM

---

## What Went Wrong

I tried to create a new VM and Proxmox said "no space left on device." I checked and the thin pool was at 100%. But I had given the Proxmox VM a 272 GB virtual disk — so where did all the space go?

It turned out Proxmox could only see about 72 GB of that disk. The rest was just sitting there unused. On top of that, I had promised more disk space to my VMs than Proxmox actually had available (thin provisioning), so when they all started writing data, the pool filled up and things started breaking. My pfSense VM even got corrupted and wouldn't boot.



---

## The Problem

Two things were happening at once:

1. **Proxmox only saw part of the disk.** The virtual disk file was 272 GB, but the partition inside Proxmox was only ~72 GB. The rest was unallocated.

2. **Thin provisioning let me over-promise.** I told my VMs they could have 80 GB total, but Proxmox only had ~72 GB. When the VMs actually used that much space, the pool ran dry.

---

## How I Figured It Out

**On Proxmox:**
```bash
vgs
```

Showed:
```
  VG  #PV #LV #SN Attr   VSize   VFree
  pve   1   4   0 wz--n-  71.50g 8.88g
```

Only 71 GB total — but my virtual disk was 272 GB.

**Then:**
```bash
lvs
```

Showed:
```
  LV    VG  Attr       LSize   Pool Origin Data%  Meta%
  data  pve twi-aotz--  24.75g             100.00  43.12
```
![vgs](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-06-14%2013-50-37.png)
![snapshot](https://github.com/Pahoeh0e/SOC_Home_Lab/blob/main/Operations/Screenshots/Screenshot%20from%202026-07-02%2018-28-37.png)

The thin pool was at 100%. That's why nothing could write.

**On the Linux host (where QEMU runs):**
```bash
qemu-img info /var/lib/libvirt/images/pve.soc.lab.qcow2
```

Showed `virtual size: 272 GiB` — so the space existed, Proxmox just couldn't use it.

---

## The Fix

### Step 1 — Make Proxmox see the full disk

On the **Linux host**, check if the virtual disk is already big:
```bash
qemu-img info /var/lib/libvirt/images/pve.soc.lab.qcow2
```

If it's small, resize it:
```bash
qemu-img resize /var/lib/libvirt/images/pve.soc.lab.qcow2 +200G
```

Then **reboot Proxmox** so it sees the new space.

### Step 2 — Grow the partition inside Proxmox

On **Proxmox**:
```bash
apt install cloud-guest-utils
growpart /dev/vda 3
```

This expands partition 3 to fill the rest of the disk.

### Step 3 — Resize the storage pool

```bash
pvresize /dev/vda3
lvextend -l +100%FREE /dev/pve/data
```

Now Proxmox can actually use all the space.

### The Lazy Way

If you're feeling confident, it's just one line:
```bash
growpart /dev/vda 3 && pvresize /dev/vda3 && lvextend -l +100%FREE /dev/pve/data && vgs
```

---

## How to Check It's Working

```bash
vgs
```

Should now show something like:
```
  VG  #PV #LV #SN Attr   VSize    VFree
  pve   1   4   0 wz--n- 271.50g 220.00g
```

And:
```bash
lvs
```

The `data` pool should show `Data%` well under 100%.

Try creating a test VM:
```bash
qm create 999 --name test-vm --memory 512 --cores 1 --virtio0 local-lvm:10
qm destroy 999
```

If that works, you're good.

---

## If a VM Got Corrupted

My pfSense VM broke because the pool ran out while it was writing. ZFS corruption from that is usually not fixable.

1. **Fix the storage first** using the steps above
2. **Rebuild the broken VM from ISO** — don't waste time trying to recover a corrupted thin pool VM
3. **Only restore from backup after** you've confirmed the pool is stable

```bash
# Example: rebuild pfSense
qm destroy 100
qm create 100 --name pfsense-firewall --memory 1024 --cores 1 \
  --net0 virtio,bridge=vmbr0 --net1 virtio,bridge=vmbr1 \
  --virtio0 local-lvm:16
# Attach ISO and reinstall
```

---

## Lessons Learned

- **Give Proxmox way more disk than you think you need.** I started with too small a virtual disk. For a multi-VM lab, allocate 250–300 GB from the start.
- **Thin provisioning is a trap if you don't watch it.** It lets you over-allocate, which is fine until everyone actually uses their space. Check `lvs` regularly.
- **A full pool corrupts VMs.** Don't ignore warnings. When `local-lvm` gets above 80%, do something about it.
- **Don't hard-reboot VMs when storage is full.** I force-restarted pfSense while the pool was at 100% and that killed it. Fix storage first, then reboot VMs.
- **The virtual disk size and the usable size are different things.** Just because QEMU says 272 GB doesn't mean Proxmox can use it. You have to grow the partition and the pool.

### Disk Sizes That Work for Me Now

| VM | Disk | Notes |
|----|------|-------|
| pfSense | 16 GB | Keep small, easy to rebuild |
| Kali Linux | 32 GB | Trimmed down from default |
| Windows Server | 25 GB | Enough for a DC |
| Windows 10 | 25 GB | Lab workstation |
| Splunk | 40 GB | Logs grow fast |
| Wazuh | 40 GB | Indexer needs room |
| **Total** | **~176 GB** | Comfortable in 250–300 GB |


