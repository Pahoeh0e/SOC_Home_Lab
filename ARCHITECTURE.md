# Network Architecture: Multi-VLAN Segmented Lab


### Firewall VLAN interfaces on a single physical NIC (router-on-a-stick):

-   vtnet1.10 — LAN (10.0.0.0/24)
-   vtnet1.20 — DMZ (192.168.20.0/24)
-   vtnet1.30 — MGMT (192.168.30.0/24)

### pfSense Firewall Configuration:

- WAN Interface: DHCP from home router, double-NAT lab setup
- LAN Interface: Static 10.0.0.1/24 with DHCP server (range: 10.0.0.100-200)
- Security Policy: Default-deny WAN policy with explicit HTTPS allow rule for management access
- Key Lesson: The "Block private networks" rule blocked my own laptop because WAN is RFC1918 behind a home router. Fixed by adding a specific source IP allow rule.


### Firewall Policy: 

-   Default-deny with explicit allow rules
-   DMZ blocked from initiating to LAN and MGMT
-   LAN allowed to reach DMZ services
-   Outbound NAT configured for internet access from all internal networks


### DMZ Infrastructure:

-    Ubuntu Server 24.04 (minimised) web server
-    Nginx serving a custom landing page

## Initial setup:
-   Ubuntu Server 24.04 (minimised) web server
-   Finalised Snort configuration with working alert generation
-   Verified detection of port scans, SQL injection, directory traversal, and XSS
-   Enabled Snort as a system service for persistent monitoring

## Validated Network Security Controls:
-   Confirmed DMZ isolation: blocked from LAN (10.0.0.0/24) and MGMT (192.168.30.0/24)
-   Verified LAN-to-DMZ access for legitimate web traffic
-   Tested outbound internet access from DMZ for updates


## Attack & Detection Workflow
-   Kali Linux (LAN) → nmap port scan → Snort alert: port scan detected
-   Kali Linux (LAN) → curl SQL injection → Snort alert: SQL injection attempt
-   Kali Linux (LAN) → curl directory traversal → Snort alert: traversal attempt
-   Kali Linux (LAN) → curl XSS payload → Snort alert: XSS attempt


## Skills Demonstrated:

-    Network segmentation (VLANs)	802.1q VLANs on Proxmox with pfSense routing
-    Firewall policy design	Default-deny, explicit allow, inter-zone blocking
-    NAT configuration	Outbound NAT for multiple internal networks
-    Host-based intrusion detection	Snort on DMZ server with custom rules
-    Threat simulation	Kali Linux reconnaissance and web attacks
-    Troubleshooting	Systematic diagnosis of routing, DNS, and service issues
-    Documentation	Network diagrams, alert logs


## Security Monitoring:

-   Snort host-based IDS installed directly on DMZ web server
-   Community rules + custom local rules for:
-   ICMP ping detection
-   SQL injection attempts
-   Directory traversal
-   Cross-site scripting (XSS)
-   Real-time alert output to alert.fast
