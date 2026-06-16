# ITS Fungal Amplicon Pipeline

## Scope

This pipeline is designed for fungal ITS amplicon sequencing data.

## Input

Paired-end ITS FASTQ files generated from ITS1 or ITS2 amplicon sequencing.

* Example:
- `YZA_ITS_R1.fastq.gz`
- `YZA_ITS_R2.fastq.gz`
- `YZB_ITS_R1.fastq.gz`
- `YZB_ITS_R2.fastq.gz`


## Region and primer examples

- 真菌rDNA:
```
18S rRNA ─ ITS1 ─ 5.8S rRNA ─ ITS2 ─ 28S rRNA
```

- ITS1 region: commonly amplified by ITS1F / ITS2
- ITS2 region: commonly amplified by ITS3 / ITS4
- Full ITS-like region: commonly amplified by ITS1 / ITS4

The actual primer pair must be confirmed with the sequencing provider.

## Scripts
### 00. init project structure
```bash
cat > scripts/run_00_init_project.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "============================================================"
echo "[INFO] 00. Initialize ITS project folders"
echo "============================================================"

mkdir -p raw
mkdir -p metadata
mkdir -p db
mkdir -p scripts
mkdir -p logs
mkdir -p tmp

mkdir -p results/00_raw_qc
mkdir -p results/01_import
mkdir -p results/02_demux_summary
mkdir -p results/03_primer_trimmed
mkdir -p results/04_itsxpress
mkdir -p results/05_dada2
mkdir -p results/06_taxonomy
mkdir -p results/07_taxonomy_delivery

echo
echo "[INFO] Project folders are ready"
find . -maxdepth 2 -type d | sort

echo
echo "============================================================"
echo "[INFO] 00 completed"
echo "============================================================"
EOF

chmod +x scripts/run_00_init_project.sh
```

### 01. raw qc
```bash
cat > scripts/run_01_raw_qc.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

RAW_DIR="${RAW_DIR:-raw}"
OUT_DIR="results/00_raw_qc"

mkdir -p "${OUT_DIR}"

echo "============================================================"
echo "[INFO] 01. Raw ITS FASTQ QC"
echo "============================================================"

command -v seqkit >/dev/null 2>&1 || {
  echo "[ERROR] seqkit command not found"
  echo "[ERROR] Please activate an environment that contains seqkit."
  exit 1
}

if ! compgen -G "${RAW_DIR}/*.fastq.gz" >/dev/null; then
  echo "[ERROR] No FASTQ files found:"
  echo "        ${RAW_DIR}/*.fastq.gz"
  exit 1
fi

echo "[INFO] Writing seqkit stats"

seqkit stats \
  "${RAW_DIR}"/*.fastq.gz \
  > "${OUT_DIR}/seqkit_raw_stats.tsv"

cat "${OUT_DIR}/seqkit_raw_stats.tsv"

echo
echo "============================================================"
echo "[INFO] 01 completed"
echo "============================================================"
EOF

chmod +x scripts/run_01_raw_qc.sh
```

### 02. import
```bash
cd ~/workspaces/Bing/its/ITS_test_project

cat > scripts/run_02_import_fastq.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

MANIFEST="${MANIFEST:-manifest.csv}"
OUT_DIR="results/01_import"

mkdir -p "${OUT_DIR}"

echo "============================================================"
echo "[INFO] 02. Import ITS FASTQ into QIIME 2"
echo "============================================================"

command -v qiime >/dev/null 2>&1 || {
  echo "[ERROR] qiime command not found"
  echo "[ERROR] Please activate your QIIME 2 environment."
  exit 1
}

if [ ! -s "${MANIFEST}" ]; then
  echo "[ERROR] Manifest file missing or empty:"
  echo "        ${MANIFEST}"
  exit 1
fi

qiime tools import \
  --type 'SampleData[PairedEndSequencesWithQuality]' \
  --input-path "${MANIFEST}" \
  --output-path "${OUT_DIR}/paired-end-demux.qza" \
  --input-format PairedEndFastqManifestPhred33V2

echo
echo "============================================================"
echo "[INFO] 02 completed"
echo "[INFO] Output: ${OUT_DIR}/paired-end-demux.qza"
echo "============================================================"
EOF

chmod +x scripts/run_02_import_fastq.sh
```

