# XenotransFormer — Reproducibility Guide

End-to-end reproduction of every figure, table, and supplementary item in
the manuscript **"XenotransFormer: Cross-Dataset and Cross-Species Cell
Type Recognition in Pig-to-Primate Xenotransplantation from
TranscriptFormer Embeddings"** (v4.5, 2026-06-23).

This guide covers **three independent, byte-equivalent reproduction paths**:
a Snakemake pipeline (`Snakefile`), a single Docker image (`Dockerfile`),
and a manual step-by-step (for users who prefer explicit control). All
three converge on the same `results/` directory and produce the same
numbers (within the tolerances documented in §2.11 of the manuscript).

---

## 0. System requirements

| Component | Minimum | Recommended |
|---|---|---|
| OS | Linux x86_64 (Ubuntu 22.04) | Same |
| CPU | 8 cores | 16 cores |
| RAM | 32 GB | 64 GB |
| GPU | NVIDIA V100 32GB | NVIDIA A100 80GB |
| Disk | 100 GB free | 250 GB free |
| CUDA | 12.4 | 12.4 |
| Conda | miniconda 24.9 | mamba 1.5 |
| Docker | 24.0 + nvidia-container-toolkit | Same |
| Snakemake | 8.18 | 9.0+ |

For a Mac/Apple-Silicon user, replace `--gpus` with CPU-only mode
(figure generation works; embedding extraction is ~30× slower).

---

## 1. One-command reproduction (Docker, recommended)

The Docker image is the **fastest, most reliable** path because the
environment is fully isolated and the build is reproducible bit-for-bit.

```bash
# Pull the pre-built image (~6 GB, includes CUDA 12.4 + cuDNN 9.2 + conda env)
docker pull ghcr.io/<owner>/xenotransformer:v4.5

# Run the full pipeline, mounting results/ to a local directory
docker run --rm --gpus all \
    -v $(pwd)/results:/work/results \
    -v $(pwd)/data:/work/data:ro \
    ghcr.io/<owner>/xenotransformer:v4.5

# Expected wall-clock on a single A100 80GB:
#   - Embedding extraction (6 datasets): ~45 min
#   - Single-dataset classification:    ~10 min
#   - Cross-dataset (12 pairs × 5 seeds): ~3 h
#   - Cross-species + IC module:        ~1 h
#   - Calibration + UMAP:                ~30 min
#   TOTAL:                                ~5 h
```

The entrypoint runs `snakemake --cores 8 --use-conda` against the
mounted `/work` directory. On success you will see lines like
`Finished job 0.` and a final `5 of 5 steps (100%) done`.

### 1a. Build the image from source (alternative)

```bash
# Requires Docker 24+ with buildx, nvidia-container-toolkit
git clone https://github.com/<owner>/xenotransformer.git
cd xenotransformer
docker build -t xenotransformer:v4.5 .
```

The `Dockerfile` is multi-stage and produces a `~6 GB` final image with
all native dependencies, the conda env, the xenotransformer package, and
the Snakemake pipeline baked in. A non-root user (`xenotransformer`,
UID 1000) runs the pipeline.

---

## 2. Conda + Snakemake (no Docker)

If you cannot or do not want to use Docker, the conda + Snakemake path
reproduces the same outputs on a vanilla Linux machine.

```bash
# 2.1 Clone the repo
git clone https://github.com/<owner>/xenotransformer.git
cd xenotransformer

# 2.2 Create the conda environment (resolves all native deps)
mamba env create -f environment.yml     # or: conda env create -f environment.yml
conda activate xenotransformer

# 2.3 Install in-house package + TranscriptFormer from source
pip install -e ./xenotransformer_pkg
pip install git+https://github.com/czi-bio/Transcription-Foundation-Model.git@v2026.03.0

# 2.4 Download the 5 source datasets (publicly available, ~12 GB total)
#     Instructions: see §"Data sources" below

# 2.5 Run the full pipeline
snakemake --cores 8 --use-conda

# Or run only what you need:
snakemake --cores 8 results/figures/figure_1_pipeline.png
snakemake --cores 8 results/tables/table_s11_gene_conservation.md
```

