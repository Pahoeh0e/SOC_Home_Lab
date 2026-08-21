# Detection Rules

All rules map to MITRE ATT&CK and include testing procedures.

---

## DET-001: Port Scan Detection

### MITRE Mapping
- **Technique**: T1046 — Network Service Scanning
- **Tactic**: Reconnaissance

### Snort Rule (DMZ Sensor)
```snort
alert tcp any any -&gt; $HOME_NET any (
    msg:"SOC-LAB Port Scan Detected"; 
    flags:S; 
    threshold:type both, track by_src, count 20, seconds 10; 
    sid:1000001; 
    rev:1;
)

```
### Splunk SPL 
```
index=snort OR index=firewall earliest=-5m
| stats dc(dest_port) as unique_ports, count as event_count by src_ip
| where unique_ports > 10
| eval severity=case(unique_ports>100,"Critical",unique_ports>50,"High",1=1,"Medium")
| eval mitre_technique="T1046"
| table _time, src_ip, unique_ports, event_count, severity, mitre_technique
| sort - unique_ports

```
### Wazuh Rule 
```
<group name="portscan,reconnaissance,">
  <rule id="100001" level="10" frequency="20" timeframe="10">
    <if_matched_sid>5710</if_matched_sid>
    <same_source_ip />
    <description>Multiple connection attempts from $(srcip) - possible port scan</description>
    <mitre>
      <id>T1046</id>
    </mitre>
    <group>portscan,reconnaissance,</group>
  </rule>
</group>

```

Testing (INSERT EVIDENCE)


## DET-002: Brute Force Authentication

### MITRE Mapping
- **Technique**: T1110 — Brute Force
- **Sub-technique**: T1110.001 — Local Brute Force
- **Tactic**: Initial Access

### Snort Rule (DMZ Sensor)

```
alert tcp any any -> $HOME_NET 3389 (
    msg:"SOC-LAB RDP Brute Force Detected";
    flow:established,to_server;
    content:"|03 00|"; depth:2;
    detection_filter:track by_src, count 5, seconds 60;
    sid:1000002;
    rev:1;
)
```
### Splunk SPL 
```
index=winsec EventCode=4625 earliest=-15m
| stats count as failed_attempts, values(Account_Name) as targeted_accounts by src_ip, dest
| where failed_attempts >= 5
| eval severity=case(failed_attempts>=20,"Critical",failed_attempts>=10,"High",1=1,"Medium")
| eval mitre_technique="T1110"
| table _time, src_ip, dest, failed_attempts, targeted_accounts, severity, mitre_technique

```

### Wazuh Rule 

```
<group name="windows,authentication,brute_force,">
  <rule id="100002" level="12" frequency="5" timeframe="300">
    <if_matched_sid>60122</if_matched_sid>
    <same_source_ip />
    <description>Multiple failed RDP logins from $(srcip) - possible brute force attack</description>
    <mitre>
      <id>T1110</id>
    </mitre>
    <group>authentication_failures,brute_force,</group>
  </rule>
</group>

```

Testing (INSERT EVIDENCE)

## DET-003: Suspicious PowerShell Execution

### MITRE Mapping
- **Technique**: T1059.001 — PowerShell
- **Tactic**: Execution

### Snort Rule (DMZ Sensor)
```
alert tcp $HOME_NET any -> $EXTERNAL_NET any (
    msg:"SOC-LAB Suspicious Outbound PowerShell/C2 Traffic";
    flow:established,to_server;
    content:"powershell"; http_header; nocase;
    sid:1000003;
    rev:1;
)

alert tcp $HOME_NET any -> $EXTERNAL_NET any (
    msg:"SOC-LAB Encoded Command in HTTP POST";
    flow:established,to_server;
    content:"POST"; http_method;
    content:"-enc"; http_client_body; nocase;
    sid:1000004;
    rev:1;
)
```
### Splunk SPL 
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
### Wazuh Rule 
```
<group name="sysmon,powershell,">
  <rule id="100003" level="13">
    <if_sid>92010</if_sid>
    <field name="win.eventdata.CommandLine">(?i)(-enc\s|-encodedcommand\s|iex\s|invoke-expression|downloadstring|bitsadmin|frombase64string)</field>
    <description>Suspicious PowerShell execution detected on $(win.system.computer)</description>
    <mitre>
      <id>T1059.001</id>
    </mitre>
    <group>powershell,suspicious_execution,</group>
  </rule>
</group>
```

