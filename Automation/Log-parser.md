#!/usr/bin/env python3
import json
import sys
from datetime import datetime
from collections import Counter


def parse_alert(line):
    """Parse a single Wazuh alert JSON line."""
    try:
        alert = json.loads(line)
    except json.JSONDecodeError:
        return None

    rule = alert.get("rule", {})
    agent = alert.get("agent", {})
    mitre = rule.get("mitre", {})

    mitre_ids = mitre.get("id", [])
    mitre_tactics = mitre.get("tactic", [])
    mitre_techniques = mitre.get("technique", [])

    return {
        "timestamp": alert.get("timestamp", ""),
        "time": alert.get("timestamp", "")[:19],
        "rule_id": str(rule.get("id", "")),
        "level": rule.get("level", 0),
        "description": rule.get("description", "No description"),
        "agent": agent.get("name", "Unknown"),
        "agent_id": agent.get("id", "Unknown"),
        "mitre_id": mitre_ids[0] if mitre_ids else "None",
        "mitre_tactic": mitre_tactics[0] if mitre_tactics else "None",
        "mitre_name": mitre_techniques[0] if mitre_techniques else "None",
        "all_mitre_ids": mitre_ids,
        "src_ip": alert.get("data", {}).get("srcip", "N/A"),
        "dst_ip": alert.get("data", {}).get("dstip", "N/A"),
        "user": alert.get("data", {}).get("dstuser", alert.get("data", {}).get("srcuser", "N/A")),
        "full_log": alert.get("full_log", "")[:200],  # Truncated for display
    }


def severity_label(level):
    """Return human-readable severity."""
    if level >= 12:
        return "CRITICAL"
    elif level >= 8:
        return "HIGH"
    elif level >= 5:
        return "MEDIUM"
    elif level >= 3:
        return "LOW"
    else:
        return "INFO"


def main():
    # Allow custom filepath via command line
    filepath = sys.argv[1] if len(sys.argv) > 1 else "/var/ossec/logs/alerts/alerts.json"
    
# Allow custom severity threshold
    min_level = int(sys.argv[2]) if len(sys.argv) > 2 else 3

    print("=" * 70)
    print(f"WAZUH ALERT REPORT — {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Source: {filepath}")
    print(f"Minimum level: {min_level}")
    print("=" * 70)

    alerts = []
    agents = Counter()
    rules = Counter()
    mitre_ids = Counter()
    error_count = 0

    try:
        with open(filepath, "r") as f:
            for line_num, line in enumerate(f, 1):
                if not line.strip():
                    continue

                alert = parse_alert(line)
                if alert is None:
                    error_count += 1
                    continue

                if alert["level"] >= min_level:
                    alerts.append(alert)
                    agents[alert["agent"]] += 1
                    rules[alert["description"]] += 1
                    if alert["mitre_id"] != "None":
                        mitre_ids[alert["mitre_id"]] += 1

    except FileNotFoundError:
        print(f"\n[!] Error: File not found: {filepath}")
        print("[!] Ensure you have alerts generated, or run as root/sudo.")
        sys.exit(1)
    except PermissionError:
        print(f"\n[!] Error: Permission denied: {filepath}")
        print("[!] Try: sudo python3 {sys.argv[0]}")
        sys.exit(1)

# Display alerts
    for alert in alerts:
        severity = severity_label(alert["level"])
        print(f"\n[{severity}] {alert['description']}")
        print(f"  Time:    {alert['time']}")
        print(f"  Agent:   {alert['agent']} (ID: {alert['agent_id']})")
        print(f"  Rule:    {alert['rule_id']} (Level: {alert['level']})")
        print(f"  MITRE:   {alert['mitre_id']} — {alert['mitre_name']} ({alert['mitre_tactic']})")
        
# Show network info if available
        if alert["src_ip"] != "N/A":
            print(f"  Source:  {alert['src_ip']}")
        if alert["dst_ip"] != "N/A":
            print(f"  Dest:    {alert['dst_ip']}")
        if alert["user"] != "N/A":
            print(f"  User:    {alert['user']}")
        
# Show truncated log snippet
        if alert["full_log"]:
            print(f"  Log:     {alert['full_log']}...")

# Summary statistics
    print(f"\n{'=' * 70}")
    print("SUMMARY")
    print("=" * 70)
    print(f"Total alerts (level ≥{min_level}): {len(alerts)}")
    print(f"Parse errors: {error_count}")
    
    if agents:
        print(f"\nTop agents:")
        for agent, count in agents.most_common(5):
            print(f"  {agent}: {count}")
    
    if rules:
        print(f"\nTop alert types:")
        for rule, count in rules.most_common(5):
            print(f"  {rule}: {count}")
    
    if mitre_ids:
        print(f"\nTop MITRE techniques:")
        for mid, count in mitre_ids.most_common(5):
            print(f"  {mid}: {count}")

    print("=" * 70)


if __name__ == "__main__":
    main()
