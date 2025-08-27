import json, sys, argparse, csv, os
def load_map(path):
    m = {}
    try:
        with open(path, newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                m[row.get("cwe_id","").strip()] = row.get("owasp_top10","").strip()
    except FileNotFoundError:
        pass
    return m
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sarif", required=True)
    ap.add_argument("--cwe-map", default="")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    if not os.path.exists(args.sarif):
        open(args.out,"w",encoding="utf-8").write("# No SARIF found\n"); return
    with open(args.sarif, encoding="utf-8") as f: sarif=json.load(f)
    cmap = load_map(args.cwe_map)
    runs = sarif.get("runs",[]); out=["# CodeQL Executive Summary\n"]
    total=0
    for run in runs:
        tool = run.get("tool",{}).get("driver",{}).get("name","unknown")
        res = run.get("results",[]); total += len(res)
        out.append(f"## Tool: {tool}, Findings: {len(res)}")
        for r in res[:100]:
            rid = r.get("ruleId",""); msg=r.get("message",{}).get("text","")
            tags=(r.get("properties",{}) or {}).get("tags",[])
            cwes=[t for t in tags if str(t).upper().startswith("CWE-")]
            mapped=[f"{c}:{cmap.get(c,'')}" for c in cwes]
            out.append(f"- {rid} :: {msg} {' '.join(mapped)}")
    out.append(f"\n**Total findings across runs:** {total}\n")
    open(args.out,"w",encoding="utf-8").write("\n".join(out))
if __name__ == "__main__": main()
