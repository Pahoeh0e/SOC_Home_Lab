# Configuration Troubleshooting








# VM Network Adapter: E1000 vs VirtIO — Windows Doesn't See Network Card

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

### Option A: Switch to E1000 (Recommended for Install / Lab)

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

### Option C: Change Both Disk AND Network to IDE/E1000 (Skip VirtIO Entirely)

For a lab where you want zero driver hassle:

| Device | Change To |
|--------|-----------|
| Hard Disk | `IDE` or `SATA` |
| CD/DVD Drive | `IDE` (default) |
| Network | `Intel E1000` |

**Trade-off:** ~5-10% performance loss vs VirtIO, but saves 30+ minutes of driver wrangling.

## Verification

### In Windows

```cmd
ipconfig /all
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

## Prevention

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

## Related Issues

- [ ] [pfSense WAN Gets `192.168.122.x`](network-pfsense-wan-libvirt-nat.md) — network adapter type must be correct before IP assignment matters
- [ ] Windows installer says **"No drives found"** — same VirtIO driver issue, but for the disk controller; change disk bus to IDE or load VirtIO storage drivers
