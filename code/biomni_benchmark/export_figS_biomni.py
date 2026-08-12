#!/usr/bin/env python
import json, csv, os
from collections import Counter
from statistics import mean, pstdev
RUN="/data/share/mouls/XenotransFormer/biomni_run"; DT=f"{RUN}/data_targets"
OUT="/data/share/mouls/XenotransFormer/figures/_data"; os.makedirs(OUT,exist_ok=True)
S=json.load(open(f"{RUN}/biomni_benchmark_summary.json"))
def norm(s):
    s=s.strip().lower()
    if s in("pt","proximal tubule"):return "PT"
    if s in("tal","thick ascending limb","thin limb"):return "TAL"
    if s in("dct","distal convoluted tubule","distal convoluted tubules"):return "DCT"
    if "intercalat" in s or s=="ic" or "collecting duct" in s or s in("cd","principal","umbrella"):return "IC"
    if "endotheli" in s or s=="endo":return "Endo"
    if any(k in s for k in["macrophage","monocyte","t cell","nk","myeloid","immune","neutrophil","dc","lympho"]):return "Immune"
    return "Other"
out={"recall":{}, "ic_dest":{}}
for T in ["SC0926","SC0924"]:
    agg=S[T]["recall_agg"]
    out["recall"][T]={c:{"mean":agg[c]["mean"],"sd":agg[c]["sd"]} for c in agg}
    # IC destination averaged over available reps
    gt={r["cell_id"]:r["true_core"] for r in csv.DictReader(open(f"{DT}/gt_{T}.csv"))}
    dest=Counter(); nrep=0
    for rep in [1,2,3]:
        pf=f"{RUN}/workspace/{T}_rep{rep}/biomni_labels.csv"
        if not os.path.exists(pf): continue
        nrep+=1
        pred={}
        rd=csv.reader(open(pf)); next(rd)
        for row in rd:
            if len(row)>=2: pred[row[0]]=norm(row[1])
        for cid,t in gt.items():
            if t=="IC" and cid in pred: dest[pred[cid]]+=1
    tot=sum(dest.values())
    out["ic_dest"][T]={k:round(v/tot,4) for k,v in dest.items()}
    print(T,"IC dest:",out["ic_dest"][T])
json.dump(out, open(f"{OUT}/figS_biomni.json","w"), indent=2)
print("WROTE figS_biomni.json")