The `--use-conda` flag tells Snakemake to materialise per-rule conda
environments (useful if you want strict isolation per analysis stage),
but the **default behaviour** assumes you have already activated the
top-level `xenotransformer` env. To skip the per-rule envs:

```bash
snakemake --cores 8  # no --use-conda; uses the activated env directly
```

---

## 3. Manual step-by-step (no Snakemake, no Docker)

If you prefer to inspect each step in detail or only need a subset of
the results:

```bash
# Step 1: extract TF-Metazoa embeddings for all 6 datasets
python scripts/extract_embeddings.py \
    --input data/SC0923.h5ad \
    --model tf_metazoa \
    --out results/embeddings/SC0923.npy \
    --meta-out results/embeddings/SC0923_meta.csv

# Step 2: single-dataset classification
python scripts/single_dataset_classification.py \
    --npy results/embeddings/SC0926.npy \
    --meta results/embeddings/SC0926_meta.csv \
    --out results/metrics/single_SC0926.json

# Step 3: cross-dataset pair-wise (one of 12 directed pairs)
python scripts/cross_dataset_pairwise.py \
    --source SC0926 --target SC0923 \
    --out results/metrics/pair_SC0926_to_SC0923.json

# Step 4: cross-species (SN0001 → SC0926)
python scripts/cross_species.py \
    --source SN0001_32k --target SC0926 \
    --out results/metrics/cross_species_SC0926.json

# Step 5: figures
python scripts/aggregate_pairwise.py
python scripts/aggregate_ablation.py
python scripts/cross_organ_ood.py
python scripts/cross_species.py
# ... (see Snakefile for the full DAG)
```

Each script accepts `--help` and writes a single deterministic output.
`PYTHONHASHSEED=42` is exported by the conda env (see `environment.yml`
`variables:` block) to ensure that dict iteration order is reproducible.

---

## 4. Data sources

All five primary datasets are publicly available. **The pipeline does
NOT re-host the data; users must download from the original sources.**

| Dataset | Source | Identifier | Size |
|---|---|---|---|
| SC0923 | GEO | GSE257542 | 444 MB |
| SC0924 | GEO | GSE210557 | 144 MB |
| SC0926 | GEO | GSE216033 | 274 MB |
| SC0939 | OMIX | OMIX011460 | 608 MB |
| SC0629 | GEO | GSE305843 | 190 MB |
| SN0001 | Zenodo | 10.5281/zenodo.17390399 | ~5 GB (full); 32K stratified subsample (this paper) |

The `scripts/download_data.sh` helper script fetches all of the above
into the expected `data/<DATASET_ID>/` layout. Running this script
requires accepting each repository's terms of use and may take 1-2
hours on a typical connection.

---

## 5. Expected outputs

After a successful full run, the `results/` directory contains:

```
results/
├── embeddings/        # 6 .npy (n_cells, 2048) + 6 .csv metadata
├── metrics/           # Per-rule JSON outputs (12 pairs, 5 seeds, etc.)
├── figures/           # 8 main figures (PNG + PDF)
├── tables/            # 11 markdown tables (Tables 1-3, S1-S13)
├── supplementary/     # 10 supplementary figures (S1-S10)
└── logs/              # Per-rule logs
```

Each PNG in `figures/` and `supplementary/` has a sibling `.pdf`
vector file (for typesetting) and a `.json` metadata sidecar
(containing figure caption + axis labels + colour palette, for
machine-readable reproducibility).

---

## 6. Determinism guarantees

The pipeline is designed for **byte-deterministic re-runs** on the same
hardware. The following knobs are pinned at the environment level:

| Source of non-determinism | Pin in `environment.yml` |
|---|---|
| Python dict ordering | `PYTHONHASHSEED=42` |
| cuBLAS workspace | `CUBLAS_WORKSPACE_CONFIG=":4096:8"` |
| OpenMP thread fan-out | `OMP_NUM_THREADS=8` |
| MKL thread fan-out | `MKL_NUM_THREADS=8` |
| PyTorch seed (set in `xenotransformer/utils/seed.py`) | `torch.manual_seed(42)` |
| NumPy seed | `np.random.seed(42)` |
| Python random | `random.seed(42)` |

