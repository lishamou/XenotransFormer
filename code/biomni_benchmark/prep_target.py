#!/usr/bin/env python
# Build blind target.h5ad (counts only) for Biomni + held-aside ground_truth.csv (CORE labels).
import scipy.io as sio, numpy as np, anndata as ad, os
D="/data/share/mouls/XenotransFormer/results/method_benchmark/for_multitarget"
WS="/data/share/mouls/XenotransFormer/biomni_run/workspace"; os.makedirs(WS,exist_ok=True)
M=sio.mmread(f"{D}/SC0926clean_counts.mtx").tocsr()          # genes x cells
genes=[l.strip() for l in open(f"{D}/SC0926clean_genes.csv")]
bcs=[l.strip() for l in open(f"{D}/SC0926clean_barcodes.csv")]
fine=[l.strip() for l in open(f"{D}/SC0926_finelabels_aligned.csv")]
assert M.shape==(len(genes),len(bcs)), (M.shape,len(genes),len(bcs))
assert len(fine)==len(bcs)
X=M.T.tocsr()                                                # cells x genes
def to_core(f):
    if f=="Proximal Tubule": return "PT"
    if f=="Thick Ascending Limb": return "TAL"
    if f=="Distal Convoluted Tubules": return "DCT"
    if f in ("Collecting Duct Principle","Collecting Duct Intercalated Type A",
             "Collecting Duct Intercalated Type B"): return "IC"
    if f in ("Endothelial","Glomerular Endothelial"): return "Endo"
    if f in ("Monocytes","Macrophages","NK & T Cells"): return "Immune"
    return "Other"
core=[to_core(f) for f in fine]
a=ad.AnnData(X.astype(np.float32))
a.var_names=genes; a.obs_names=bcs
a.write_h5ad(f"{WS}/target.h5ad")
import csv
with open(f"{WS}/../ground_truth.csv","w",newline="") as fo:
    w=csv.writer(fo); w.writerow(["cell_id","true_fine","true_core"])
    for b,f,c in zip(bcs,fine,core): w.writerow([b,f,c])
from collections import Counter
print("target.h5ad:", a.shape, "genes x done")
print("CORE dist:", dict(Counter(core)))
print("WROTE target.h5ad + ground_truth.csv")
