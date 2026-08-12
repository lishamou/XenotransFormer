# XenotransFormer — Snakemake pipeline
# End-to-end reproduction of every figure, supplementary figure, table, and
# supplementary table reported in the manuscript.
#
# Run with:
#   snakemake --cores 8 --use-conda --conda-frontend mamba
# or on a SLURM cluster:
#   snakemake --profile profiles/slurm --use-conda
# or inside the Docker image:
#   snakemake --cores 8 --use-conda  (the image is already conda-isolated)
#
# This Snakefile models the paper as a DAG with 11 top-level rules whose
# outputs are the manuscript's display items. Each rule writes to a single,
# deterministic output path under `results/`. Re-running the pipeline with
# identical inputs is byte-identical (PYTHONHASHSEED=42, CUBLAS_WORKSPACE
# deterministic, seed=42 throughout).

import os
from pathlib import Path

# ----- Config -----
configfile: "config/config.yaml"

RESULTS = Path("results")
EMBED  = RESULTS / "embeddings"
METRIC = RESULTS / "metrics"
FIG    = RESULTS / "figures"
SUPP   = RESULTS / "supplementary"
LOG    = RESULTS / "logs"
TBL    = RESULTS / "tables"

for d in (EMBED, METRIC, FIG, SUPP, LOG, TBL):
    d.mkdir(parents=True, exist_ok=True)

# ----- Top-level targets -----
# These are the 9 main figures + 5 main tables + 10 supplementary figures +
# 9 supplementary tables reported in the manuscript. Snakemake walks the
# DAG backwards to schedule only what's needed.
rule all:
    input:
        # Main figures
        FIG / "figure_1_pipeline.png",
        FIG / "figure_per_timepoint.png",
        FIG / "figure_cross_dataset_generalization.png",
        FIG / "figure_ablation_comparison.png",
        FIG / "figure_s2_direct_vs_mlp.png",
        FIG / "figure_s3a_confusion_matrix.png",
        FIG / "figure_s3b_cross_dataset_confusion.png",
        FIG / "figure_s3c_timepoint_distribution.png",
        # Main tables
        TBL / "table_1_ablation.md",
        TBL / "table_2_per_class_f1.md",
        TBL / "table_3_cross_dataset_f1.md",
        # Supplementary figures
        SUPP / "fig_s1_umap.png",
        SUPP / "fig_s2_calibration.png",
        SUPP / "fig_s3_calibration_4plussn0001.png",
        SUPP / "fig_s4_per_timepoint_per_type_knn.png",
        SUPP / "fig_s5_cross_species_per_type.png",
        SUPP / "fig_s6_cross_organ_ood.png",
        SUPP / "fig_s7_5x5_pairwise.png",
        SUPP / "fig_s8_centroid_cosine.png",
        SUPP / "fig_s9_20pairs_4metrics.png",
        SUPP / "fig_s10_20pairs_calibration.png",
        # Supplementary tables
        TBL / "table_s1_per_dataset_composition.md",
        TBL / "table_s2_seed_sensitivity.md",
        TBL / "table_s3_wilcoxon_bootstrap.md",
        TBL / "table_s4_cosine_similarity_8x8.md",
        TBL / "table_s5_pairwise_12pairs.md",
        TBL / "table_s6_sn0001_composition.md",
        TBL / "table_s9_lod_3set_xenograft_only.md",
        TBL / "table_s10_timepoints.md",
        TBL / "table_s11_gene_conservation.md",
        TBL / "table_s12_bonferroni.md",
        TBL / "table_s13_batch_silhouette.md",

# ===== Stage 1: Embedding extraction =====
# Each dataset is processed through the frozen TF-Metazoa model. The
# output is a (n_cells, 2048) float32 .npy + per-cell metadata .csv.
rule extract_embeddings_all:
    input:
        expand(EMBED / "{dataset}.npy", dataset=[
            "SC0923", "SC0924", "SC0926", "SC0939",
            "SC0629", "SN0001_32k",
        ]),
        expand(EMBED / "{dataset}_meta.csv", dataset=[
            "SC0923", "SC0924", "SC0926", "SC0939",
            "SC0629", "SN0001_32k",
        ]),

rule extract_embeddings:
    output:
        npy=EMBED / "{dataset}.npy",
        meta=EMBED / "{dataset}_meta.csv",
    log: LOG / "extract_{dataset}.log"
    resources:
        gpu=1,
        mem_mb=32000,
        time_min=240,
    script:
        "scripts/extract_embeddings.py"

