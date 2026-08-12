# XenotransFormer — Reference-composition Coupling Audit

This repository contains the analysis code for the manuscript:

> **Reference composition biases automated cell annotation and obscures biological signals in xenotransplantation single-cell atlases**

## What's here

```
Snakefile              # 14-rule DAG (see REPRODUCIBILITY.md §4)
environment.yml        # conda + pip, 56 packages pinned
Dockerfile             # nvidia/cuda:12.4.1 multi-stage
REPRODUCIBILITY.md     # 10-section reproducibility guide

config/
  paper_config.yaml    # paper-wide config (datasets, classifier, metrics)
profiles/slurm/
  config.yaml          # HPC cluster config

code/
  prior_sensitivity_diagnostic.py   # THE diagnostic (tempered_prior_curve, composition_correlation, …)
  06_multitarget_diagnostic.py       # multi-target prior-sensitivity
  15_generality_diagnostic.py        # 2nd-pig + non-xeno (kidney, lung) generality
  biomni_benchmark/                  # Biomni A1 reference-free evaluation
    run_biomni.py                     # pipeline driver
    score_biomni.py / score_all.py    # recall / F1 / per-class comparison
    prep_target.py / prep_targets.py  # build target.h5ad + ground_truth.csv
    export_figS_biomni.py             # render FigS4
    driver.sh                         # one-command launcher

results/
  biomni_benchmark/
    biomni_benchmark_summary.json     # per-class recall (SC0926, SC0924)
    biomni_vs_truth.json              # confusion matrices
```

## Re-run the diagnostic

```bash
# Option A: Docker (recommended)
docker build -t xenotransformer .
docker run --rm -v $(pwd)/results:/xenotransformer/results xenotransformer \
    snakemake --cores 8

# Option B: conda
conda env create -f environment.yml
conda activate xenotransformer
snakemake --cores 8

# Option C: direct
python code/prior_sensitivity_diagnostic.py \
    --reference h5ad_or_csv --target h5ad_or_csv --output results/
```

See `REPRODUCIBILITY.md` §4 for the full Snakefile plan and per-rule resource
allocations.

## Citation

If you use this code or the diagnostic, please cite the manuscript and the
data-deposit DOI on Zenodo (see `data_availability` statement in the manuscript).

## License

- Code: MIT
- Embedded per-cell CORE labels: CC-BY-4.0