### 03. demux summary
```bash
cat > scripts/run_03_demux_summarize.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

IN_QZA="results/01_import/paired-end-demux.qza"
OUT_DIR="results/02_demux_summary"

mkdir -p "${OUT_DIR}"

echo "============================================================"
echo "[INFO] 03. Demux summary"
echo "============================================================"

command -v qiime >/dev/null 2>&1 || {
  echo "[ERROR] qiime command not found"
  echo "[ERROR] Please activate your QIIME 2 environment."
  exit 1
}

if [ ! -s "${IN_QZA}" ]; then
  echo "[ERROR] Input QZA missing or empty:"
  echo "        ${IN_QZA}"
  exit 1
fi

qiime demux summarize \
  --i-data "${IN_QZA}" \
  --o-visualization "${OUT_DIR}/paired-end-demux.qzv"

echo
echo "============================================================"
echo "[INFO] 03 completed"
echo "[INFO] Output: ${OUT_DIR}/paired-end-demux.qzv"
echo "============================================================"
EOF

chmod +x scripts/run_03_demux_summarize.sh
```

### 04. primer trim
```bash
cd ~/workspaces/Bing/its/ITS_test_project

cat > scripts/run_04_trim_primers.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

IN_QZA="results/01_import/paired-end-demux.qza"
OUT_DIR="results/03_primer_trimmed"

FORWARD_PRIMER="${FORWARD_PRIMER:-}"
REVERSE_PRIMER="${REVERSE_PRIMER:-}"
DISCARD_UNTRIMMED="${DISCARD_UNTRIMMED:-false}"

mkdir -p "${OUT_DIR}"

echo "============================================================"
echo "[INFO] 04. Trim ITS primers"
echo "============================================================"
echo "[INFO] DISCARD_UNTRIMMED=${DISCARD_UNTRIMMED}"

command -v qiime >/dev/null 2>&1 || {
  echo "[ERROR] qiime command not found"
  echo "[ERROR] Please activate your QIIME 2 environment."
  exit 1
}

if [ ! -s "${IN_QZA}" ]; then
  echo "[ERROR] Input QZA missing or empty:"
  echo "        ${IN_QZA}"
  exit 1
fi

if [ -z "${FORWARD_PRIMER}" ] || [ -z "${REVERSE_PRIMER}" ]; then
  echo "[WARN] FORWARD_PRIMER or REVERSE_PRIMER not provided."
  echo "[WARN] This step will copy input to primer-trimmed.qza without primer trimming."

  cp "${IN_QZA}" "${OUT_DIR}/primer-trimmed.qza"

  qiime demux summarize \
    --i-data "${OUT_DIR}/primer-trimmed.qza" \
    --o-visualization "${OUT_DIR}/primer-trimmed.qzv"

  echo
  echo "============================================================"
  echo "[INFO] 04 completed without primer trimming"
  echo "============================================================"
  exit 0
fi

echo "[INFO] Input: ${IN_QZA}"
echo "[INFO] Forward primer: ${FORWARD_PRIMER}"
echo "[INFO] Reverse primer: ${REVERSE_PRIMER}"

CUTADAPT_ARGS=(
  --i-demultiplexed-sequences "${IN_QZA}"
  --p-front-f "${FORWARD_PRIMER}"
  --p-front-r "${REVERSE_PRIMER}"
  --o-trimmed-sequences "${OUT_DIR}/primer-trimmed.qza"
  --verbose
)

if [ "${DISCARD_UNTRIMMED}" = "true" ]; then
  CUTADAPT_ARGS+=(--p-discard-untrimmed)
fi

qiime cutadapt trim-paired "${CUTADAPT_ARGS[@]}"

qiime demux summarize \
  --i-data "${OUT_DIR}/primer-trimmed.qza" \
  --o-visualization "${OUT_DIR}/primer-trimmed.qzv"

echo
echo "============================================================"
echo "[INFO] 04 completed"
echo "[INFO] Output: ${OUT_DIR}/primer-trimmed.qza"
echo "[INFO] Output: ${OUT_DIR}/primer-trimmed.qzv"
echo "============================================================"
EOF

chmod +x scripts/run_04_trim_primers.sh
```