Testing (INSERT EVIDENCE)


## DET-004: Lateral Movement (PsExec)

### MITRE Mapping
- **Technique**: T1021.002 — Remote Services: SMB/Windows Admin Shares
- **Tactic**: Lateral Movement

### Snort Rule (DMZ Sensor)
```
alert tcp $HOME_NET any -> $HOME_NET 445 (
    msg:"SOC-LAB PsExec Service File Transfer Detected";
    flow:established,to_server;
    content:"|5c|psexesvc.exe"; nocase;
    sid:1000005;
    rev:1;
)

alert tcp $HOME_NET any -> $HOME_NET 445 (
    msg:"SOC-LAB SMB Admin Share Access (Possible Lateral Movement)";
    flow:established,to_server;
    content:"|00 00 00 9f ff 53 4d 42|"; depth:9;
    content:"|5c|ADMIN$|5c|"; nocase;
    sid:1000006;
    rev:1;
)
```
### Splunk SPL 

```
index=sysmon EventCode=1 earliest=-1h
(Image="*\\psexec.exe" OR Image="*\\psexesvc.exe" OR CommandLine="*\\admin$*")
OR
index=winsec EventCode=7045 ServiceName="PSEXESVC"
| eval severity="High"
| eval mitre_technique="T1021.002"
| table _time, Computer, User, Image, CommandLine, ServiceName, severity, mitre_technique

```
### Wazuh Rule 
```
<group name="sysmon,lateral_movement,">
  <rule id="100004" level="12">
    <if_sid>92010</if_sid>
    <field name="win.eventdata.Image">(?i)psexec\.exe|psexesvc\.exe</field>
    <description>PsExec execution detected - possible lateral movement on $(win.system.computer)</description>
    <mitre>
      <id>T1021.002</id>
    </mitre>
    <group>lateral_movement,psexec,</group>
  </rule>

  <rule id="1000041" level="12">
    <if_sid>92010</if_sid>
    <field name="win.eventdata.CommandLine">(?i)\\\\[^\s]+\\(admin|ipc|c|d)\$</field>
    <description>Admin share access detected - possible lateral movement on $(win.system.computer)</description>
    <mitre>
      <id>T1021.002</id>
    </mitre>
    <group>lateral_movement,admin_shares,</group>
  </rule>
</group>

```
Testing (INSERT EVIDENCE)

## DET-005: C2 Beaconing Detection

### MITRE Mapping
- **Technique**: T1071 — Application Layer Protocol
- **Tactic**: Command and Control


### Snort Rule (DMZ Sensor)
```
alert tcp $HOME_NET any -> $EXTERNAL_NET any (
    msg:"SOC-LAB C2 Beaconing Detected - Regular Intervals";
    flow:established,to_server;
    detection_filter:track by_src, count 10, seconds 300;
    sid:1000007;
    rev:1;
)
```

### Splunk SPL 

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
### Wazuh Rule 
```
<group name="c2,beaconing,">
  <rule id="100005" level="12" frequency="10" timeframe="300">
    <if_matched_sid>92003</if_matched_sid>
    <same_source_ip />
    <same_field>win.eventdata.Image</same_field>
    <description>Repeated outbound connections from same process on $(win.system.computer) - possible C2 beaconing</description>
    <mitre>
      <id>T1071</id>
    </mitre>
    <group>c2,beaconing,command_and_control,</group>
  </rule>

  <rule id="1000051" level="13">
    <if_sid>92010</if_sid>
    <field name="win.eventdata.Image">(?i)(beacon|agent|implant|shell|reverse|meterpreter)\.(exe|dll|ps1|bat)</field>
    <description>Possible C2 agent execution detected on $(win.system.computer)</description>
    <mitre>
      <id>T1071</id>
      <id>T1059</id>
    </mitre>
    <group>c2,malware_execution,</group>
  </rule>
</group>
```
Testing (INSERT EVIDENCE)

## DET-006: Credential Dumping (Mimikatz)

### MITRE Mapping
- **Technique**: T1003 — OS Credential Dumping
- **Tactic**: Credential Access

