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
-    Static IP: 192.168.20.10/24


## Security Monitoring:

-   Snort host-based IDS installed directly on DMZ web server
-   Community rules + custom local rules for:
-   ICMP ping detection
-   SQL injection attempts
-   Directory traversal
-   Cross-site scripting (XSS)
-   Real-time alert output to alert.fast