### 05. itsxpress
```bash
cat > scripts/run_05_itsxpress.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

IN_QZA="results/03_primer_trimmed/primer-trimmed.qza"
OUT_DIR="results/04_itsxpress"

ITS_REGION="${ITS_REGION:-ITS2}"
ITS_TAXA="${ITS_TAXA:-F}"
CLUSTER_ID="${CLUSTER_ID:-1.0}"

mkdir -p "${OUT_DIR}"

echo "============================================================"
echo "[INFO] 05. ITSxpress trimming"
echo "============================================================"
echo "[INFO] ITS_REGION=${ITS_REGION}"
echo "[INFO] ITS_TAXA=${ITS_TAXA}"
echo "[INFO] CLUSTER_ID=${CLUSTER_ID}"

command -v qiime >/dev/null 2>&1 || {
  echo "[ERROR] qiime command not found"
  exit 1
}

if [ ! -s "${IN_QZA}" ]; then
  echo "[ERROR] Input QZA missing or empty:"
  echo "        ${IN_QZA}"
  exit 1
fi

if ! qiime q2-itsxpress --help >/dev/null 2>&1; then
  echo "[ERROR] q2-itsxpress plugin not found in this QIIME 2 environment."
  echo "[ERROR] Please check:"
  echo "        qiime q2-itsxpress --help"
  exit 1
fi

qiime q2-itsxpress trim-pair-output-unmerged \
  --i-per-sample-sequences "${IN_QZA}" \
  --p-region "${ITS_REGION}" \
  --p-taxa "${ITS_TAXA}" \
  --p-cluster-id "${CLUSTER_ID}" \
  --o-trimmed "${OUT_DIR}/itsxpress-trimmed.qza"

qiime demux summarize \
  --i-data "${OUT_DIR}/itsxpress-trimmed.qza" \
  --o-visualization "${OUT_DIR}/itsxpress-trimmed.qzv"

echo
echo "============================================================"
echo "[INFO] 05 completed"
echo "============================================================"
EOF

chmod +x scripts/run_05_itsxpress.sh
```