### Snort Rule (DMZ Sensor)
```
alert tcp $HOME_NET any -> $EXTERNAL_NET any (
    msg:"SOC-LAB Mimikatz Output Upload Detected";
    flow:established,to_server;
    content:"sekurlsa"; nocase;
    sid:1000009;
    rev:1;
)

```
### Splunk SPL 

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
### Wazuh Rule 
```
<group name="sysmon,credential_dumping,">
  <rule id="100006" level="14">
    <if_sid>92010</if_sid>
    <field name="win.eventdata.TargetImage">(?i)lsass\.exe</field>
    <field name="win.eventdata.GrantedAccess">(?i)0x1010|0x1410|0x143a|0x1438|0x1016</field>
    <description>LSASS access with suspicious permissions on $(win.system.computer) - possible credential dumping</description>
    <mitre>
      <id>T1003.001</id>
    </mitre>
    <group>credential_access,lsass,</group>
  </rule>

  <rule id="1000061" level="14">
    <if_sid>92010</if_sid>
    <field name="win.eventdata.Image">(?i)mimikatz|mimilib|mimidrv|kiwi</field>
    <description>Mimikatz tool execution detected on $(win.system.computer)</description>
    <mitre>
      <id>T1003</id>
    </mitre>
    <group>credential_access,mimikatz,</group>
  </rule>
</group>
```
Testing (INSERT EVIDENCE)

## DET-007: Persistence via Registry Run Keys
### MITRE Mapping
- **Technique**: T1547.001 — Registry Run Keys / Startup Folder
- **Tactic**: Persistence

### Snort Rule (DMZ Sensor)
```
alert tcp $HOME_NET any -> $EXTERNAL_NET any (
    msg:"SOC-LAB Registry Run Key Config Exfil";
    flow:established,to_server;
    content:"Software|5c|Microsoft|5c|Windows|5c|CurrentVersion|5c|Run"; nocase;
    sid:1000010;
    rev:1;
)
```

### Splunk SPL 

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
### Wazuh Rule 
```
<group name="sysmon,persistence,registry,">
  <rule id="100007" level="10">
    <if_sid>92013</if_sid>
    <field name="win.eventdata.EventType">SetValue</field>
    <field name="win.eventdata.TargetObject">(?i)\\Software\\Microsoft\\Windows\\CurrentVersion\\Run</field>
    <description>Registry Run key modified on $(win.system.computer) - possible persistence</description>
    <mitre>
      <id>T1547.001</id>
    </mitre>
    <group>persistence,registry_run_keys,</group>
  </rule>

  <rule id="1000071" level="10">
    <if_sid>92013</if_sid>
    <field name="win.eventdata.EventType">SetValue</field>
    <field name="win.eventdata.TargetObject">(?i)\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce</field>
    <description>Registry RunOnce key modified on $(win.system.computer) - possible persistence</description>
    <mitre>
      <id>T1547.001</id>
    </mitre>
    <group>persistence,registry_run_keys,</group>
  </rule>
</group>
```

Testing (INSERT EVIDENCE)

## DET-008: Data Exfiltration
### MITRE Mapping
- **Technique**: T1041 — Exfiltration Over C2 Channel
- **Tactic**: Exfiltration

### Snort Rule (DMZ Sensor)
```
alert tcp $HOME_NET any -> $EXTERNAL_NET any (
    msg:"SOC-LAB Large Data Transfer - Possible Exfiltration";
    flow:established,to_server;
    content:!"GET"; content:!"POST"; 
    detection_filter:track by_src, count 1000, seconds 60;
    sid:1000008; 
    rev:1;
)
```

### Splunk SPL 

```
index=firewall earliest=-1h
| stats sum(bytes_out) as total_out, sum(bytes_in) as total_in by src_ip, dest_ip
| eval ratio=total_out/total_in
| where total_out > 104857600 AND ratio > 10
| eval severity="High"
| eval mitre_technique="T1041"
| table _time, src_ip, dest_ip, total_out, total_in, ratio, severity, mitre_technique
```
### Wazuh Rule 
```
<group name="sysmon,exfiltration,">
  <rule id="100008" level="12" frequency="50" timeframe="60">
    <if_matched_sid>92003</if_matched_sid>
    <same_source_ip />
    <field name="win.eventdata.DestinationIp">^(?!10\.0\.)</field>
    <description>Large volume of outbound connections to external IP from $(win.system.computer) - possible data exfiltration</description>
    <mitre>
      <id>T1041</id>
    </mitre>
    <group>exfiltration,</group>
  </rule>
</group>

```
Testing (INSERT EVIDENCE)
