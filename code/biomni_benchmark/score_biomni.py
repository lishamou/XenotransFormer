#!/usr/bin/env python
# Compare Biomni CORE annotation vs held-aside ground truth. Focus: IC/DCT recall + where they leak.
import csv, json, os, re
from collections import Counter, defaultdict
RUN="/data/share/mouls/XenotransFormer/biomni_run"
GT=f"{RUN}/ground_truth.csv"; PRED=f"{RUN}/workspace/biomni_labels.csv"
CORE=["PT","TAL","DCT","IC","Endo","Immune","Other"]
def norm(lbl):
    s=lbl.strip().lower()
    if s in ("pt","proximal tubule","proximal_tubule"): return "PT"
    if s in ("tal","thick ascending limb"): return "TAL"
    if s in ("dct","distal convoluted tubule","distal convoluted tubules"): return "DCT"
    if "intercalat" in s or s=="ic" or "collecting duct" in s or s in ("cd","principal"): return "IC"
    if s in ("endo","endothelial") or "endotheli" in s: return "Endo"
    if s in ("immune",) or any(k in s for k in ["macrophage","monocyte","t cell","nk","lympho","myeloid","immune","leukocyte"]): return "Immune"
    return "Other"
gt={}
for r in csv.DictReader(open(GT)): gt[r["cell_id"]]=r["true_core"]
pred={}; raw=Counter()
with open(PRED) as f:
    rd=csv.reader(f); hdr=next(rd)
    ci=0; li=1
    for row in rd:
        if len(row)<2: continue
        cid=row[0]; lab=row[1]; raw[lab]+=1
        pred[cid]=norm(lab)
common=[c for c in gt if c in pred]
print(f"cells: gt={len(gt)} pred={len(pred)} matched={len(common)}")
print("raw Biomni label vocab:", dict(raw))
# confusion + recall
conf=defaultdict(Counter); truec=Counter(); predc=Counter()
for c in common:
    t=gt[c]; p=pred[c]; conf[t][p]+=1; truec[t]+=1; predc[p]+=1
rows=[]
for t in CORE:
    n=truec[t]
    if n==0: continue
    correct=conf[t][t]; recall=correct/n
    leaks=", ".join(f"{k}:{v}({v/n:.0%})" for k,v in conf[t].most_common(4))
    rows.append({"class":t,"true_n":n,"recall":round(recall,3),"top_pred":leaks})
    print(f"{t:7s} n={n:5d} recall={recall:.2%}  ->  {leaks}")
print("pred totals:", dict(predc))
out={"matched":len(common),"raw_vocab":dict(raw),
     "per_class":rows,"true_counts":dict(truec),"pred_counts":dict(predc),
     "confusion":{t:dict(conf[t]) for t in conf}}
json.dump(out, open(f"{RUN}/biomni_vs_truth.json","w"), indent=2)
print("WROTE biomni_vs_truth.json")
