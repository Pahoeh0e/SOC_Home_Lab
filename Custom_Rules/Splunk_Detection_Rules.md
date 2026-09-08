# Splunk Detection Rules

All rules map to MITRE ATT&CK and include testing procedures.

---

## DET-001: Port Scan Detection

### MITRE Mapping
- **Technique**: T1046 — Network Service Scanning
- **Tactic**: Reconnaissance

```
index=snort OR index=firewall earliest=-5m
| stats dc(dest_port) as unique_ports, count as event_count by src_ip
| where unique_ports > 10
| eval severity=case(unique_ports>100,"Critical",unique_ports>50,"High",1=1,"Medium")
| eval mitre_technique="T1046"
| table _time, src_ip, unique_ports, event_count, severity, mitre_technique
| sort - unique_ports

```



## DET-002: Brute Force Authentication

### MITRE Mapping
- **Technique**: T1110 — Brute Force
- **Sub-technique**: T1110.001 — Local Brute Force
- **Tactic**: Initial Access

```
index=winsec EventCode=4625 earliest=-15m
| stats count as failed_attempts, values(Account_Name) as targeted_accounts by src_ip, dest
| where failed_attempts >= 5
| eval severity=case(failed_attempts>=20,"Critical",failed_attempts>=10,"High",1=1,"Medium")
| eval mitre_technique="T1110"
| table _time, src_ip, dest, failed_attempts, targeted_accounts, severity, mitre_technique

```


## DET-003: Suspicious PowerShell Execution

### MITRE Mapping
- **Technique**: T1059.001 — PowerShell
- **Tactic**: Execution

```
index=sysmon EventCode=1 earliest=-1h
(
    CommandLine="* -enc *" OR 
    CommandLine="* -encodedcommand *" OR 
    CommandLine="*IEX*" OR 
    CommandLine="*Invoke-Expression*" OR
    CommandLine="*DownloadString*" OR
    CommandLine="*bitsadmin*"
)
| eval severity="Critical"
| eval mitre_technique="T1059.001"
| table _time, Computer, User, Image, CommandLine, severity, mitre_technique
| sort - _time
```

## DET-004: Lateral Movement (PsExec)

### MITRE Mapping
- **Technique**: T1021.002 — Remote Services: SMB/Windows Admin Shares
- **Tactic**: Lateral Movement


```
index=sysmon EventCode=1 earliest=-1h
(Image="*\\psexec.exe" OR Image="*\\psexesvc.exe" OR CommandLine="*\\admin$*")
OR
index=winsec EventCode=7045 ServiceName="PSEXESVC"
| eval severity="High"
| eval mitre_technique="T1021.002"
| table _time, Computer, User, Image, CommandLine, ServiceName, severity, mitre_technique

```


## DET-005: C2 Beaconing Detection

### MITRE Mapping
- **Technique**: T1071 — Application Layer Protocol
- **Tactic**: Command and Control


```
index=sysmon EventCode=3 earliest=-4h
| eval dest_ip=DestinationIp
| where NOT match(dest_ip, "^10\.0\.")
| bin _time span=5m
| stats dc(_time) as beacon_intervals, values(dest_ip) as dest_ips, count as conn_count by Computer, Image, dest_port
| eventstats avg(conn_count) as avg_conn, stdev(conn_count) as stdev_conn by Computer
| eval is_beacon=if(conn_count > avg_conn + (2 * stdev_conn) AND beacon_intervals > 5, "Yes", "No")
| where is_beacon="Yes"
| eval severity="High", mitre_technique="T1071"
| table _time, Computer, Image, dest_ips, dest_port, conn_count, beacon_intervals, severity, mitre_technique
```


## DET-006: Credential Dumping (Mimikatz)

### MITRE Mapping
- **Technique**: T1003 — OS Credential Dumping
- **Tactic**: Credential Access

```

index=sysmon EventCode=10 earliest=-1h
(
    TargetImage="*\\lsass.exe" OR
    CallTrace="*dbghelp.dll*" OR
    CallTrace="*dbgcore.dll*"
)
OR
index=sysmon EventCode=7 ImageLoaded="*\\samlib.dll"
| eval severity="Critical"
| eval mitre_technique="T1003.001"
| table _time, Computer, User, SourceImage, TargetImage, CallTrace, severity, mitre_technique

```


## DET-007: Persistence via Registry Run Keys
### MITRE Mapping
- **Technique**: T1547.001 — Registry Run Keys / Startup Folder
- **Tactic**: Persistence


```
index=sysmon EventCode=13 earliest=-1h
(
    TargetObject="*\\Software\\Microsoft\\Windows\\CurrentVersion\\Run*" OR
    TargetObject="*\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce*"
)
| eval severity="Medium"
| eval mitre_technique="T1547.001"
| table _time, Computer, User, TargetObject, Details, severity, mitre_technique
```


## DET-008: Data Exfiltration
### MITRE Mapping
- **Technique**: T1041 — Exfiltration Over C2 Channel
- **Tactic**: Exfiltration


```
index=firewall earliest=-1h
| stats sum(bytes_out) as total_out, sum(bytes_in) as total_in by src_ip, dest_ip
| eval ratio=total_out/total_in
| where total_out > 104857600 AND ratio > 10
| eval severity="High"
| eval mitre_technique="T1041"
| table _time, src_ip, dest_ip, total_out, total_in, ratio, severity, mitre_technique

```
## DET-008: Detect Web Server User Spawning a Shell
### MITRE Mapping
- **Technique**: T1059 & T1505.003 - Command execution and web server process executing shell commands indicates a possible web shell
- **Tactic**: Execution & Persistence


```

index=os OR index=linux_audit earliest=-5m
| search user="www-data" OR user="apache" OR user="nginx"
| stats count as shell_spawns by host, user, process
| where match(process, "(bash|sh)$")
| eval severity="Critical"
| eval mitre_technique="T1059"
| eval mitre_subtechnique="T1505.003"
| table _time, host, user, process, shell_spawns, severity, mitre_technique, mitre_subtechnique
| sort - shell_spawns

```