### 06. dada2 denoising
```bash
cd ~/workspaces/Bing/its/ITS_test_project

cat > scripts/run_06_dada2.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

IN_QZA="results/04_itsxpress/itsxpress-trimmed.qza"
OUT_DIR="results/05_dada2"

TRUNC_LEN_F="${TRUNC_LEN_F:-0}"
TRUNC_LEN_R="${TRUNC_LEN_R:-0}"
TRIM_LEFT_F="${TRIM_LEFT_F:-0}"
TRIM_LEFT_R="${TRIM_LEFT_R:-0}"
THREADS="${THREADS:-0}"

mkdir -p "${OUT_DIR}"

echo "============================================================"
echo "[INFO] 06. DADA2 denoise paired ITS reads"
echo "============================================================"
echo "[INFO] Input: ${IN_QZA}"
echo "[INFO] TRUNC_LEN_F=${TRUNC_LEN_F}"
echo "[INFO] TRUNC_LEN_R=${TRUNC_LEN_R}"
echo "[INFO] TRIM_LEFT_F=${TRIM_LEFT_F}"
echo "[INFO] TRIM_LEFT_R=${TRIM_LEFT_R}"
echo "[INFO] THREADS=${THREADS}"

command -v qiime >/dev/null 2>&1 || {
  echo "[ERROR] qiime command not found"
  exit 1
}

if [ ! -s "${IN_QZA}" ]; then
  echo "[ERROR] Input QZA missing or empty:"
  echo "        ${IN_QZA}"
  exit 1
fi

qiime dada2 denoise-paired \
  --i-demultiplexed-seqs "${IN_QZA}" \
  --p-trunc-len-f "${TRUNC_LEN_F}" \
  --p-trunc-len-r "${TRUNC_LEN_R}" \
  --p-trim-left-f "${TRIM_LEFT_F}" \
  --p-trim-left-r "${TRIM_LEFT_R}" \
  --p-n-threads "${THREADS}" \
  --o-table "${OUT_DIR}/table.qza" \
  --o-representative-sequences "${OUT_DIR}/rep-seqs.qza" \
  --o-denoising-stats "${OUT_DIR}/denoising-stats.qza"

qiime metadata tabulate \
  --m-input-file "${OUT_DIR}/denoising-stats.qza" \
  --o-visualization "${OUT_DIR}/denoising-stats.qzv"

qiime feature-table summarize \
  --i-table "${OUT_DIR}/table.qza" \
  --o-visualization "${OUT_DIR}/table.qzv"

qiime feature-table tabulate-seqs \
  --i-data "${OUT_DIR}/rep-seqs.qza" \
  --o-visualization "${OUT_DIR}/rep-seqs.qzv"

echo
echo "============================================================"
echo "[INFO] 06 completed"
echo "[INFO] Output: ${OUT_DIR}/table.qza"
echo "[INFO] Output: ${OUT_DIR}/rep-seqs.qza"
echo "[INFO] Output: ${OUT_DIR}/denoising-stats.qza"
echo "============================================================"
EOF

chmod +x scripts/run_06_dada2.sh
```

