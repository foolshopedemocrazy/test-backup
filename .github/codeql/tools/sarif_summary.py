#!/usr/bin/env python3
"""
Generate a compact executive summary in Markdown from a SARIF file.

- Counts by severity bucket (Critical/High/Medium/Low) using 'security-severity'
- Top rules by frequency
- OWASP grouping via optional CWE→OWASP CSV
- PR-friendly Markdown output
"""
import argparse, csv, json
from collections import Counter
from pathlib import Path
from typing import Dict, Optional, List

def bucket(score_str: Optional[str]) -> str:
    try:
        s = float(score_str) if score_str is not None else None
    except ValueError:
        s = None
    if s is None: return "Unspecified"
    if s >= 9.0:  return "Critical"
    if s >= 7.0:  return "High"
    if s >= 4.0:  return "Medium"
    return "Low"

def load_cwe_to_owasp(csv_path: Optional[Path]) -> Dict[str, str]:
    if not csv_path or not csv_path.exists():
        return {}
    mapping = {}
    with csv_path.open(newline="", encoding="utf-8") as fh:
        reader = csv.reader(fh)
        for row in reader:
            if not row or row[0].startswith("#") or len(row) < 2: continue
            mapping[row[0].strip()] = row[1].strip()
    return mapping

def extract_rule_meta(rules: List[dict]) -> Dict[str, dict]:
    meta = {}
    for r in rules or []:
        rid   = r.get("id")
        props = r.get("properties", {}) or {}
        tags  = props.get("tags", []) or []
        meta[rid] = {
            "default_security_severity": props.get("security-severity"),
            "tags": tags,
            "name": r.get("name") or rid,
            "shortDescription": (r.get("shortDescription") or {}).get("text", ""),
            "fullDescription": (r.get("fullDescription") or {}).get("text", "")
        }
    return meta

def cwe_from_tags(tags: List[str]) -> Optional[str]:
    for t in tags or []:
        tt = t.lower()
        if "external/cwe/cwe-" in tt:
            num = "".join(ch for ch in tt.split("external/cwe/cwe-")[1] if ch.isdigit())
            if num: return num
    return None

def owasp_for_cwe(cwe: Optional[str], cwe_map: Dict[str, str]) -> str:
    if not cwe: return cwe_map.get("*_default", "A00:Unmapped")
    return cwe_map.get(cwe, cwe_map.get("*_default", "A00:Unmapped"))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sarif", required=True, type=Path)
    ap.add_argument("--out",   required=True, type=Path)
    ap.add_argument("--cwe-map", required=False, type=Path)
    args = ap.parse_args()

    sarif = json.loads(args.sarif.read_text(encoding="utf-8"))
    runs  = sarif.get("runs", [])
    cwe_map = load_cwe_to_owasp(args.cwe_map)

    severity_counts = Counter()
    owasp_counts    = Counter()
    rule_counts     = Counter()
    new_counts = 0
    total = 0

    rule_meta: Dict[str, dict] = {}
    for run in runs:
        driver = (run.get("tool") or {}).get("driver") or {}
        rule_meta.update(extract_rule_meta(driver.get("rules", []) or []))

    for run in runs:
        for res in run.get("results", []) or []:
            total += 1
            rule_id = res.get("ruleId") or (res.get("rule") or {}).get("id") or "unknown-rule"
            rule_counts[rule_id] += 1

            props = res.get("properties", {}) or {}
            sec_sev = props.get("security-severity") or rule_meta.get(rule_id, {}).get("default_security_severity")
            severity_counts[bucket(sec_sev)] += 1

            if res.get("baselineState") == "new":
                new_counts += 1

            tags = (res.get("rule") or {}).get("properties", {}).get("tags") \
                   or rule_meta.get(rule_id, {}).get("tags", []) or []
            cwe = cwe_from_tags(tags)
            owasp_counts[owasp_for_cwe(cwe, cwe_map)] += 1

    top_rules = rule_counts.most_common(5)

    lines = []
    lines.append("# CodeQL Executive Summary\n")
    lines.append(f"- **Total alerts**: {total}")
    lines.append(f"- **New in this run**: {new_counts}\n")

    def table(title: str, data: Counter, h1: str, h2: str):
        lines.append(f"## {title}\n")
        lines.append(f"| {h1} | {h2} |")
        lines.append("|---|---:|")
        for k, v in data.most_common():
            lines.append(f"| {k} | {v} |")
        lines.append("")

    table("Alerts by Severity", severity_counts, "Severity", "Count")
    table("Alerts by OWASP Group", owasp_counts, "OWASP", "Count")

    lines.append("## Top Rules\n")
    lines.append("| Rule ID | Count |")
    lines.append("|---|---:|")
    for rid, cnt in top_rules:
        lines.append(f"| `{rid}` | {cnt} |")
    lines.append("")

    args.out.write_text("\n".join(lines), encoding="utf-8")

if __name__ == "__main__":
    main()
