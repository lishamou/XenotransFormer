# XenotransFormer — Reproducible Docker image
# Builds a self-contained environment that reproduces every figure, table,
# and supplementary item in the manuscript with a single command:
#   docker run --rm -v $(pwd)/results:/work/results \
#     ghcr.io/<owner>/xenotransformer:v4.5
# or interactively:
#   docker run --rm -it --gpus all \
#     -v $(pwd)/results:/work/results \
#     -v $(pwd)/data:/work/data:ro \
#     ghcr.io/<owner>/xenotransformer:v4.5 bash
#
# Image layers:
#   1. NVIDIA CUDA 12.4 + cuDNN 9.2 base (debian12, python 3.11)
#   2. conda environment from environment.yml
#   3. xenotransformer package + TranscriptFormer (pip -e)
#   4. Non-root user, deterministic seeds, OMP/MKL cap
#   5. Default entrypoint: snakemake --cores 8

# ============================================================
# Stage 1: CUDA base + system dependencies
# ============================================================
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04 AS base

# Disable interactive prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONHASHSEED=42 \
    PYTHONUNBUFFERED=1 \
    HDF5_USE_FILE_LOCKING=FALSE \
    OMP_NUM_THREADS=8 \
    MKL_NUM_THREADS=8 \
    CUBLAS_WORKSPACE_CONFIG=":4096:8" \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# System packages (kept minimal for reproducibility — no late updates)
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates=20230311 \
        wget=1.21.2-2ubuntu1 \
        curl=7.81.0-1ubuntu1.16 \
        git=1:2.34.1-1ubuntu1.11 \
        build-essential=12.9ubuntu3 \
        libgl1=1.4.0-1 \
        libglib2.0-0=2.72.4-0ubuntu2.2 \
        libgeos=3.10.2-1 \
        libhdf5-dev=1.10.7+repack-4ubuntu2 \
        libffi-dev=3.4.2-4 \
        libssl-dev=3.0.2-0ubuntu1.15 \
        libxml2-dev=2.9.13+dfsg-1ubuntu0.4 \
        libxslt1-dev=1.1.34-4ubuntu0.22.04.1 \
        libblas-dev=3.10.0-2ubuntu1 \
        liblapack-dev=3.10.0-2ubuntu1 \
        libgomp1=12.3.0-1ubuntu1~22.04 \
        zlib1g-dev=1:1.2.11.dfsg-2ubuntu9.2 \
        graphviz=2.42.2-6 \
        graphviz-dev=2.42.2-6 \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Stage 2: Conda + mamba installation (faster solver)
# ============================================================
RUN curl -fsSL https://repo.anaconda.com/miniconda/Miniconda3-py311_24.9.2-0-Linux-x86_64.sh \
        -o /tmp/miniconda.sh \
    && bash /tmp/miniconda.sh -b -p /opt/conda \
    && rm /tmp/miniconda.sh \
    && /opt/conda/bin/conda clean -afy \
    && /opt/conda/bin/conda install -n base -c conda-forge -y mamba=1.5.8 \
    && /opt/conda/bin/conda clean -afy

ENV PATH="/opt/conda/bin:$PATH"

# ============================================================
# Stage 3: Conda environment from environment.yml
# ============================================================
WORKDIR /work
COPY environment.yml xenotransformer_pkg/ ./xenotransformer_pkg/
RUN mamba env create -f environment.yml \
    && mamba clean -afy \
    && /opt/conda/bin/conda run -n xenotransformer \
        pip install --no-cache-dir ./xenotransformer_pkg

# ============================================================
# Stage 4: TranscriptFormer (CZI Biohub) — frozen, inference only
# ============================================================
ARG TRANSCRIPTFORMER_REF=v2026.03.0
RUN /opt/conda/bin/conda run -n xenotransformer \
        pip install --no-cache-dir \
        git+https://github.com/czi-bio/Transcription-Foundation-Model.git@${TRANSCRIPTFORMER_REF}

# ============================================================
# Stage 5: Copy Snakemake pipeline + scripts
# ============================================================
COPY Snakefile config/ scripts/ ./
RUN chmod -R a+rX /work

# ============================================================
# Stage 6: Non-root user for security + reproducibility
# ============================================================
RUN useradd -m -s /bin/bash -u 1000 xenotransformer \
    && chown -R xenotransformer:xenotransformer /work
USER xenotransformer

# Verify CUDA is visible at build time (smoke test; not a runtime guarantee)
RUN /opt/conda/bin/conda run -n xenotransformer python -c \
    "import torch; print('CUDA available:', torch.cuda.is_available()); \
     print('Device count:', torch.cuda.device_count()); \
     print('PyTorch:', torch.__version__)"

# ============================================================
# Stage 7: Health check + entrypoint
# ============================================================
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD /opt/conda/bin/conda run -n xenotransformer \
        python -c "import torch, scanpy, snakemake; print('OK')" || exit 1

# Default entrypoint: run the full Snakemake pipeline
# Override examples:
#   --entrypoint bash                 # interactive shell
#   snakemake results/figures/figure_1_pipeline.png  # single rule
#   snakemake --cores 16             # parallel
ENTRYPOINT ["/opt/conda/bin/conda", "run", "--no-capture-output", "-n", "xenotransformer"]
CMD ["snakemake", "--cores", "8", "--use-conda", "--printshellcmds", \
     "--rerun-triggers", "mtime", "--keep-going"]

# Metadata
LABEL org.opencontainers.image.title="XenotransFormer" \
      org.opencontainers.image.description="Cross-dataset and cross-species cell type recognition in pig-to-primate xenotransplantation from TranscriptFormer embeddings" \
      org.opencontainers.image.source="https://github.com/<owner>/xenotransformer" \
      org.opencontainers.image.licenses="CC-BY-4.0" \
      org.opencontainers.image.version="v4.5" \
      org.opencontainers.image.documentation="https://github.com/<owner>/xenotransformer/blob/main/REPRODUCIBILITY.md"
