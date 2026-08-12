#!/usr/bin/env python
import csv, json, os
from collections import Counter, defaultdict
from statistics import mean, pstdev
RUN="/data/share/mouls/XenotransFormer/biomni_run"; DT=f"{RUN}/data_targets"
CORE=["PT","TAL","DCT","IC","Endo","Immune","Other"]
def norm(lbl):
    s=lbl.strip().lower()
    if s in ("pt","proximal tubule","proximal_tubule"): return "PT"
    if s in ("tal","thick ascending limb","thin limb"): return "TAL"
    if s in ("dct","distal convoluted tubule","distal convoluted tubules"): return "DCT"
    if "intercalat" in s or s=="ic" or "collecting duct" in s or s in ("cd","principal","umbrella"): return "IC"
    if "endotheli" in s or s=="endo": return "Endo"
    if any(k in s for k in ["macrophage","monocyte","t cell","nk","lympho","myeloid","immune","leukocyte","neutrophil","dendritic","dc"]): return "Immune"
    return "Other"
summary={}
for T in ["SC0926","SC0924"]:
    gt={}
    for r in csv.DictReader(open(f"{DT}/gt_{T}.csv")): gt[r["cell_id"]]=r["true_core"]
    reps=[]
    for rep in [1,2,3]:
        pf=f"{RUN}/workspace/{T}_rep{rep}/biomni_labels.csv"
        if not os.path.exists(pf): continue
        pred={}
        with open(pf) as f:
            rd=csv.reader(f); next(rd)
            for row in rd:
                if len(row)>=2: pred[row[0]]=norm(row[1])
        conf=defaultdict(Counter); truec=Counter()
        for c,t in gt.items():
            if t=="DROP" or c not in pred: continue
            conf[t][pred[c]]+=1; truec[t]+=1
        rec={t:(conf[t][t]/truec[t] if truec[t] else None) for t in CORE if truec[t]}
        ic_to_dct=conf["IC"]["DCT"]/truec["IC"] if truec.get("IC") else None
        reps.append({"rep":rep,"recall":rec,"n":dict(truec),
                     "IC_to_DCT_frac":round(ic_to_dct,3) if ic_to_dct is not None else None,
                     "matched":sum(truec.values())})
        print(f"[{T} rep{rep}] IC={rec.get('IC',0):.2%} DCT={rec.get('DCT',0):.2%} "
              f"IC->DCT={ic_to_dct:.2%} PT={rec.get('PT',0):.2%} (matched {sum(truec.values())})")
    # aggregate
    if reps:
        agg={}
        for t in CORE:
            vals=[r["recall"][t] for r in reps if t in r["recall"]]
            if vals: agg[t]={"mean":round(mean(vals),3),"sd":round(pstdev(vals),3),"n_reps":len(vals)}
        ictodct=[r["IC_to_DCT_frac"] for r in reps if r["IC_to_DCT_frac"] is not None]
        summary[T]={"reps":reps,"recall_agg":agg,
                    "IC_to_DCT_mean":round(mean(ictodct),3) if ictodct else None}
        print(f"  >> {T} AGG: IC {agg.get('IC',{}).get('mean')}±{agg.get('IC',{}).get('sd')} | "
              f"DCT {agg.get('DCT',{}).get('mean')}±{agg.get('DCT',{}).get('sd')} | IC->DCT {summary[T]['IC_to_DCT_mean']}")
json.dump(summary, open(f"{RUN}/biomni_benchmark_summary.json","w"), indent=2)
print("WROTE biomni_benchmark_summary.json")
