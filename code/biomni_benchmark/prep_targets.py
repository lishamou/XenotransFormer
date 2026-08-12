#!/usr/bin/env python
import scipy.io as sio, numpy as np, anndata as ad, os, csv
D="/data/share/mouls/XenotransFormer/results/method_benchmark/for_multitarget"
OUT="/data/share/mouls/XenotransFormer/biomni_run/data_targets"; os.makedirs(OUT,exist_ok=True)
def core_sc0926(f):
    m={"Proximal Tubule":"PT","Thick Ascending Limb":"TAL","Distal Convoluted Tubules":"DCT",
       "Collecting Duct Principle":"IC","Collecting Duct Intercalated Type A":"IC","Collecting Duct Intercalated Type B":"IC",
       "Endothelial":"Endo","Glomerular Endothelial":"Endo","Monocytes":"Immune","Macrophages":"Immune","NK & T Cells":"Immune"}
    return m.get(f,"Other")
def core_sc0924(f):
    if f=="DROP": return "DROP"
    m={"Proximal Tubule":"PT","Thick Ascending Limb":"TAL","Thin Limb":"TAL","Distal Convoluted Tubule":"DCT",
       "Collecting Duct Principle":"IC","Collecting Duct Intercalated Type A":"IC","Collecting Duct Intercalated Type B":"IC",
       "Endothelial":"Endo","Fenestrated Endothelial":"Endo","Glomerular Endothelial":"Endo",
       "Macrophage":"Immune","Myeloid":"Immune","T Cells":"Immune","Neutrophils":"Immune","Plasmacytoid DC":"Immune"}
    return m.get(f,"Other")
TG={"SC0926":("SC0926clean_counts.mtx","SC0926clean_genes.csv","SC0926clean_barcodes.csv","SC0926_finelabels_aligned.csv",core_sc0926),
    "SC0924":("SC0924_counts.mtx","SC0924_genes.csv","SC0924_barcodes.csv","SC0924_finelabels_aligned.csv",core_sc0924)}
for T,(cnt,gf,bf,lf,mp) in TG.items():
    M=sio.mmread(f"{D}/{cnt}").tocsr()
    genes=[l.strip() for l in open(f"{D}/{gf}")]; bcs=[l.strip() for l in open(f"{D}/{bf}")]
    fine=[l.strip() for l in open(f"{D}/{lf}")]
    if M.shape[0]==len(genes): X=M.T.tocsr()
    else: X=M.tocsr()
    assert X.shape[0]==len(bcs)==len(fine), (T,X.shape,len(bcs),len(fine))
    a=ad.AnnData(X.astype(np.float32)); a.var_names=genes; a.obs_names=bcs
    a.write_h5ad(f"{OUT}/target_{T}.h5ad")
    with open(f"{OUT}/gt_{T}.csv","w",newline="") as fo:
        w=csv.writer(fo); w.writerow(["cell_id","true_fine","true_core"])
        for b,f in zip(bcs,fine): w.writerow([b,f,mp(f)])
    from collections import Counter
    print(T, X.shape, "CORE:", dict(Counter(mp(f) for f in fine)))
print("DONE prep_targets")