### 07. taxonomy assignment
```bash
cd ~/workspaces/Bing/its/ITS_test_project

cat > scripts/run_07_taxonomy_delivery.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

TABLE_QZA="results/05_dada2/table.qza"
REP_SEQS_QZA="results/05_dada2/rep-seqs.qza"

UNITE_CLASSIFIER="${UNITE_CLASSIFIER:-/home/adprc/databases/its/unite/v10_2025_02_19_fungi/qiime2-amplicon-2024.5/unite_classifier_dynamic.qza}"

OUT_DIR="results/06_taxonomy"
EXPORT_DIR="${OUT_DIR}/exported"

THREADS="${THREADS:-12}"

mkdir -p "${OUT_DIR}" "${EXPORT_DIR}"

echo "============================================================"
echo "[INFO] 07. Taxonomy assignment and delivery tables"
echo "============================================================"
echo "[INFO] TABLE_QZA=${TABLE_QZA}"
echo "[INFO] REP_SEQS_QZA=${REP_SEQS_QZA}"
echo "[INFO] UNITE_CLASSIFIER=${UNITE_CLASSIFIER}"
echo "[INFO] THREADS=${THREADS}"

command -v qiime >/dev/null 2>&1 || {
  echo "[ERROR] qiime command not found"
  echo "[ERROR] Please activate your QIIME 2 environment."
  exit 1
}

command -v biom >/dev/null 2>&1 || {
  echo "[ERROR] biom command not found"
  echo "[ERROR] Please install biom-format in the current environment."
  exit 1
}

command -v python >/dev/null 2>&1 || {
  echo "[ERROR] python command not found"
  exit 1
}

if [ ! -s "${TABLE_QZA}" ]; then
  echo "[ERROR] table.qza missing or empty:"
  echo "        ${TABLE_QZA}"
  exit 1
fi

if [ ! -s "${REP_SEQS_QZA}" ]; then
  echo "[ERROR] rep-seqs.qza missing or empty:"
  echo "        ${REP_SEQS_QZA}"
  exit 1
fi

if [ ! -s "${UNITE_CLASSIFIER}" ]; then
  echo "[ERROR] UNITE classifier missing or empty:"
  echo "        ${UNITE_CLASSIFIER}"
  exit 1
fi

echo
echo "[INFO] Check classifier artifact"
qiime tools peek "${UNITE_CLASSIFIER}"

echo
echo "[INFO] Assign taxonomy with classify-sklearn"
qiime feature-classifier classify-sklearn \
  --i-classifier "${UNITE_CLASSIFIER}" \
  --i-reads "${REP_SEQS_QZA}" \
  --p-n-jobs "${THREADS}" \
  --o-classification "${OUT_DIR}/taxonomy.qza"

echo
echo "[INFO] Create taxonomy visualization"
qiime metadata tabulate \
  --m-input-file "${OUT_DIR}/taxonomy.qza" \
  --o-visualization "${OUT_DIR}/taxonomy.qzv"

echo
echo "[INFO] Create taxonomy barplot if metadata.tsv exists"
if [ -s "metadata.tsv" ]; then
  qiime taxa barplot \
    --i-table "${TABLE_QZA}" \
    --i-taxonomy "${OUT_DIR}/taxonomy.qza" \
    --m-metadata-file metadata.tsv \
    --o-visualization "${OUT_DIR}/taxa-bar-plots.qzv"
else
  echo "[WARN] metadata.tsv not found. Skip taxa barplot."
fi

echo
echo "[INFO] Export taxonomy.tsv"
qiime tools export \
  --input-path "${OUT_DIR}/taxonomy.qza" \
  --output-path "${EXPORT_DIR}/taxonomy"

cp "${EXPORT_DIR}/taxonomy/taxonomy.tsv" "${OUT_DIR}/taxonomy.tsv"

echo
echo "[INFO] Export representative sequences FASTA"
qiime tools export \
  --input-path "${REP_SEQS_QZA}" \
  --output-path "${EXPORT_DIR}/rep_seqs"

cp "${EXPORT_DIR}/rep_seqs/dna-sequences.fasta" "${OUT_DIR}/rep_seqs.fasta"

echo
echo "[INFO] Export feature table counts"
qiime tools export \
  --input-path "${TABLE_QZA}" \
  --output-path "${EXPORT_DIR}/feature_table"

biom convert \
  -i "${EXPORT_DIR}/feature_table/feature-table.biom" \
  -o "${OUT_DIR}/feature_table.tsv" \
  --to-tsv

echo
echo "[INFO] Build relative abundance table"
qiime feature-table relative-frequency \
  --i-table "${TABLE_QZA}" \
  --o-relative-frequency-table "${OUT_DIR}/feature_table_relative.qza"

qiime tools export \
  --input-path "${OUT_DIR}/feature_table_relative.qza" \
  --output-path "${EXPORT_DIR}/feature_table_relative"

biom convert \
  -i "${EXPORT_DIR}/feature_table_relative/feature-table.biom" \
  -o "${OUT_DIR}/feature_table_relative_abundance.tsv" \
  --to-tsv

echo
echo "[INFO] Merge feature table and taxonomy"
python - <<'PY'
import pandas as pd
from pathlib import Path

out_dir = Path("results/06_taxonomy")

feature_table_path = out_dir / "feature_table.tsv"
taxonomy_path = out_dir / "taxonomy.tsv"
merged_path = out_dir / "feature_taxonomy_table.tsv"

# QIIME/BIOM exported table usually has one metadata/comment line first.
feature_df = pd.read_csv(feature_table_path, sep="\t", skiprows=1)

# First column is usually '#OTU ID'
feature_df = feature_df.rename(columns={feature_df.columns[0]: "Feature ID"})

tax_df = pd.read_csv(taxonomy_path, sep="\t")

merged = feature_df.merge(tax_df, on="Feature ID", how="left")

# Put taxonomy columns after Feature ID for readability
front_cols = ["Feature ID"]
tax_cols = [c for c in ["Taxon", "Confidence"] if c in merged.columns]
sample_cols = [c for c in merged.columns if c not in front_cols + tax_cols]

merged = merged[front_cols + tax_cols + sample_cols]
merged.to_csv(merged_path, sep="\t", index=False)

print(f"[INFO] Wrote: {merged_path}")
print(f"[INFO] Features: {merged.shape[0]}")
print(f"[INFO] Columns: {merged.shape[1]}")
PY

echo
echo "============================================================"
echo "[INFO] 07 completed"
echo "============================================================"
echo "[INFO] Main outputs:"
echo "  ${OUT_DIR}/taxonomy.qza"
echo "  ${OUT_DIR}/taxonomy.qzv"
echo "  ${OUT_DIR}/taxonomy.tsv"
echo "  ${OUT_DIR}/feature_table.tsv"
echo "  ${OUT_DIR}/feature_table_relative_abundance.tsv"
echo "  ${OUT_DIR}/feature_taxonomy_table.tsv"
echo "  ${OUT_DIR}/rep_seqs.fasta"
echo "============================================================"
EOF

chmod +x scripts/run_07_taxonomy_delivery.sh
```