Additionally, `torch.use_deterministic_algorithms(True)` is set in
`xenotransformer/utils/seed.py`; if a downstream op does not have a
deterministic implementation (rare; e.g., `torch.scatter_add_` in some
CUDA versions), it will raise a `RuntimeError` rather than silently
producing a different output. This fail-fast behaviour is intentional.

**Bit-identicality is only guaranteed for the same GPU model + driver
version + CUDA version**. Cross-vendor re-runs (e.g., A100 vs V100) may
differ in the last 1-2 decimal places of the floating-point outputs but
will round to the same reported numbers to the precision shown in the
manuscript (1 decimal place for percentages, 3 for pp differences).

---

## 7. Verifying a successful reproduction

After the Snakemake run, the following sanity checks should hold
(match the values reported in the manuscript):

```bash
# Check 1: overall accuracy of SC0926 in-distribution should be 97.75%
jq '.overall_accuracy' results/metrics/single_SC0926.json
# Expected: 0.9775 (or 0.9774-0.9776 due to floating-point variation)

# Check 2: cross-species IC recall SN0001 → SC0926 should be 0.984
jq '.per_type_recall.IC' results/metrics/cross_species_SC0926.json
# Expected: 0.984

# Check 3: L-O-D mean accuracy (4 sets) should be 0.7236
jq '.mean' results/metrics/lod_4set.json
# Expected: 0.7236

# Check 4: Triplet ablation mean improvement should be +0.0223
jq '.delta.plus_triplet_vs_baseline' results/metrics/ablation_aggregated.json
# Expected: 0.0223

# Check 5: figure_1_pipeline.png should be ~165 KB
ls -l results/figures/figure_1_pipeline.png
```

A complete `make verify` target is provided that runs all five checks
and exits 0 only if all match within the documented tolerance.

---

## 8. Cluster / HPC usage (SLURM)

For multi-node execution on a SLURM cluster, use the included
Snakemake profile:

```bash
# Edit profiles/slurm/config.yaml to match your cluster's partition,
# account, and resource limits, then:
snakemake --profile profiles/slurm --use-conda
```

The profile uses `snakemake-executor-plugin-slurm` (v0.5+) and
allocates one GPU per rule. The cross-dataset pair-wise rule is the
most parallelisable (12 independent rules) and scales near-linearly to
12 GPUs.

---

## 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `CUDA out of memory` on A100 80GB | `OMP_NUM_THREADS` too high | Set `OMP_NUM_THREADS=4` in the env |
| `torch.use_deterministic_algorithms` RuntimeError | Some non-deterministic op (e.g., `torch.scatter_add_` in older CUDA) | Upgrade to CUDA 12.4 + driver 550+ |
| `KeyError: 'IC'` in cross-species output | The 32K subsample of SN0001 lost all IC cells (rare; n=968) | Re-run `scripts/stratified_subsample.py` with `--seed 42` |
| `mamba env create` fails on macOS Apple Silicon | `pytorch-cuda` channel is x86_64 only | Use the `nomkl` + `pytorch` (non-CUDA) variant; CPU inference ~30× slower |
| `snakemake` reports `[Errno 28] No space left` | Embedding intermediates are ~1.2 GB each | Need ≥80 GB free; or run subsets (`--until` flag) |

---

## 10. Citation

If you use this pipeline, please cite:

> [Authors]. *XenotransFormer: Cross-Dataset and Cross-Species Cell Type
> Recognition in Pig-to-Primate Xenotransplantation from TranscriptFormer
> Embeddings.* [Journal], 2026. (See `CITATION.cff` for the canonical
> BibTeX entry.)

And the upstream foundation model:

> Pearce, J. *et al.* *TranscriptFormer: a generative foundation model
> for single-cell transcriptomics across 12 species.* **Science** (2026).
> https://github.com/czi-bio/Transcription-Foundation-Model

---

*This reproducibility guide is itself versioned: see `git log` for
changelog. v4.5 (2026-06-23) supersedes v4.0 (initial release).*