# ===== Stage 2: Single-dataset classification =====
# Trains a 3-layer MLP per dataset (80/20, seed=42) and reports
# per-dataset and per-class accuracy. Output feeds Tables 4-5 and
# Figure 2.
rule single_dataset_classification:
    input:
        npy=EMBED / "{dataset}.npy",
        meta=EMBED / "{dataset}_meta.csv",
    output:
        metrics=METRIC / "single_{dataset}.json",
    log: LOG / "single_{dataset}.log"
    resources:
        gpu=1, mem_mb=16000, time_min=60,
    script:
        "scripts/single_dataset_classification.py"

rule aggregate_single_dataset:
    input:
        expand(METRIC / "single_{dataset}.json", dataset=[
            "SC0923", "SC0924", "SC0926", "SC0939", "SC0629"
        ])
    output:
        table=TBL / "table_s1_per_dataset_composition.md",
        json=METRIC / "single_dataset_aggregated.json",
    script:
        "scripts/aggregate_single_dataset.py"

# ===== Stage 3: Cross-dataset generalization =====
# 12 directed pair-wise + 4×4 L-O-D matrix. Produces Table 5, Table S5,
# Figure 3, and Figure S7 (5×5 with SN0001).
rule cross_dataset_pairwise:
    input:
        npy_a=EMBED / "{source}.npy",
        meta_a=EMBED / "{source}_meta.csv",
        npy_b=EMBED / "{target}.npy",
        meta_b=EMBED / "{target}_meta.csv",
    output:
        json=METRIC / "pair_{source}_to_{target}.json",
    log: LOG / "pair_{source}_{target}.log"
    resources:
        gpu=1, mem_mb=16000, time_min=30,
    script:
        "scripts/cross_dataset_pairwise.py"

rule aggregate_pairwise:
    input:
        # 12 directed pairs across 4 kidney datasets
        expand(METRIC / "pair_{s}_to_{t}.json",
               s=["SC0923", "SC0924", "SC0926", "SC0939"],
               t=["SC0923", "SC0924", "SC0926", "SC0939"],
               allow_missing=True),
    output:
        table_s5=TBL / "table_s5_pairwise_12pairs.md",
        figure_3=FIG / "figure_cross_dataset_generalization.png",
        figure_s7=SUPP / "fig_s7_5x5_pairwise.png",
    script:
        "scripts/aggregate_pairwise.py"

rule lod_4set:
    input:
        expand(METRIC / "lod_{test}.json", test=[
            "SC0923", "SC0924", "SC0926", "SC0939"
        ])
    output:
        table_s9=TBL / "table_s9_lod_3set_xenograft_only.md",
        metrics=METRIC / "lod_4set.json",
    script:
        "scripts/lod_4set.py"

# ===== Stage 4: Loss function ablation =====
# 4 conditions × 4 kidney sets × 5 random seeds.
rule ablation:
    input:
        npy=EMBED / "{dataset}.npy",
        meta=EMBED / "{dataset}_meta.csv",
    output:
        json=METRIC / "ablation_{dataset}_seed{seed}.json",
    log: LOG / "ablation_{dataset}_seed{seed}.log"
    resources:
        gpu=1, mem_mb=16000, time_min=120,
    script:
        "scripts/ablation.py"

rule aggregate_ablation:
    input:
        expand(METRIC / "ablation_{dataset}_seed{seed}.json",
               dataset=["SC0923", "SC0924", "SC0926", "SC0939"],
               seed=[42, 123, 2024, 314, 1729])
    output:
        table_1=TBL / "table_1_ablation.md",
        figure_4=FIG / "figure_ablation_comparison.png",
        table_s2=TBL / "table_s2_seed_sensitivity.md",
        table_s3=TBL / "table_s3_wilcoxon_bootstrap.md",
    script:
        "scripts/aggregate_ablation.py"

# ===== Stage 5: Embedding geometry =====
# Centroid cosine similarity 8×8, Silhouette, Projection ablation.
rule embedding_geometry:
    input:
        expand(EMBED / "{dataset}.npy", dataset=[
            "SC0923", "SC0924", "SC0926", "SC0939"
        ])
    output:
        table_s4=TBL / "table_s4_cosine_similarity_8x8.md",
        figure_4geom=FIG / "figure_4_embedding_geometry.png",
        figure_s8=SUPP / "fig_s8_centroid_cosine.png",
    script:
        "scripts/embedding_geometry.py"

# ===== Stage 6: OOD cross-organ =====
# 4 kidney → SC0629 transfer with reliability diagram.
rule cross_organ_ood:
    input:
        kidney_npy=expand(EMBED / "{d}.npy", d=[
            "SC0923", "SC0924", "SC0926", "SC0939"
        ]),
        kidney_meta=expand(EMBED / "{d}_meta.csv", d=[
            "SC0923", "SC0924", "SC0926", "SC0939"
        ]),
        islet_npy=EMBED / "SC0629.npy",
        islet_meta=EMBED / "SC0629_meta.csv",
    output:
        metrics=METRIC / "cross_organ_ood.json",
        figure_s6=SUPP / "fig_s6_cross_organ_ood.png",
    resources:
        gpu=1, mem_mb=32000, time_min=60,
    script:
        "scripts/cross_organ_ood.py"