## Workflow
### 1. Initialize project structure
```bash
bash scripts/run_00_init_project.sh
```

### 2. Raw QC
```bash
conda activate host-tools
```

```bash
bash scripts/run_01_raw_qc.sh
```

檢查QC結果：
```bash
cat results/00_raw_qc/seqkit_raw_stats.tsv
```

### 3. Import FASTQ into QIIME 2
Environment:
- QIIME 2 amplicon
- q2-itsxpress
- itsxpress
- bbmap / bbmerge.sh
- cutadapt
- dada2
- feature-classifier
```bash
conda activate qiime2-amplicon-2024.5
```
```bash
bash scripts/run_02_import_fastq.sh
```

### 4. Demux summary
```bash
bash scripts/run_03_demux_summarize.sh
```
### 5. Trim primers
```bash
FORWARD_PRIMER=GCATCGATGAAGAACGCAGC \
REVERSE_PRIMER=TCCTCCGCTTATTGATATGC \
bash scripts/run_04_trim_primers.sh
```

### 6. ITSxpress
指定 ITS_REGION 和 ITS_TAXA 為 F(Fungi) 以適應不同的實驗設計和目標物種群：
```bash
ITS_REGION=ITS2 \
ITS_TAXA=F \
bash scripts/run_05_itsxpress.sh
```

### 7. DADA2 denoising
```bash
THREADS=12 \
TRUNC_LEN_F=0 \
TRUNC_LEN_R=0 \
bash scripts/run_06_dada2.sh
```

### 8. Taxonomy assignment and delivery tables
```bash
THREADS=12 \
bash scripts/run_07_taxonomy_delivery.sh
```

## UNITE ITS database

Database: [UNITE QIIME](https://unite.ut.ee/repository.php) release for Fungi 2  
Version: 19.02.2025  
UNITE version: 10.0  
DOI: 10.15156/BIO/3301242  
Taxon group: Fungi  
Notes: Includes global and 3% distance singletons.  
QIIME 2 environment: qiime2-amplicon-2024.5  
Classifier: locally trained with q2-feature-classifier fit-classifier-naive-bayes

```
Abarenkov, Kessy; Zirk, Allan; Piirmann, Timo; Pöhönen, Raivo; Ivanov, Filipp; Nilsson, R. Henrik; Kõljalg, Urmas (2025): UNITE QIIME release for Fungi 2. Version 19.02.2025. UNITE Community. https://doi.org/10.15156/BIO/3301242
```