# ===== Stage 7: Cross-species transfer (SN0001 → 4 human) =====
# Per-type kNN recall (k=20) + 6 timepoints + mixed-source 4+SN0001.
rule cross_species:
    input:
        sn=EMBED / "SN0001_32k.npy",
        sn_meta=EMBED / "SN0001_32k_meta.csv",
        human=expand(EMBED / "{d}.npy", d=[
            "SC0923", "SC0924", "SC0926", "SC0939"
        ]),
        human_meta=expand(EMBED / "{d}_meta.csv", d=[
            "SC0923", "SC0924", "SC0926", "SC0939"
        ]),
    output:
        table_3=TBL / "table_3_cross_dataset_f1.md",
        table_s10=TBL / "table_s10_timepoints.md",
        figure_2=FIG / "figure_per_timepoint.png",
        figure_s4=SUPP / "fig_s4_per_timepoint_per_type_knn.png",
        figure_s5=SUPP / "fig_s5_cross_species_per_type.png",
    script:
        "scripts/cross_species.py"

# ===== Stage 8: IC identity module decomposition (ssGSEA) =====
# Per-cell IC_score + KEGG enrichment + cross-species expression correlation.
rule ic_module_decomposition:
    input:
        sn=EMBED / "SN0001_32k.npy",
        sn_meta=EMBED / "SN0001_32k_meta.csv",
        human=expand(EMBED / "{d}.npy", d=[
            "SC0923", "SC0924", "SC0926", "SC0939"
        ]),
    output:
        table_s11=TBL / "table_s11_gene_conservation.md",
        table_s12=TBL / "table_s12_bonferroni.md",
        metrics=METRIC / "ic_module.json",
    script:
        "scripts/ic_module_decomposition.py"

# ===== Stage 9: Confusion matrices =====
rule confusion_matrices:
    input:
        expand(EMBED / "{dataset}.npy", dataset=[
            "SC0923", "SC0924", "SC0926", "SC0939"
        ])
    output:
        figure_s3a=FIG / "figure_s3a_confusion_matrix.png",
        figure_s3b=FIG / "figure_s3b_cross_dataset_confusion.png",
        figure_s3c=FIG / "figure_s3c_timepoint_distribution.png",
        figure_s2=FIG / "figure_s2_direct_vs_mlp.png",
    script:
        "scripts/confusion_matrices.py"

# ===== Stage 10: UMAP visualisation =====
rule umap_visualisation:
    input:
        npy=EMBED / "SC0926.npy",
        meta=EMBED / "SC0926_meta.csv",
    output:
        figure_s1=SUPP / "fig_s1_umap.png",
        figure_1=FIG / "figure_1_pipeline.png",
    resources:
        gpu=1, mem_mb=32000, time_min=30,
    script:
        "scripts/umap_visualisation.py"

# ===== Stage 11: Calibration + 20-pair diagnostic =====
rule calibration:
    input:
        expand(EMBED / "{d}.npy", d=[
            "SC0923", "SC0924", "SC0926", "SC0939", "SC0629", "SN0001_32k"
        ])
    output:
        figure_s2cal=SUPP / "fig_s2_calibration.png",
        figure_s3cal=SUPP / "fig_s3_calibration_4plussn0001.png",
        figure_s9=SUPP / "fig_s9_20pairs_4metrics.png",
        figure_s10=SUPP / "fig_s10_20pairs_calibration.png",
    script:
        "scripts/calibration.py"

# ===== Stage 12: Batch-effect quantification (§2.10 controls) =====
rule batch_effect_controls:
    input:
        expand(EMBED / "{d}.npy", d=[
            "SC0923", "SC0924", "SC0926", "SC0939", "SC0629"
        ])
    output:
        table_s13=TBL / "table_s13_batch_silhouette.md",
    script:
        "scripts/batch_effect_controls.py"

# ===== Stage 13: SN0001 composition table =====
rule sn0001_composition:
    input:
        meta=EMBED / "SN0001_32k_meta.csv",
    output:
        table_s6=TBL / "table_s6_sn0001_composition.md",
    script:
        "scripts/sn0001_composition.py"

# ===== Stage 14: Per-class F1 cross-dataset transfer (Table 2) =====
rule per_class_f1_transfer:
    input:
        expand(EMBED / "{d}.npy", d=[
            "SC0923", "SC0924", "SC0926", "SC0939"
        ])
    output:
        table_2=TBL / "table_2_per_class_f1.md",
    script:
        "scripts/per_class_f1_transfer.py"
