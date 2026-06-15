# Shotgun Metagenomics Pipeline
Metagenomics SOP 定位

1. 用途： analysis
2. 輸入：.R1.fastq.gz + .R2.fastq.gz + metadata.tsv
3. 核心工具：fastp + kraken2 + bracken + R/Python plotting
4. 輸出：統計圖、pathway、heatmap、barplot

* fastp = 原始 reads 品質控制、adapter trimming 與低品質 reads 過濾
* Bowtie2 = 對人類基因組 index 比對，去除宿主 reads
* MetaPhlAn = marker-based taxonomy profiling
* Kraken2 = k-mer-based taxonomy classification
* Bracken = 依據 Kraken2 report 重新估算 genus / species abundance
* HUMAnN = gene family、pathway abundance 與 pathway coverage profiling
* R / Python = 下游統計分析與繪圖

```
host-tools
└── fastp、seqkit、Bowtie2
    用於 QC 與去宿主 reads

metagenomics-taxonomy
└── MetaPhlAn 4.2.4 + vJan25 DB
    用於正式 taxonomy profiling

metagenomics-humann
└── HUMAnN 3.9 + MetaPhlAn 4.1.1 + vJun23 DB
    用於 functional profiling
```

### Shared databases:
```bash
/home/adprc/host_genome/
└── 人類基因組 Bowtie2 index

/home/adprc/databases/metagenomics/
├── metaphlan/
│   └── mpa_vJan25_CHOCOPhlAnSGB_202503
│       # 正式 taxonomy profiling
│
├── metaphlan_vJun23/
│   └── mpa_vJun23_CHOCOPhlAnSGB_202403
│       # HUMAnN 3.9 相容版本
│
├── kraken2/
│   └── standard/
│       # Kraken2 Standard DB + Bracken 150-mer DB
│
└── humann/
    ├── chocophlan/
    │   └── chocophlan/
    │       # nucleotide search DB
    │
    └── uniref/
        └── uniref/
            # UniRef90 DIAMOND protein DB
```

### Repo Structure:
```bash
WMS_project/
├── raw/
│   ├── YZA_R1.fq.gz -> symbolic link to original FASTQ
│   ├── YZA_R2.fq.gz -> symbolic link to original FASTQ
│   ├── YZB_R1.fq.gz -> symbolic link to original FASTQ
│   └── YZB_R2.fq.gz -> symbolic link to original FASTQ
│
├── metadata/
│   └── metadata.tsv
│       # 下游統計分析與繪圖使用
│
├── scripts/
│   ├── run_01_fastp.sh
│   ├── run_02_dehost_human.sh
│   ├── run_03_metaphlan.sh
│   ├── run_03b_metaphlan_humann_compatible.sh
│   ├── run_04_kraken2.sh
│   ├── run_05_bracken_species.sh
│   ├── run_05_bracken_genus.sh
│   ├── run_06_merge_taxonomy_tables.sh
│   ├── run_07_humann.sh
│   └── run_08_humann_tables.sh
│
├── db/
│   └── README.md
│       # 紀錄共用 DB 的絕對路徑與版本
│       # 不在專案內重複儲存大型 DB
│
├── tmp/
│   ├── kraken2_test/
│   └── humann_input/
│       # 暫存檔，可於確認分析成功後清除
│
├── logs/
│   └── pipeline.log
│       # 選配：未來建立總流程 script 時使用
│
└── results/
    ├── 00_raw_qc/
    │   └── seqkit_raw_stats.tsv
    │
    ├── 01_fastp/
    │   ├── clean_reads/
    │   │   ├── YZA_R1.clean.fq.gz
    │   │   ├── YZA_R2.clean.fq.gz
    │   │   ├── YZB_R1.clean.fq.gz
    │   │   └── YZB_R2.clean.fq.gz
    │   │
    │   ├── reports/
    │   │   ├── YZA.fastp.html
    │   │   ├── YZA.fastp.json
    │   │   ├── YZB.fastp.html
    │   │   └── YZB.fastp.json
    │   │
    │   ├── logs/
    │   │   ├── YZA.fastp.log
    │   │   └── YZB.fastp.log
    │   │
    │   └── seqkit_clean_stats.tsv
    │
    ├── 02_dehost/
    │   ├── clean_reads/
    │   │   ├── YZA_R1.dehost.fq.gz
    │   │   ├── YZA_R2.dehost.fq.gz
    │   │   ├── YZB_R1.dehost.fq.gz
    │   │   └── YZB_R2.dehost.fq.gz
    │   │
    │   ├── logs/
    │   │   ├── YZA.bowtie2.log
    │   │   └── YZB.bowtie2.log
    │   │
    │   └── seqkit_dehost_stats.tsv
    │
    ├── 03_metaphlan/
    │   ├── profiles/
    │   │   ├── YZA_profile.txt
    │   │   └── YZB_profile.txt
    │   │
    │   ├── bowtie2out/
    │   │   ├── YZA.bowtie2.bz2
    │   │   └── YZB.bowtie2.bz2
    │   │
    │   └── logs/
    │       ├── YZA.metaphlan.log
    │       └── YZB.metaphlan.log
    │
    ├── 03b_metaphlan_humann_compatible/
    │   ├── profiles/
    │   │   ├── YZA_profile.txt
    │   │   └── YZB_profile.txt
    │   │
    │   ├── bowtie2out/
    │   │   ├── YZA.bowtie2.bz2
    │   │   └── YZB.bowtie2.bz2
    │   │
    │   └── logs/
    │       ├── YZA.metaphlan.log
    │       └── YZB.metaphlan.log
    │
    ├── 04_kraken2/
    │   ├── reports/
    │   │   ├── YZA.kraken2.report.tsv
    │   │   └── YZB.kraken2.report.tsv
    │   │
    │   ├── outputs/
    │   │   ├── YZA.kraken2.read_classification.tsv
    │   │   └── YZB.kraken2.read_classification.tsv
    │   │
    │   └── logs/
    │       ├── YZA.kraken2.log
    │       └── YZB.kraken2.log
    │
    ├── 05_bracken/
    │   ├── species/
    │   ├── genus/
    │   ├── family/
    │   ├── order/
    │   ├── class/
    │   ├── phylum/
    │   └── logs/
    │
    ├── 06_taxonomy_tables/
    │   ├── metaphlan/
    │   │   ├── metaphlan_all_levels_relative_abundance.tsv
    │   │   ├── metaphlan_phylum_relative_abundance.tsv
    │   │   ├── metaphlan_class_relative_abundance.tsv
    │   │   ├── metaphlan_order_relative_abundance.tsv
    │   │   ├── metaphlan_family_relative_abundance.tsv
    │   │   ├── metaphlan_genus_relative_abundance.tsv
    │   │   ├── metaphlan_species_relative_abundance.tsv
    │   │   ├── metaphlan_marker_coverage.tsv
    │   │   └── metaphlan_estimated_reads.tsv
    │   │
    │   ├── kraken2/
    │   │   ├── kraken2_observed_tree_relative_abundance.tsv
    │   │   ├── kraken2_observed_tree_clade_reads.tsv
    │   │   ├── kraken2_phylum_relative_abundance.tsv
    │   │   ├── kraken2_class_relative_abundance.tsv
    │   │   ├── kraken2_order_relative_abundance.tsv
    │   │   ├── kraken2_family_relative_abundance.tsv
    │   │   ├── kraken2_genus_relative_abundance.tsv
    │   │   └── kraken2_species_relative_abundance.tsv
    │   │
    │   └── bracken/
    │       ├── bracken_phylum_relative_abundance.tsv
    │       ├── bracken_phylum_estimated_reads.tsv
    │       ├── bracken_class_relative_abundance.tsv
    │       ├── bracken_class_estimated_reads.tsv
    │       ├── bracken_order_relative_abundance.tsv
    │       ├── bracken_order_estimated_reads.tsv
    │       ├── bracken_family_relative_abundance.tsv
    │       ├── bracken_family_estimated_reads.tsv
    │       ├── bracken_genus_relative_abundance.tsv
    │       ├── bracken_genus_estimated_reads.tsv
    │       ├── bracken_species_relative_abundance.tsv
    │       └── bracken_species_estimated_reads.tsv
    │
    ├── 07_humann/
    │   ├── YZA/
    │   │   ├── YZA_genefamilies.tsv
    │   │   ├── YZA_pathabundance.tsv
    │   │   └── YZA_pathcoverage.tsv
    │   │
    │   ├── YZB/
    │   │   ├── YZB_genefamilies.tsv
    │   │   ├── YZB_pathabundance.tsv
    │   │   └── YZB_pathcoverage.tsv
    │   │
    │   └── logs/
    │       ├── YZA.humann.log
    │       └── YZB.humann.log
    │
    └── 08_humann_tables/
        ├── normalized/
        │   ├── YZA_genefamilies_cpm.tsv
        │   ├── YZA_pathabundance_relab.tsv
        │   ├── YZA_pathcoverage.tsv
        │   ├── YZB_genefamilies_cpm.tsv
        │   ├── YZB_pathabundance_relab.tsv
        │   └── YZB_pathcoverage.tsv
        │
        ├── humann_genefamilies_cpm.tsv
        ├── humann_pathabundance_relab.tsv
        └── humann_pathcoverage.tsv
    └── assembly_based/
        ├── U01_assembly/
        ├── U02_gene_prediction/
        ├── U03_unigene_catalog/
        ├── U04_mapping/
        ├── U05_unigene_abundance/
        ├── U06_taxonomy_annotation/
        ├── U07_function_annotation/
        └── U08_delivery_tables/        
```

### Process Flow:
```bash
Raw paired-end FASTQ
│
├── 00. Project initialization
│   └── 建立 scripts、tmp 與 results 資料夾骨架
│
├── 01. Read QC / trimming
│   └── fastp
│
├── 02. Strict human-host removal
│   ├── Bowtie2 對 human genome index 比對
│   └── 僅保留 R1 與 R2 均 unmapped 的完整 read pairs
│
└── results/02_dehost/clean_reads/*.dehost.fq.gz
    │
    ├── A. Reference-based profiling branch
    │   ├── 03. MetaPhlAn taxonomy profiling
    │   ├── 03b. HUMAnN-compatible MetaPhlAn profiling
    │   ├── 04. Kraken2 classification
    │   ├── 05. Bracken rank-specific abundance re-estimation
    │   ├── 06. Taxonomy table merging
    │   ├── 07. HUMAnN functional profiling
    │   └── 08. HUMAnN table merging
    │
    └── B. Assembly-based unigene catalog branch
        ├── U01. MEGAHIT per-sample assembly
        ├── U02. Prodigal gene prediction
        ├── U03. Non-redundant unigene catalog construction
        ├── U04. Reads mapping back to unigene catalog
        ├── U05. Unigene quantification
        ├── U06. Taxonomy annotation
        ├── U07. Functional annotation
        └── U08. Delivery-table construction
```

### Shell Script Template:

#### 00. Initial setup
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/run_00_init_project.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Initialize shotgun metagenomics project folders
#
# This script only creates folders.
# It does not overwrite, move, or delete existing files.
# ==============================================================================

echo "============================================================"
echo "[INFO] Initializing shotgun metagenomics project structure"
echo "============================================================"

# ------------------------------------------------------------------------------
# Project-level folders
# ------------------------------------------------------------------------------

mkdir -p raw
mkdir -p metadata
mkdir -p db
mkdir -p logs
mkdir -p tmp

# ------------------------------------------------------------------------------
# Script folders
# ------------------------------------------------------------------------------

mkdir -p scripts
mkdir -p scripts/assembly_based
mkdir -p scripts/deprecated

# ------------------------------------------------------------------------------
# Common upstream results
# ------------------------------------------------------------------------------

mkdir -p results/00_raw_qc

mkdir -p results/01_fastp/clean_reads
mkdir -p results/01_fastp/reports
mkdir -p results/01_fastp/logs

mkdir -p results/02_dehost/clean_reads
mkdir -p results/02_dehost/tmp
mkdir -p results/02_dehost/logs

# ------------------------------------------------------------------------------
# Reference-based taxonomy branch
# ------------------------------------------------------------------------------

mkdir -p results/03_metaphlan/profiles
mkdir -p results/03_metaphlan/read_stats
mkdir -p results/03_metaphlan/bowtie2out
mkdir -p results/03_metaphlan/logs

mkdir -p results/03b_metaphlan_humann_compatible/profiles
mkdir -p results/03b_metaphlan_humann_compatible/bowtie2out
mkdir -p results/03b_metaphlan_humann_compatible/logs

mkdir -p results/04_kraken2/reports
mkdir -p results/04_kraken2/outputs
mkdir -p results/04_kraken2/logs

for rank_name in phylum class order family genus species; do
  mkdir -p "results/05_bracken/${rank_name}"
done

mkdir -p results/05_bracken/logs

mkdir -p results/06_taxonomy_tables/metaphlan
mkdir -p results/06_taxonomy_tables/kraken2
mkdir -p results/06_taxonomy_tables/bracken

# ------------------------------------------------------------------------------
# Reference-based functional branch
# ------------------------------------------------------------------------------

mkdir -p results/07_humann/logs
mkdir -p results/08_humann_tables/normalized

mkdir -p tmp/humann_input

# ------------------------------------------------------------------------------
# Assembly-based unigene branch
# ------------------------------------------------------------------------------

mkdir -p results/assembly_based/U01_assembly/logs
mkdir -p results/assembly_based/U02_gene_prediction/logs
mkdir -p results/assembly_based/U03_unigene_catalog/logs
mkdir -p results/assembly_based/U04_mapping/logs
mkdir -p results/assembly_based/U05_unigene_abundance
mkdir -p results/assembly_based/U06_taxonomy_annotation/diamond
mkdir -p results/assembly_based/U06_taxonomy_annotation/tables
mkdir -p results/assembly_based/U06_taxonomy_annotation/rank_tables
mkdir -p results/assembly_based/U06_taxonomy_annotation/delivery_like
mkdir -p results/assembly_based/U06_taxonomy_annotation/logs
mkdir -p results/assembly_based/U07_function_annotation/logs
mkdir -p results/assembly_based/U08_delivery_tables


echo
echo "[INFO] Project folders are ready"
echo
echo "[INFO] Top-level folders:"
find . \
  -maxdepth 2 \
  -type d \
  | sort

echo
echo "============================================================"
echo "[INFO] Initialization completed"
echo "============================================================"
EOF

chmod +x scripts/run_00_init_project.sh
```

#### 01. fastp
```bash
#!/usr/bin/env bash
set -euo pipefail

mkdir -p results/01_fastp/clean_reads
mkdir -p results/01_fastp/reports
mkdir -p results/01_fastp/logs

for sample in YZA YZB; do
  echo "[INFO] Running fastp for ${sample}"

  fastp \
    -i raw/${sample}_R1.fq.gz \
    -I raw/${sample}_R2.fq.gz \
    -o results/01_fastp/clean_reads/${sample}_R1.clean.fq.gz \
    -O results/01_fastp/clean_reads/${sample}_R2.clean.fq.gz \
    -h results/01_fastp/reports/${sample}.fastp.html \
    -j results/01_fastp/reports/${sample}.fastp.json \
    -w 8 \
    2> results/01_fastp/logs/${sample}.fastp.log

  echo "[INFO] Done: ${sample}"
done

seqkit stats results/01_fastp/clean_reads/*.clean.fq.gz \
  > results/01_fastp/seqkit_clean_stats.tsv
EOF

chmod +x scripts/run_01_fastp.sh
```

#### 02. dehost
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/run_02_dehost_human.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Strict human-host removal for paired-end shotgun metagenomics reads
#
# Required conda environment:
#   conda activate host-tools
#
# Input:
#   results/01_fastp/clean_reads/<sample>_R1.clean.fq.gz
#   results/01_fastp/clean_reads/<sample>_R2.clean.fq.gz
#
# Output:
#   results/02_dehost/clean_reads/<sample>_R1.dehost.fq.gz
#   results/02_dehost/clean_reads/<sample>_R2.dehost.fq.gz
#
# Retention rule:
#   Keep a read pair only when BOTH mates are unmapped to the human reference.
#
# Notes:
#   SAM flag 0x4 = read unmapped
#   SAM flag 0x8 = mate unmapped
#   samtools view -f 12 retains records with both flags set.
# ==============================================================================

HOST_INDEX="/home/adprc/host_genome/genome_index/human_genome/host_genome_index"
THREADS=12

FASTP_DIR="results/01_fastp/clean_reads"
OUT_DIR="results/02_dehost"
CLEAN_DIR="${OUT_DIR}/clean_reads"
TMP_DIR="${OUT_DIR}/tmp"
LOG_DIR="${OUT_DIR}/logs"

SAMPLES=(
  "YZA"
  "YZB"
)

mkdir -p "${CLEAN_DIR}"
mkdir -p "${TMP_DIR}"
mkdir -p "${LOG_DIR}"

# ==============================================================================
# Preflight checks
# ==============================================================================

command -v bowtie2 >/dev/null 2>&1 || {
  echo "[ERROR] bowtie2 command not found"
  echo "[ERROR] Please run:"
  echo "        conda activate host-tools"
  exit 1
}

command -v samtools >/dev/null 2>&1 || {
  echo "[ERROR] samtools command not found"
  echo "[ERROR] Please install samtools in the host-tools environment."
  exit 1
}

command -v seqkit >/dev/null 2>&1 || {
  echo "[ERROR] seqkit command not found"
  exit 1
}

if ! compgen -G "${HOST_INDEX}*.bt2*" >/dev/null; then
  echo "[ERROR] Bowtie2 human reference index not found:"
  echo "        ${HOST_INDEX}*.bt2*"
  exit 1
fi

# ==============================================================================
# Run strict dehost
# ==============================================================================

for sample in "${SAMPLES[@]}"; do
  echo
  echo "============================================================"
  echo "[INFO] Strict human dehost: ${sample}"
  echo "============================================================"

  r1="${FASTP_DIR}/${sample}_R1.clean.fq.gz"
  r2="${FASTP_DIR}/${sample}_R2.clean.fq.gz"

  out_r1="${CLEAN_DIR}/${sample}_R1.dehost.fq.gz"
  out_r2="${CLEAN_DIR}/${sample}_R2.dehost.fq.gz"

  tmp_bam="${TMP_DIR}/${sample}.both_mates_unmapped.name_sorted.bam"
  bowtie2_log="${LOG_DIR}/${sample}.bowtie2.log"
  samtools_log="${LOG_DIR}/${sample}.samtools_fastq.log"

  for input_file in "${r1}" "${r2}"; do
    if [ ! -s "${input_file}" ]; then
      echo "[ERROR] Missing or empty input file:"
      echo "        ${input_file}"
      exit 1
    fi
  done

  if [ -s "${out_r1}" ] && [ -s "${out_r2}" ]; then
    echo "[INFO] Strict dehost outputs already exist. Skip: ${sample}"
    continue
  fi

  # --------------------------------------------------------------------------
  # Bowtie2 alignment
  #
  # samtools view -f 12:
  #   retain paired records where both read and mate are unmapped.
  #
  # samtools sort -n:
  #   name-sort records before conversion back to paired FASTQ.
  # --------------------------------------------------------------------------
  bowtie2 \
    -x "${HOST_INDEX}" \
    -1 "${r1}" \
    -2 "${r2}" \
    --very-sensitive \
    --threads "${THREADS}" \
    2> "${bowtie2_log}" \
  | samtools view \
      -@ "${THREADS}" \
      -b \
      -f 12 \
      -F 2304 \
      - \
  | samtools sort \
      -@ "${THREADS}" \
      -n \
      -o "${tmp_bam}" \
      -

  # --------------------------------------------------------------------------
  # Convert strictly non-host read pairs back to FASTQ.
  #
  # -1 / -2:
  #   write mate 1 and mate 2 separately.
  #
  # -0 / -s:
  #   discard unexpected unpaired records.
  # --------------------------------------------------------------------------
  samtools fastq \
    -@ "${THREADS}" \
    -n \
    -1 "${out_r1}" \
    -2 "${out_r2}" \
    -0 /dev/null \
    -s /dev/null \
    "${tmp_bam}" \
    2> "${samtools_log}"

  rm -f -- "${tmp_bam}"

  if [ ! -s "${out_r1}" ] || [ ! -s "${out_r2}" ]; then
    echo "[ERROR] Strict dehost FASTQ output missing or empty:"
    echo "        ${out_r1}"
    echo "        ${out_r2}"
    exit 1
  fi

  echo "[INFO] Done: ${sample}"
done

# ==============================================================================
# Cohort-level seqkit summary
# ==============================================================================

seqkit stats \
  "${CLEAN_DIR}"/*.dehost.fq.gz \
  > "${OUT_DIR}/seqkit_dehost_stats.tsv"

echo
echo "============================================================"
echo "[INFO] Strict dehost completed"
echo "============================================================"

echo "[INFO] Seqkit summary:"
cat "${OUT_DIR}/seqkit_dehost_stats.tsv"

echo
echo "[INFO] Human-host alignment rates:"
grep "overall alignment rate" "${LOG_DIR}"/*.bowtie2.log || true
EOF

chmod +x scripts/run_02_dehost_human.sh
```

#### 03. MetaPhlAn
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/run_03_metaphlan.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# MetaPhlAn taxonomy profiling
#
# Required conda environment:
#   conda activate metagenomics-taxonomy
#
# Output:
#   profiles/<sample>_profile.txt
#       Standard relative-abundance profile for downstream taxonomy analysis.
#
#   read_stats/<sample>_read_stats.txt
#       Marker-based coverage and estimated reads for QC.
#
#   bowtie2out/<sample>.bowtie2.bz2
#       Intermediate marker mapping output reused for read statistics.
# ==============================================================================

METAPHLAN_DB="/home/adprc/databases/metagenomics/metaphlan"
THREADS=12

DEHOST_DIR="results/02_dehost/clean_reads"
OUT_DIR="results/03_metaphlan"

SAMPLES=(
  "YZA"
  "YZB"
)

mkdir -p "${OUT_DIR}/profiles"
mkdir -p "${OUT_DIR}/read_stats"
mkdir -p "${OUT_DIR}/bowtie2out"
mkdir -p "${OUT_DIR}/logs"

command -v metaphlan >/dev/null 2>&1 || {
  echo "[ERROR] metaphlan command not found"
  echo "[ERROR] Please run:"
  echo "        conda activate metagenomics-taxonomy"
  exit 1
}

echo "[INFO] MetaPhlAn version:"
metaphlan --version

for sample in "${SAMPLES[@]}"; do
  echo
  echo "============================================================"
  echo "[INFO] Sample: ${sample}"
  echo "============================================================"

  r1="${DEHOST_DIR}/${sample}_R1.dehost.fq.gz"
  r2="${DEHOST_DIR}/${sample}_R2.dehost.fq.gz"

  mapout="${OUT_DIR}/bowtie2out/${sample}.bowtie2.bz2"

  profile="${OUT_DIR}/profiles/${sample}_profile.txt"
  read_stats="${OUT_DIR}/read_stats/${sample}_read_stats.txt"

  profile_log="${OUT_DIR}/logs/${sample}.metaphlan.profile.log"
  read_stats_log="${OUT_DIR}/logs/${sample}.metaphlan.read_stats.log"

  for input_file in "${r1}" "${r2}"; do
    if [ ! -s "${input_file}" ]; then
      echo "[ERROR] Missing or empty input file:"
      echo "        ${input_file}"
      exit 1
    fi
  done

  # --------------------------------------------------------------------------
  # Step 1: Standard relative-abundance profile
  # --------------------------------------------------------------------------
  if [ ! -s "${profile}" ] || [ ! -s "${mapout}" ]; then
    echo "[INFO] Running standard MetaPhlAn profile"

    metaphlan \
      "${r1},${r2}" \
      --input_type fastq \
      --db_dir "${METAPHLAN_DB}" \
      --nproc "${THREADS}" \
      --mapout "${mapout}" \
      -o "${profile}" \
      2>&1 | tee "${profile_log}"
  else
    echo "[INFO] Existing MetaPhlAn profile and mapout found. Skip mapping:"
    echo "       ${profile}"
    echo "       ${mapout}"
  fi

  # --------------------------------------------------------------------------
  # Step 2: Marker-based coverage and estimated reads
  #
  # These statistics are QC outputs.
  # Do not treat them as direct replacements for Bracken estimated reads.
  # --------------------------------------------------------------------------
  if [ ! -s "${read_stats}" ]; then
    echo "[INFO] Generating MetaPhlAn read statistics"

    metaphlan \
      "${mapout}" \
      --input_type mapout \
      --db_dir "${METAPHLAN_DB}" \
      --nproc "${THREADS}" \
      -t rel_ab_w_read_stats \
      -o "${read_stats}" \
      2>&1 | tee "${read_stats_log}"
  else
    echo "[INFO] Existing MetaPhlAn read statistics found. Skip:"
    echo "       ${read_stats}"
  fi

  echo "[INFO] Done: ${sample}"
done

echo
echo "============================================================"
echo "[INFO] MetaPhlAn profiling completed"
echo "============================================================"

echo "[INFO] Standard profiles:"
find "${OUT_DIR}/profiles" \
  -type f \
  -name "*_profile.txt" \
  -print | sort

echo
echo "[INFO] Marker-based read statistics:"
find "${OUT_DIR}/read_stats" \
  -type f \
  -name "*_read_stats.txt" \
  -print | sort
EOF

chmod +x scripts/run_03_metaphlan.sh
```

#### 03b. MetaPhlAn humann compatible
```bash
#!/usr/bin/env bash
set -euo pipefail

METAPHLAN_DB="/home/adprc/databases/metagenomics/metaphlan_vJun23"
METAPHLAN_INDEX="mpa_vJun23_CHOCOPhlAnSGB_202403"
THREADS=12

DEHOST_DIR="results/02_dehost/clean_reads"
OUT_DIR="results/03b_metaphlan_humann_compatible"

mkdir -p "${OUT_DIR}/profiles"
mkdir -p "${OUT_DIR}/bowtie2out"
mkdir -p "${OUT_DIR}/logs"

for sample in YZA YZB; do
  echo "[INFO] Running HUMAnN-compatible MetaPhlAn for ${sample}"

  metaphlan \
    "${DEHOST_DIR}/${sample}_R1.dehost.fq.gz,${DEHOST_DIR}/${sample}_R2.dehost.fq.gz" \
    --input_type fastq \
    --bowtie2db "${METAPHLAN_DB}" \
    --index "${METAPHLAN_INDEX}" \
    --nproc "${THREADS}" \
    --bowtie2out "${OUT_DIR}/bowtie2out/${sample}.bowtie2.bz2" \
    -o "${OUT_DIR}/profiles/${sample}_profile.txt" \
    2>&1 | tee "${OUT_DIR}/logs/${sample}.metaphlan.log"

  echo "[INFO] Done: ${sample}"
done
EOF

chmod +x scripts/run_03b_metaphlan_humann_compatible.sh
```

#### 04. Kraken2
```bash
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Kraken2 taxonomy classification
#
# Required conda environment:
#   conda activate metagenomics-taxonomy
#
# Database:
#   Kraken2 PlusPF 20260226
#   Includes Standard DB + RefSeq fungi + RefSeq protozoa.
#   Used to better match BGI/Dr.Tom-style taxonomy coverage:
#   Bacteria, Archaea, Viruses, Eukaryota-related microbial taxa, and unclassified reads.
#
# Input:
#   results/02_dehost/clean_reads/<sample>_R1.dehost.fq.gz
#   results/02_dehost/clean_reads/<sample>_R2.dehost.fq.gz
#
# Output:
#   reports/<sample>.kraken2.report.tsv
#       Sample-level taxonomy report containing the full taxonomy tree.
#
#   outputs/<sample>.kraken2.read_classification.tsv
#       Read-level classification output. Retained for traceability.
# ==============================================================================

KRAKEN2_DB="/home/adprc/databases/metagenomics/kraken2/pluspf_20260226"
THREADS=12

DEHOST_DIR="results/02_dehost/clean_reads"
OUT_DIR="results/04_kraken2"

SAMPLES=(
  "YZA"
  "YZB"
)

mkdir -p "${OUT_DIR}/reports"
mkdir -p "${OUT_DIR}/outputs"
mkdir -p "${OUT_DIR}/logs"

command -v kraken2 >/dev/null 2>&1 || {
  echo "[ERROR] kraken2 command not found"
  echo "[ERROR] Please run: conda activate metagenomics-taxonomy"
  exit 1
}

if [ ! -d "${KRAKEN2_DB}" ]; then
  echo "[ERROR] Kraken2 database not found:"
  echo "        ${KRAKEN2_DB}"
  exit 1
fi

for sample in "${SAMPLES[@]}"; do
  echo
  echo "============================================================"
  echo "[INFO] Running Kraken2: ${sample}"
  echo "============================================================"

  r1="${DEHOST_DIR}/${sample}_R1.dehost.fq.gz"
  r2="${DEHOST_DIR}/${sample}_R2.dehost.fq.gz"

  report="${OUT_DIR}/reports/${sample}.kraken2.report.tsv"
  output="${OUT_DIR}/outputs/${sample}.kraken2.read_classification.tsv"
  log="${OUT_DIR}/logs/${sample}.kraken2.log"

  for input_file in "${r1}" "${r2}"; do
    if [ ! -s "${input_file}" ]; then
      echo "[ERROR] Missing or empty input file:"
      echo "        ${input_file}"
      exit 1
    fi
  done

  if [ -s "${report}" ] && [ -s "${output}" ]; then
    echo "[INFO] Kraken2 outputs already exist. Skip: ${sample}"
    continue
  fi

  kraken2 \
    --db "${KRAKEN2_DB}" \
    --threads "${THREADS}" \
    --paired \
    --report "${report}" \
    --output "${output}" \
    "${r1}" \
    "${r2}" \
    2>&1 | tee "${log}"

  if [ ! -s "${report}" ]; then
    echo "[ERROR] Kraken2 report missing or empty:"
    echo "        ${report}"
    exit 1
  fi

  echo "[INFO] Done: ${sample}"
done

echo
echo "[INFO] Kraken2 reports:"
find "${OUT_DIR}/reports" -type f -name "*.kraken2.report.tsv" -print | sort
EOF

chmod +x scripts/run_04_kraken2.sh
```

#### 05. Bracken
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/run_05_bracken_all_ranks.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Bracken abundance re-estimation for standard taxonomy ranks
#
# Required conda environment:
#   conda activate metagenomics-taxonomy
#
# Database:
#   Same Kraken2 PlusPF 20260226 database as Step 04.
#   Bracken uses database150mers.kmer_distrib for read-length-specific abundance re-estimation.
#
# Input:
#   results/04_kraken2/reports/<sample>.kraken2.report.tsv
#
# Output:
#   results/05_bracken/<rank>/<sample>.bracken.<code>.tsv
#   results/05_bracken/<rank>/<sample>.bracken.<code>.report
#
# Notes:
#   Bracken performs abundance re-estimation one taxonomy rank at a time.
# ==============================================================================

KRAKEN2_DB="/home/adprc/databases/metagenomics/kraken2/pluspf_20260226"
READ_LEN=150

KRAKEN2_REPORT_DIR="results/04_kraken2/reports"
OUT_BASE_DIR="results/05_bracken"
LOG_DIR="${OUT_BASE_DIR}/logs"

SAMPLES=(
  "YZA"
  "YZB"
)

RANK_NAMES=(
  "phylum"
  "class"
  "order"
  "family"
  "genus"
  "species"
)

RANK_CODES=(
  "P"
  "C"
  "O"
  "F"
  "G"
  "S"
)

mkdir -p "${LOG_DIR}"

command -v bracken >/dev/null 2>&1 || {
  echo "[ERROR] bracken command not found"
  echo "[ERROR] Please run:"
  echo "        conda activate metagenomics-taxonomy"
  exit 1
}

if [ ! -d "${KRAKEN2_DB}" ]; then
  echo "[ERROR] Kraken2 / Bracken database not found:"
  echo "        ${KRAKEN2_DB}"
  exit 1
fi

if [ ! -f "${KRAKEN2_DB}/database${READ_LEN}mers.kmer_distrib" ]; then
  echo "[ERROR] Bracken ${READ_LEN}-mer database file not found:"
  echo "        ${KRAKEN2_DB}/database${READ_LEN}mers.kmer_distrib"
  exit 1
fi

for sample in "${SAMPLES[@]}"; do
  echo
  echo "============================================================"
  echo "[INFO] Sample: ${sample}"
  echo "============================================================"

  input_report="${KRAKEN2_REPORT_DIR}/${sample}.kraken2.report.tsv"

  if [ ! -s "${input_report}" ]; then
    echo "[ERROR] Kraken2 report missing or empty:"
    echo "        ${input_report}"
    exit 1
  fi

  for i in "${!RANK_CODES[@]}"; do
    rank_name="${RANK_NAMES[$i]}"
    rank_code="${RANK_CODES[$i]}"

    out_dir="${OUT_BASE_DIR}/${rank_name}"

    output_table="${out_dir}/${sample}.bracken.${rank_code}.tsv"
    output_report="${out_dir}/${sample}.bracken.${rank_code}.report"
    log="${LOG_DIR}/${sample}.bracken.${rank_code}.log"

    mkdir -p "${out_dir}"

    if [ -s "${output_table}" ] && [ -s "${output_report}" ]; then
      echo "[INFO] Bracken outputs already exist. Skip:"
      echo "       sample=${sample}, rank=${rank_name}"
      continue
    fi

    echo "[INFO] Running Bracken:"
    echo "       sample=${sample}"
    echo "       rank=${rank_name}"
    echo "       code=${rank_code}"

    bracken \
      -d "${KRAKEN2_DB}" \
      -i "${input_report}" \
      -o "${output_table}" \
      -w "${output_report}" \
      -r "${READ_LEN}" \
      -l "${rank_code}" \
      2>&1 | tee "${log}"

    if [ ! -s "${output_table}" ]; then
      echo "[ERROR] Bracken table missing or empty:"
      echo "        ${output_table}"
      exit 1
    fi

    if [ ! -s "${output_report}" ]; then
      echo "[ERROR] Bracken report missing or empty:"
      echo "        ${output_report}"
      exit 1
    fi

    echo "[INFO] Done:"
    echo "       sample=${sample}, rank=${rank_name}"
  done
done

echo
echo "============================================================"
echo "[INFO] Bracken abundance re-estimation completed"
echo "============================================================"

find "${OUT_BASE_DIR}" \
  -mindepth 2 \
  -maxdepth 2 \
  -type f \
  -name "*.tsv" \
  -print | sort
EOF

chmod +x scripts/run_05_bracken_all_ranks.sh
```

#### 06. merge tables for samples
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/run_06_merge_taxonomy_tables.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Merge cohort-level taxonomy tables
#
# Required conda environment:
#   conda activate metagenomics-taxonomy
#
# Standard matrix orientation:
#   rows    = taxa
#   columns = samples
#
# Output folders:
#   results/06_taxonomy_tables/metaphlan/
#   results/06_taxonomy_tables/kraken2/
#   results/06_taxonomy_tables/bracken/
# ==============================================================================

OUT_DIR="results/06_taxonomy_tables"

METAPHLAN_PROFILE_DIR="results/03_metaphlan/profiles"
METAPHLAN_READ_STATS_DIR="results/03_metaphlan/read_stats"

KRAKEN2_REPORT_DIR="results/04_kraken2/reports"
BRACKEN_DIR="results/05_bracken"

METAPHLAN_OUT_DIR="${OUT_DIR}/metaphlan"
KRAKEN2_OUT_DIR="${OUT_DIR}/kraken2"
BRACKEN_OUT_DIR="${OUT_DIR}/bracken"

mkdir -p "${METAPHLAN_OUT_DIR}"
mkdir -p "${KRAKEN2_OUT_DIR}"
mkdir -p "${BRACKEN_OUT_DIR}"

# ==============================================================================
# Preflight checks
# ==============================================================================

echo "============================================================"
echo "[INFO] Merge taxonomy tables"
echo "============================================================"

command -v merge_metaphlan_tables.py >/dev/null 2>&1 || {
  echo "[ERROR] merge_metaphlan_tables.py not found"
  echo "[ERROR] Please run:"
  echo "        conda activate metagenomics-taxonomy"
  exit 1
}

command -v python >/dev/null 2>&1 || {
  echo "[ERROR] python command not found"
  exit 1
}

python - <<'PY'
try:
    import pandas  # noqa: F401
except ImportError as exc:
    raise SystemExit(
        "[ERROR] Python package not found: pandas\n"
        "[ERROR] Please install pandas in metagenomics-taxonomy environment."
    ) from exc
PY

ls "${METAPHLAN_PROFILE_DIR}"/*_profile.txt >/dev/null 2>&1 || {
  echo "[ERROR] MetaPhlAn profiles not found:"
  echo "        ${METAPHLAN_PROFILE_DIR}/*_profile.txt"
  exit 1
}

ls "${METAPHLAN_READ_STATS_DIR}"/*_read_stats.txt >/dev/null 2>&1 || {
  echo "[ERROR] MetaPhlAn read-statistics files not found:"
  echo "        ${METAPHLAN_READ_STATS_DIR}/*_read_stats.txt"
  echo "[ERROR] Please rerun: bash scripts/run_03_metaphlan.sh"
  exit 1
}

ls "${KRAKEN2_REPORT_DIR}"/*.kraken2.report.tsv >/dev/null 2>&1 || {
  echo "[ERROR] Kraken2 reports not found:"
  echo "        ${KRAKEN2_REPORT_DIR}/*.kraken2.report.tsv"
  exit 1
}

for rank_name in phylum class order family genus species; do
  ls "${BRACKEN_DIR}/${rank_name}"/*.tsv >/dev/null 2>&1 || {
    echo "[ERROR] Bracken ${rank_name} tables not found:"
    echo "        ${BRACKEN_DIR}/${rank_name}/*.tsv"
    exit 1
  }
done

# ==============================================================================
# Remove obsolete root-level TSV files and refresh generated subfolders
# ==============================================================================

echo "[INFO] Removing obsolete taxonomy tables"

find "${OUT_DIR}" \
  -maxdepth 1 \
  -type f \
  -name "*.tsv" \
  -delete

rm -rf "${METAPHLAN_OUT_DIR}"
rm -rf "${KRAKEN2_OUT_DIR}"
rm -rf "${BRACKEN_OUT_DIR}"

mkdir -p "${METAPHLAN_OUT_DIR}"
mkdir -p "${KRAKEN2_OUT_DIR}"
mkdir -p "${BRACKEN_OUT_DIR}"

# ==============================================================================
# Merge MetaPhlAn standard profiles
# ==============================================================================

echo "[INFO] Merging MetaPhlAn profiles"

merge_metaphlan_tables.py \
  "${METAPHLAN_PROFILE_DIR}"/*_profile.txt \
  > "${METAPHLAN_OUT_DIR}/metaphlan_all_levels_relative_abundance.tsv"

# ==============================================================================
# Build standardized cohort-level tables
# ==============================================================================

echo "[INFO] Building cohort-level taxonomy tables"

python - <<'PY'
from __future__ import annotations

from pathlib import Path
import re

import pandas as pd


# =============================================================================
# Configuration
# =============================================================================

OUT_DIR = Path("results/06_taxonomy_tables")

METAPHLAN_OUT_DIR = OUT_DIR / "metaphlan"
KRAKEN2_OUT_DIR = OUT_DIR / "kraken2"
BRACKEN_OUT_DIR = OUT_DIR / "bracken"

METAPHLAN_ALL_LEVELS = (
    METAPHLAN_OUT_DIR
    / "metaphlan_all_levels_relative_abundance.tsv"
)

METAPHLAN_READ_STATS_DIR = Path(
    "results/03_metaphlan/read_stats"
)

KRAKEN2_REPORT_DIR = Path(
    "results/04_kraken2/reports"
)

BRACKEN_DIR = Path(
    "results/05_bracken"
)

STANDARD_RANKS = [
    ("phylum", "P", "p__"),
    ("class", "C", "c__"),
    ("order", "O", "o__"),
    ("family", "F", "f__"),
    ("genus", "G", "g__"),
    ("species", "S", "s__"),
]


# =============================================================================
# Generic helpers
# =============================================================================

def save_table(
    a_df: pd.DataFrame,
    output_path: Path,
) -> None:
    """
    Save a cohort-level table using the standard orientation:
        rows    = features
        columns = samples
    """
    a_df.to_csv(
        output_path,
        sep="\t",
        index=True,
    )

    print(
        f"[INFO] Written: {output_path} "
        f"(features={a_df.shape[0]}, "
        f"samples={a_df.shape[1]})"
    )


def read_comment_header_table(path: Path) -> pd.DataFrame:
    """
    Read MetaPhlAn output whose column-name row starts with '#'.

    The function searches for the final commented header beginning with
    '#clade_name', then loads non-comment rows using that header.
    """
    header: list[str] | None = None

    with path.open("rt", encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#clade_name"):
                header = line.lstrip("#").rstrip("\n").split("\t")

    if header is None:
        raise ValueError(
            f"MetaPhlAn header '#clade_name' not found: {path}"
        )

    return pd.read_csv(
        path,
        sep="\t",
        comment="#",
        header=None,
        names=header,
    )


# =============================================================================
# MetaPhlAn
# =============================================================================

def load_metaphlan_relative_abundance(path: Path) -> pd.DataFrame:
    """Load official merged MetaPhlAn relative-abundance table."""
    a_df = pd.read_csv(
        path,
        sep="\t",
        comment="#",
        index_col=0,
    )

    a_df.index = a_df.index.astype(str)
    a_df.index.name = "clade_name"

    return (
        a_df
        .apply(pd.to_numeric, errors="coerce")
        .fillna(0.0)
    )


def extract_metaphlan_rank(
    a_df: pd.DataFrame,
    rank_prefix: str,
) -> pd.DataFrame:
    """Keep rows terminating at one requested MetaPhlAn rank."""
    rank_pattern = re.compile(
        rf"(?:^|\|){re.escape(rank_prefix)}[^|]+$"
    )

    selected_index = [
        taxon
        for taxon in a_df.index
        if rank_pattern.search(taxon)
    ]

    return a_df.loc[selected_index].copy()


def merge_metaphlan_read_stats(
    value_col: str,
) -> pd.DataFrame:
    """
    Merge one MetaPhlAn read-statistics column across samples.

    Expected useful columns:
        coverage
        estimated_number_of_reads_from_the_clade
    """
    sample_series_list: list[pd.Series] = []

    for path in sorted(
        METAPHLAN_READ_STATS_DIR.glob("*_read_stats.txt")
    ):
        sample_id = path.name.removesuffix("_read_stats.txt")

        a_df = read_comment_header_table(path)

        if "clade_name" not in a_df.columns:
            raise ValueError(
                f"{path} does not contain 'clade_name'"
            )

        if value_col not in a_df.columns:
            raise ValueError(
                f"{path} does not contain '{value_col}'. "
                f"Available columns: {list(a_df.columns)}"
            )

        sample_series = pd.Series(
            data=pd.to_numeric(
                a_df[value_col],
                errors="coerce",
            ).fillna(0.0).values,
            index=a_df["clade_name"].astype(str),
            name=sample_id,
        )

        sample_series = sample_series.groupby(
            level=0
        ).sum()

        sample_series_list.append(sample_series)

    if not sample_series_list:
        raise FileNotFoundError(
            "No MetaPhlAn read-statistics files found"
        )

    merged_df = pd.concat(
        sample_series_list,
        axis=1,
    ).fillna(0.0)

    merged_df.index.name = "clade_name"

    return merged_df


# =============================================================================
# Kraken2
# =============================================================================

KRAKEN2_COLUMNS = [
    "percentage",
    "clade_reads",
    "direct_reads",
    "rank_code",
    "taxonomy_id",
    "name",
]


def load_kraken2_report(path: Path) -> pd.DataFrame:
    """
    Load a six-column Kraken2 observed taxonomy-tree report.

    Intermediate rank codes such as G1 or S1 are retained in observed-tree
    outputs but excluded from standard-rank tables.
    """
    a_df = pd.read_csv(
        path,
        sep="\t",
        header=None,
        names=KRAKEN2_COLUMNS,
        dtype={
            "rank_code": str,
            "taxonomy_id": str,
            "name": str,
        },
    )

    a_df["name"] = (
        a_df["name"]
        .fillna("")
        .astype(str)
        .str.strip()
    )

    for col in [
        "percentage",
        "clade_reads",
        "direct_reads",
    ]:
        a_df[col] = pd.to_numeric(
            a_df[col],
            errors="coerce",
        ).fillna(0.0)

    a_df["taxon"] = (
        "rank__"
        + a_df["rank_code"].astype(str)
        + "|taxid__"
        + a_df["taxonomy_id"].astype(str)
        + "|name__"
        + a_df["name"].astype(str)
    )

    return a_df


def merge_kraken2_reports(
    value_col: str,
    rank_code: str | None = None,
) -> pd.DataFrame:
    """Merge Kraken2 reports into a taxa × samples matrix."""
    sample_series_list: list[pd.Series] = []

    for path in sorted(
        KRAKEN2_REPORT_DIR.glob("*.kraken2.report.tsv")
    ):
        sample_id = path.name.removesuffix(
            ".kraken2.report.tsv"
        )

        a_df = load_kraken2_report(path)

        if rank_code is not None:
            a_df = a_df.loc[
                a_df["rank_code"].astype(str) == rank_code
            ].copy()

        sample_series = pd.Series(
            data=a_df[value_col].values,
            index=a_df["taxon"],
            name=sample_id,
        )

        sample_series = sample_series.groupby(
            level=0
        ).sum()

        sample_series_list.append(sample_series)

    if not sample_series_list:
        raise FileNotFoundError(
            f"No Kraken2 reports found in: "
            f"{KRAKEN2_REPORT_DIR}"
        )

    merged_df = pd.concat(
        sample_series_list,
        axis=1,
    ).fillna(0.0)

    merged_df.index.name = "taxon"

    return merged_df


# =============================================================================
# Bracken
# =============================================================================

def merge_bracken_rank(
    rank_name: str,
    rank_code: str,
    value_col: str,
) -> pd.DataFrame:
    """Merge Bracken tables for one standard taxonomy rank."""
    input_dir = BRACKEN_DIR / rank_name

    pattern = f"*.bracken.{rank_code}.tsv"
    suffix = f".bracken.{rank_code}.tsv"

    sample_series_list: list[pd.Series] = []

    for path in sorted(input_dir.glob(pattern)):
        sample_id = path.name.removesuffix(suffix)

        a_df = pd.read_csv(
            path,
            sep="\t",
        )

        required_cols = {
            "name",
            "taxonomy_id",
            "taxonomy_lvl",
            value_col,
        }

        missing_cols = required_cols.difference(
            a_df.columns
        )

        if missing_cols:
            raise ValueError(
                f"{path} is missing required columns: "
                f"{sorted(missing_cols)}"
            )

        taxon = (
            "rank__"
            + a_df["taxonomy_lvl"].astype(str)
            + "|taxid__"
            + a_df["taxonomy_id"].astype(str)
            + "|name__"
            + a_df["name"].astype(str)
        )

        sample_series = pd.Series(
            data=pd.to_numeric(
                a_df[value_col],
                errors="coerce",
            ).fillna(0.0).values,
            index=taxon,
            name=sample_id,
        )

        sample_series = sample_series.groupby(
            level=0
        ).sum()

        sample_series_list.append(sample_series)

    if not sample_series_list:
        raise FileNotFoundError(
            f"No Bracken tables matched: "
            f"{input_dir / pattern}"
        )

    merged_df = pd.concat(
        sample_series_list,
        axis=1,
    ).fillna(0.0)

    merged_df.index.name = "taxon"

    return merged_df


# =============================================================================
# MetaPhlAn outputs
# =============================================================================

print()
print("[INFO] Processing MetaPhlAn tables")

metaphlan_all_df = load_metaphlan_relative_abundance(
    METAPHLAN_ALL_LEVELS
)

for rank_name, _, rank_prefix in STANDARD_RANKS:
    rank_df = extract_metaphlan_rank(
        metaphlan_all_df,
        rank_prefix=rank_prefix,
    )

    save_table(
        rank_df,
        METAPHLAN_OUT_DIR
        / f"metaphlan_{rank_name}_relative_abundance.tsv",
    )

metaphlan_coverage_df = merge_metaphlan_read_stats(
    value_col="coverage",
)

save_table(
    metaphlan_coverage_df,
    METAPHLAN_OUT_DIR / "metaphlan_marker_coverage.tsv",
)

metaphlan_estimated_reads_df = merge_metaphlan_read_stats(
    value_col="estimated_number_of_reads_from_the_clade",
)

save_table(
    metaphlan_estimated_reads_df,
    METAPHLAN_OUT_DIR / "metaphlan_estimated_reads.tsv",
)


# =============================================================================
# Kraken2 outputs
# =============================================================================

print()
print("[INFO] Processing Kraken2 tables")

kraken2_observed_tree_relative_df = merge_kraken2_reports(
    value_col="percentage",
)

save_table(
    kraken2_observed_tree_relative_df,
    KRAKEN2_OUT_DIR
    / "kraken2_observed_tree_relative_abundance.tsv",
)

kraken2_observed_tree_reads_df = merge_kraken2_reports(
    value_col="clade_reads",
)

save_table(
    kraken2_observed_tree_reads_df,
    KRAKEN2_OUT_DIR
    / "kraken2_observed_tree_clade_reads.tsv",
)

for rank_name, rank_code, _ in STANDARD_RANKS:
    rank_df = merge_kraken2_reports(
        value_col="percentage",
        rank_code=rank_code,
    )

    save_table(
        rank_df,
        KRAKEN2_OUT_DIR
        / f"kraken2_{rank_name}_relative_abundance.tsv",
    )


# =============================================================================
# Bracken outputs
# =============================================================================

print()
print("[INFO] Processing Bracken tables")

for rank_name, rank_code, _ in STANDARD_RANKS:
    relative_df = merge_bracken_rank(
        rank_name=rank_name,
        rank_code=rank_code,
        value_col="fraction_total_reads",
    )

    save_table(
        relative_df,
        BRACKEN_OUT_DIR
        / f"bracken_{rank_name}_relative_abundance.tsv",
    )

    estimated_reads_df = merge_bracken_rank(
        rank_name=rank_name,
        rank_code=rank_code,
        value_col="new_est_reads",
    )

    save_table(
        estimated_reads_df,
        BRACKEN_OUT_DIR
        / f"bracken_{rank_name}_estimated_reads.tsv",
    )


# =============================================================================
# Summary
# =============================================================================

print()
print("============================================================")
print("[INFO] Taxonomy-table merge completed")
print("============================================================")

print(f"[INFO] Output directory: {OUT_DIR}")
print(f"[INFO] MetaPhlAn rows: {metaphlan_all_df.shape[0]}")
print(
    "[INFO] Kraken2 observed-tree nodes: "
    f"{kraken2_observed_tree_relative_df.shape[0]}"
)
PY

echo
echo "============================================================"
echo "[INFO] Output files"
echo "============================================================"

find "${OUT_DIR}" \
  -type f \
  -name "*.tsv" \
  -printf "%p\n" \
  | sort
EOF

chmod +x scripts/run_06_merge_taxonomy_tables.sh
```

#### 07. HUMAnN
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/run_07_humann.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# HUMAnN functional profiling pipeline
#
# Required conda environment:
#   conda activate metagenomics-humann
#
# Input:
#   results/02_dehost/clean_reads/<sample>_R1.dehost.fq.gz
#   results/02_dehost/clean_reads/<sample>_R2.dehost.fq.gz
#
# HUMAnN-compatible MetaPhlAn profiles:
#   results/03b_metaphlan_humann_compatible/profiles/<sample>_profile.txt
#
# Main output folder:
#   results/07_humann/<sample>/
#
# Main outputs:
#   <sample>_genefamilies.tsv
#   <sample>_pathabundance.tsv
#   <sample>_pathcoverage.tsv
#
# Temporary-file policy:
#   - If HUMAnN is interrupted:
#       Preserve temporary files for --resume.
#   - If HUMAnN completes successfully:
#       Remove HUMAnN intermediate files automatically.
#       Remove the temporary combined FASTQ after output validation.
# ==============================================================================

THREADS=12

# ------------------------------------------------------------------------------
# Shared HUMAnN databases
# ------------------------------------------------------------------------------
NUCLEOTIDE_DB="/home/adprc/databases/metagenomics/humann/chocophlan/chocophlan"
PROTEIN_DB="/home/adprc/databases/metagenomics/humann/uniref/uniref"

# ------------------------------------------------------------------------------
# Project folders
# ------------------------------------------------------------------------------
DEHOST_DIR="results/02_dehost/clean_reads"
METAPHLAN_DIR="results/03b_metaphlan_humann_compatible/profiles"

OUT_DIR="results/07_humann"
TMP_DIR="tmp/humann_input"
LOG_DIR="${OUT_DIR}/logs"

# ------------------------------------------------------------------------------
# Samples
# ------------------------------------------------------------------------------
SAMPLES=(
  "YZA"
  "YZB"
)

mkdir -p "${OUT_DIR}"
mkdir -p "${TMP_DIR}"
mkdir -p "${LOG_DIR}"

# ==============================================================================
# Helper functions
# ==============================================================================

verify_outputs() {
  local genefamilies="$1"
  local pathabundance="$2"
  local pathcoverage="$3"

  [ -s "${genefamilies}" ] && \
  [ -s "${pathabundance}" ] && \
  [ -s "${pathcoverage}" ]
}

cleanup_completed_sample() {
  local sample="$1"
  local sample_out_dir="$2"
  local combined_fastq="$3"

  local humann_temp_dir="${sample_out_dir}/${sample}_humann_temp"

  # HUMAnN should normally remove this folder automatically when
  # --remove-temp-output is enabled. This additional step safely removes
  # stale temp folders produced by older runs.
  if [ -d "${humann_temp_dir}" ]; then
    echo "[INFO] Removing stale HUMAnN temp folder:"
    echo "       ${humann_temp_dir}"

    rm -rf -- "${humann_temp_dir}"
  fi

  # This file is created by this script rather than by HUMAnN.
  if [ -f "${combined_fastq}" ]; then
    echo "[INFO] Removing temporary combined FASTQ:"
    echo "       ${combined_fastq}"

    rm -f -- "${combined_fastq}"
  fi
}

# ==============================================================================
# Preflight checks
# ==============================================================================

echo "============================================================"
echo "[INFO] HUMAnN functional profiling pipeline"
echo "============================================================"

echo "[INFO] Checking required commands"

command -v humann >/dev/null 2>&1 || {
  echo "[ERROR] humann command not found"
  echo "[ERROR] Please run:"
  echo "        conda activate metagenomics-humann"
  exit 1
}

command -v metaphlan >/dev/null 2>&1 || {
  echo "[ERROR] metaphlan command not found"
  echo "[ERROR] Please run:"
  echo "        conda activate metagenomics-humann"
  exit 1
}

command -v bowtie2 >/dev/null 2>&1 || {
  echo "[ERROR] bowtie2 command not found"
  exit 1
}

command -v diamond >/dev/null 2>&1 || {
  echo "[ERROR] diamond command not found"
  exit 1
}

echo
echo "[INFO] HUMAnN version:"
humann --version

echo
echo "[INFO] MetaPhlAn command:"
command -v metaphlan

echo
echo "[INFO] MetaPhlAn version:"
metaphlan --version

echo
echo "[INFO] Bowtie2 command:"
command -v bowtie2

echo
echo "[INFO] DIAMOND command:"
command -v diamond

echo
echo "[INFO] Checking HUMAnN databases"

if [ ! -d "${NUCLEOTIDE_DB}" ]; then
  echo "[ERROR] HUMAnN nucleotide database not found:"
  echo "        ${NUCLEOTIDE_DB}"
  exit 1
fi

if [ ! -d "${PROTEIN_DB}" ]; then
  echo "[ERROR] HUMAnN protein database not found:"
  echo "        ${PROTEIN_DB}"
  exit 1
fi

echo "[INFO] HUMAnN databases found"

# ==============================================================================
# Run HUMAnN
# ==============================================================================

for sample in "${SAMPLES[@]}"; do
  echo
  echo "============================================================"
  echo "[INFO] Sample: ${sample}"
  echo "============================================================"

  # --------------------------------------------------------------------------
  # Input files
  # --------------------------------------------------------------------------
  r1="${DEHOST_DIR}/${sample}_R1.dehost.fq.gz"
  r2="${DEHOST_DIR}/${sample}_R2.dehost.fq.gz"

  taxonomic_profile="${METAPHLAN_DIR}/${sample}_profile.txt"

  # --------------------------------------------------------------------------
  # Temporary input
  #
  # HUMAnN does not preserve paired-end relationships.
  # Concatenating two valid gzip streams produces a valid gzipped FASTQ input.
  # --------------------------------------------------------------------------
  combined_fastq="${TMP_DIR}/${sample}.dehost.combined.fastq.gz"

  # --------------------------------------------------------------------------
  # Output folders and files
  # --------------------------------------------------------------------------
  sample_out_dir="${OUT_DIR}/${sample}"

  humann_log="${LOG_DIR}/${sample}.humann.log"
  console_log="${LOG_DIR}/${sample}.console.log"

  genefamilies="${sample_out_dir}/${sample}_genefamilies.tsv"
  pathabundance="${sample_out_dir}/${sample}_pathabundance.tsv"
  pathcoverage="${sample_out_dir}/${sample}_pathcoverage.tsv"

  # --------------------------------------------------------------------------
  # Check required input files
  # --------------------------------------------------------------------------
  for input_file in "${r1}" "${r2}" "${taxonomic_profile}"; do
    if [ ! -s "${input_file}" ]; then
      echo "[ERROR] Missing or empty input file:"
      echo "        ${input_file}"
      exit 1
    fi
  done

  # --------------------------------------------------------------------------
  # Skip completed samples
  #
  # If outputs already exist from a previous successful run, remove any stale
  # temp files and skip recomputation.
  # --------------------------------------------------------------------------
  if verify_outputs \
    "${genefamilies}" \
    "${pathabundance}" \
    "${pathcoverage}"; then

    echo "[INFO] HUMAnN outputs already exist. Skip: ${sample}"

    cleanup_completed_sample \
      "${sample}" \
      "${sample_out_dir}" \
      "${combined_fastq}"

    continue
  fi

  # --------------------------------------------------------------------------
  # Combine paired-end FASTQ files
  #
  # If a previous run was interrupted, reuse the combined FASTQ.
  # --------------------------------------------------------------------------
  if [ ! -s "${combined_fastq}" ]; then
    echo "[INFO] Combining paired-end reads for ${sample}"

    cat \
      "${r1}" \
      "${r2}" \
      > "${combined_fastq}"

    echo "[INFO] Combined FASTQ created:"
    echo "       ${combined_fastq}"
  else
    echo "[INFO] Reusing existing combined FASTQ:"
    echo "       ${combined_fastq}"
  fi

  mkdir -p "${sample_out_dir}"

  # --------------------------------------------------------------------------
  # Functional profiling
  #
  # --taxonomic-profile:
  #   Reuse HUMAnN-compatible MetaPhlAn profile generated by run_03b.
  #
  # --resume:
  #   Reuse valid intermediate files if a previous run was interrupted.
  #
  # --remove-temp-output:
  #   Remove HUMAnN intermediate files after successful completion.
  #
  # --o-log:
  #   Save the official HUMAnN log outside the temporary folder.
  #
  # tee:
  #   Save terminal output separately for troubleshooting.
  #
  # set -o pipefail:
  #   Ensure a HUMAnN failure is not hidden by tee.
  # --------------------------------------------------------------------------
  echo "[INFO] Running HUMAnN for ${sample}"

  humann \
    --input "${combined_fastq}" \
    --output "${sample_out_dir}" \
    --output-basename "${sample}" \
    --threads "${THREADS}" \
    --nucleotide-database "${NUCLEOTIDE_DB}" \
    --protein-database "${PROTEIN_DB}" \
    --taxonomic-profile "${taxonomic_profile}" \
    --resume \
    --remove-temp-output \
    --o-log "${humann_log}" \
    2>&1 | tee "${console_log}"

  # --------------------------------------------------------------------------
  # Validate outputs before removing script-generated temporary input
  # --------------------------------------------------------------------------
  if verify_outputs \
    "${genefamilies}" \
    "${pathabundance}" \
    "${pathcoverage}"; then

    echo "[INFO] HUMAnN outputs verified: ${sample}"

    cleanup_completed_sample \
      "${sample}" \
      "${sample_out_dir}" \
      "${combined_fastq}"
  else
    echo "[ERROR] HUMAnN finished, but one or more expected outputs are missing:"
    echo "        ${genefamilies}"
    echo "        ${pathabundance}"
    echo "        ${pathcoverage}"
    echo
    echo "[ERROR] Temporary files were preserved for troubleshooting."
    exit 1
  fi

  echo "[INFO] Done: ${sample}"
done

# ==============================================================================
# Summary
# ==============================================================================

echo
echo "============================================================"
echo "[INFO] HUMAnN functional profiling completed"
echo "============================================================"

echo
echo "[INFO] Main outputs:"

find "${OUT_DIR}" \
  -maxdepth 2 \
  -type f \
  \( \
    -name "*_genefamilies.tsv" \
    -o -name "*_pathabundance.tsv" \
    -o -name "*_pathcoverage.tsv" \
  \) \
  -print | sort

echo
echo "[INFO] HUMAnN logs:"

find "${LOG_DIR}" \
  -maxdepth 1 \
  -type f \
  \( \
    -name "*.humann.log" \
    -o -name "*.console.log" \
  \) \
  -print | sort
EOF

chmod +x scripts/run_07_humann.sh
```

#### 08. HUMAnN tables
```bash
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Merge HUMAnN functional profiling tables
#
# Required conda environment:
#   conda activate metagenomics-humann
#
# Input:
#   results/07_humann/<sample>/<sample>_genefamilies.tsv
#   results/07_humann/<sample>/<sample>_pathabundance.tsv
#   results/07_humann/<sample>/<sample>_pathcoverage.tsv
#
# Output:
#   results/08_humann_tables/
# ==============================================================================

HUMANN_DIR="results/07_humann"
OUT_DIR="results/08_humann_tables"
NORMALIZED_DIR="${OUT_DIR}/normalized"

SAMPLES=(
  "YZA"
  "YZB"
)

mkdir -p "${NORMALIZED_DIR}"

echo "[INFO] Checking required commands"

command -v humann_renorm_table >/dev/null 2>&1 || {
  echo "[ERROR] humann_renorm_table not found"
  echo "[ERROR] Please run: conda activate metagenomics-humann"
  exit 1
}

command -v humann_join_tables >/dev/null 2>&1 || {
  echo "[ERROR] humann_join_tables not found"
  echo "[ERROR] Please run: conda activate metagenomics-humann"
  exit 1
}

# ------------------------------------------------------------------------------
# Normalize abundance tables
#
# genefamilies:
#   Use CPM because this table contains many features and CPM values are easier
#   to inspect than very small fractions.
#
# pathabundance:
#   Use relative abundance for downstream pathway comparisons and plots.
#
# pathcoverage:
#   Do not normalize; coverage is not an abundance table.
# ------------------------------------------------------------------------------
for sample in "${SAMPLES[@]}"; do
  echo
  echo "============================================================"
  echo "[INFO] Sample: ${sample}"
  echo "============================================================"

  genefamilies_in="${HUMANN_DIR}/${sample}/${sample}_genefamilies.tsv"
  pathabundance_in="${HUMANN_DIR}/${sample}/${sample}_pathabundance.tsv"
  pathcoverage_in="${HUMANN_DIR}/${sample}/${sample}_pathcoverage.tsv"

  genefamilies_out="${NORMALIZED_DIR}/${sample}_genefamilies_cpm.tsv"
  pathabundance_out="${NORMALIZED_DIR}/${sample}_pathabundance_relab.tsv"
  pathcoverage_out="${NORMALIZED_DIR}/${sample}_pathcoverage.tsv"

  for input_file in \
    "${genefamilies_in}" \
    "${pathabundance_in}" \
    "${pathcoverage_in}"
  do
    if [ ! -s "${input_file}" ]; then
      echo "[ERROR] Missing or empty input file:"
      echo "        ${input_file}"
      exit 1
    fi
  done

  echo "[INFO] Normalizing gene families to CPM"
  humann_renorm_table \
    --input "${genefamilies_in}" \
    --output "${genefamilies_out}" \
    --units cpm

  echo "[INFO] Normalizing pathway abundance to relative abundance"
  humann_renorm_table \
    --input "${pathabundance_in}" \
    --output "${pathabundance_out}" \
    --units relab

  echo "[INFO] Copying pathway coverage table"
  cp "${pathcoverage_in}" "${pathcoverage_out}"

  echo "[INFO] Done: ${sample}"
done

# ------------------------------------------------------------------------------
# Join normalized single-sample tables into cohort-level matrices
# ------------------------------------------------------------------------------
echo
echo "[INFO] Joining gene family CPM tables"

humann_join_tables \
  --input "${NORMALIZED_DIR}" \
  --output "${OUT_DIR}/humann_genefamilies_cpm.tsv" \
  --file_name "genefamilies_cpm"

echo "[INFO] Joining pathway relative-abundance tables"

humann_join_tables \
  --input "${NORMALIZED_DIR}" \
  --output "${OUT_DIR}/humann_pathabundance_relab.tsv" \
  --file_name "pathabundance_relab"

echo "[INFO] Joining pathway coverage tables"

humann_join_tables \
  --input "${NORMALIZED_DIR}" \
  --output "${OUT_DIR}/humann_pathcoverage.tsv" \
  --file_name "pathcoverage"

echo
echo "============================================================"
echo "[INFO] HUMAnN table merge completed"
echo "============================================================"

ls -lh "${OUT_DIR}"
EOF

chmod +x scripts/run_08_humann_tables.sh
```

#### U01. megahit assembly
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/assembly_based/run_U01_megahit_assembly.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# U01. Per-sample metagenome assembly using MEGAHIT
#
# Required conda environment:
#   conda activate metagenomics-assembly
#
# Input:
#   results/02_dehost/clean_reads/<sample>_R1.dehost.fq.gz
#   results/02_dehost/clean_reads/<sample>_R2.dehost.fq.gz
#
# Output:
#   results/assembly_based/U01_assembly/<sample>/final.contigs.fa
#
# Design:
#   - Assemble each sample independently.
#   - Merge predicted genes across samples later.
#   - Build a cohort-level non-redundant unigene catalog in U03.
# ==============================================================================

THREADS=12
MEMORY_FRACTION=0.80
MIN_CONTIG_LEN=500

DEHOST_DIR="results/02_dehost/clean_reads"
OUT_DIR="results/assembly_based/U01_assembly"
LOG_DIR="${OUT_DIR}/logs"

SAMPLES=(
  "YZA"
  "YZB"
)

mkdir -p "${OUT_DIR}"
mkdir -p "${LOG_DIR}"

# ==============================================================================
# Preflight checks
# ==============================================================================

echo "============================================================"
echo "[INFO] U01. MEGAHIT per-sample assembly"
echo "============================================================"

command -v megahit >/dev/null 2>&1 || {
  echo "[ERROR] megahit command not found"
  echo "[ERROR] Please run:"
  echo "        conda activate metagenomics-assembly"
  exit 1
}

command -v seqkit >/dev/null 2>&1 || {
  echo "[ERROR] seqkit command not found"
  exit 1
}

echo "[INFO] MEGAHIT version:"
megahit --version

# ==============================================================================
# Run assembly
# ==============================================================================

for sample in "${SAMPLES[@]}"; do
  echo
  echo "============================================================"
  echo "[INFO] Sample: ${sample}"
  echo "============================================================"

  r1="${DEHOST_DIR}/${sample}_R1.dehost.fq.gz"
  r2="${DEHOST_DIR}/${sample}_R2.dehost.fq.gz"

  sample_out_dir="${OUT_DIR}/${sample}"
  final_contigs="${sample_out_dir}/final.contigs.fa"
  log="${LOG_DIR}/${sample}.megahit.log"

  for input_file in "${r1}" "${r2}"; do
    if [ ! -s "${input_file}" ]; then
      echo "[ERROR] Missing or empty input file:"
      echo "        ${input_file}"
      exit 1
    fi
  done

  # --------------------------------------------------------------------------
  # Skip completed assemblies
  # --------------------------------------------------------------------------
  if [ -s "${final_contigs}" ]; then
    echo "[INFO] Existing assembly found. Skip:"
    echo "       ${final_contigs}"
    continue
  fi

  # --------------------------------------------------------------------------
  # Resume interrupted assemblies when an output folder already exists.
  # --------------------------------------------------------------------------
  if [ -d "${sample_out_dir}" ]; then
    echo "[INFO] Existing incomplete MEGAHIT folder found."
    echo "[INFO] Attempting to continue assembly:"
    echo "       ${sample_out_dir}"

    megahit \
      --continue \
      -o "${sample_out_dir}" \
      2>&1 | tee -a "${log}"
  else
    echo "[INFO] Starting MEGAHIT assembly"
    echo "       sample=${sample}"
    echo "       minimum contig length=${MIN_CONTIG_LEN}"
    echo "       threads=${THREADS}"
    echo "       memory fraction=${MEMORY_FRACTION}"

    megahit \
      -1 "${r1}" \
      -2 "${r2}" \
      -o "${sample_out_dir}" \
      --min-contig-len "${MIN_CONTIG_LEN}" \
      --memory "${MEMORY_FRACTION}" \
      -t "${THREADS}" \
      2>&1 | tee "${log}"
  fi

  # --------------------------------------------------------------------------
  # Validate the main assembly output.
  # --------------------------------------------------------------------------
  if [ ! -s "${final_contigs}" ]; then
    echo "[ERROR] MEGAHIT assembly output missing or empty:"
    echo "        ${final_contigs}"
    exit 1
  fi

  echo
  echo "[INFO] Assembly completed:"
  echo "       ${final_contigs}"

  seqkit stats -a -T "${final_contigs}"
done

# ==============================================================================
# Cohort-level summary
# ==============================================================================

echo
echo "============================================================"
echo "[INFO] Writing cohort-level assembly summary"
echo "============================================================"

mapfile -t CONTIG_FILES < <(
  find "${OUT_DIR}" \
    -mindepth 2 \
    -maxdepth 2 \
    -type f \
    -name "final.contigs.fa" \
    | sort
)

if [ "${#CONTIG_FILES[@]}" -eq 0 ]; then
  echo "[ERROR] No final.contigs.fa files found"
  exit 1
fi

seqkit stats \
  -a \
  -T \
  "${CONTIG_FILES[@]}" \
  > "${OUT_DIR}/assembly_stats.tsv"

echo "[INFO] Assembly summary:"
cat "${OUT_DIR}/assembly_stats.tsv"

echo
echo "============================================================"
echo "[INFO] U01 assembly completed"
echo "============================================================"
EOF

chmod +x scripts/assembly_based/run_U01_megahit_assembly.sh
```

#### U02. gene prediction
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/assembly_based/run_U02_predict_genes.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# U02. Prokaryotic gene prediction from assembled metagenomic contigs
#
# Required conda environment:
#   conda activate metagenomics-assembly
#
# Input:
#   results/assembly_based/U01_assembly/<sample>/final.contigs.fa
#
# Output:
#   results/assembly_based/U02_gene_prediction/<sample>/
#   ├── <sample>.contigs.prefixed.fa
#   ├── <sample>.genes.fna
#   ├── <sample>.proteins.faa
#   └── <sample>.genes.gff
#
# Notes:
#   - Prodigal is used in metagenomic mode: -p meta
#   - Contig headers are prefixed with the sample ID before prediction.
#   - Prefixing prevents ID collisions when genes from multiple samples
#     are merged into a cohort-level catalog in U03.
# ==============================================================================

ASSEMBLY_DIR="results/assembly_based/U01_assembly"
OUT_DIR="results/assembly_based/U02_gene_prediction"
LOG_DIR="${OUT_DIR}/logs"

SAMPLES=(
  "YZA"
  "YZB"
)

mkdir -p "${OUT_DIR}"
mkdir -p "${LOG_DIR}"

# ==============================================================================
# Preflight checks
# ==============================================================================

echo "============================================================"
echo "[INFO] U02. Prodigal metagenomic gene prediction"
echo "============================================================"

command -v prodigal >/dev/null 2>&1 || {
  echo "[ERROR] prodigal command not found"
  echo "[ERROR] Please run:"
  echo "        conda activate metagenomics-assembly"
  exit 1
}

command -v seqkit >/dev/null 2>&1 || {
  echo "[ERROR] seqkit command not found"
  echo "[ERROR] Please run:"
  echo "        conda activate metagenomics-assembly"
  exit 1
}

echo "[INFO] Prodigal version:"
prodigal -v 2>&1 || true

# ==============================================================================
# Predict genes
# ==============================================================================

for sample in "${SAMPLES[@]}"; do
  echo
  echo "============================================================"
  echo "[INFO] Sample: ${sample}"
  echo "============================================================"

  contigs="${ASSEMBLY_DIR}/${sample}/final.contigs.fa"

  sample_out_dir="${OUT_DIR}/${sample}"

  prefixed_contigs="${sample_out_dir}/${sample}.contigs.prefixed.fa"
  genes_fna="${sample_out_dir}/${sample}.genes.fna"
  proteins_faa="${sample_out_dir}/${sample}.proteins.faa"
  genes_gff="${sample_out_dir}/${sample}.genes.gff"

  prodigal_log="${LOG_DIR}/${sample}.prodigal.log"

  mkdir -p "${sample_out_dir}"

  # --------------------------------------------------------------------------
  # Check input
  # --------------------------------------------------------------------------
  if [ ! -s "${contigs}" ]; then
    echo "[ERROR] Assembly contigs missing or empty:"
    echo "        ${contigs}"
    exit 1
  fi

  # --------------------------------------------------------------------------
  # Skip completed samples
  # --------------------------------------------------------------------------
  if [ -s "${genes_fna}" ] && \
     [ -s "${proteins_faa}" ] && \
     [ -s "${genes_gff}" ]; then

    echo "[INFO] Gene-prediction outputs already exist. Skip:"
    echo "       ${sample}"
    continue
  fi

  # --------------------------------------------------------------------------
  # Prefix contig IDs with sample ID
  #
  # Example:
  #   >k141_1
  # becomes:
  #   >YZA__k141_1
  #
  # This avoids duplicated feature IDs across samples.
  # --------------------------------------------------------------------------
  if [ ! -s "${prefixed_contigs}" ]; then
    echo "[INFO] Prefixing contig IDs:"
    echo "       sample=${sample}"

    awk \
      -v prefix="${sample}__" \
      '/^>/ {
          sub(/^>/, ">" prefix)
       }
       { print }' \
      "${contigs}" \
      > "${prefixed_contigs}"
  else
    echo "[INFO] Existing prefixed contigs found. Reuse:"
    echo "       ${prefixed_contigs}"
  fi

  # --------------------------------------------------------------------------
  # Run Prodigal in metagenomic mode
  #
  # -i : input contigs
  # -p meta : metagenomic mode
  # -d : nucleotide coding sequences
  # -a : translated protein sequences
  # -f gff : GFF output format
  # -o : gene-coordinate annotation
  # --------------------------------------------------------------------------
  echo "[INFO] Running Prodigal:"
  echo "       sample=${sample}"

  prodigal \
    -i "${prefixed_contigs}" \
    -p meta \
    -d "${genes_fna}" \
    -a "${proteins_faa}" \
    -f gff \
    -o "${genes_gff}" \
    2>&1 | tee "${prodigal_log}"

  # --------------------------------------------------------------------------
  # Validate outputs
  # --------------------------------------------------------------------------
  for output_file in \
    "${genes_fna}" \
    "${proteins_faa}" \
    "${genes_gff}"
  do
    if [ ! -s "${output_file}" ]; then
      echo "[ERROR] Prodigal output missing or empty:"
      echo "        ${output_file}"
      exit 1
    fi
  done

  echo
  echo "[INFO] Gene prediction completed:"
  echo "       sample=${sample}"

  echo "[INFO] Nucleotide genes:"
  seqkit stats -T "${genes_fna}"

  echo
  echo "[INFO] Protein sequences:"
  seqkit stats -T "${proteins_faa}"
done

# ==============================================================================
# Cohort-level summary
# ==============================================================================

echo
echo "============================================================"
echo "[INFO] Writing cohort-level gene-prediction summaries"
echo "============================================================"

mapfile -t GENE_FILES < <(
  find "${OUT_DIR}" \
    -mindepth 2 \
    -maxdepth 2 \
    -type f \
    -name "*.genes.fna" \
    | sort
)

mapfile -t PROTEIN_FILES < <(
  find "${OUT_DIR}" \
    -mindepth 2 \
    -maxdepth 2 \
    -type f \
    -name "*.proteins.faa" \
    | sort
)

if [ "${#GENE_FILES[@]}" -eq 0 ]; then
  echo "[ERROR] No predicted nucleotide-gene files found"
  exit 1
fi

if [ "${#PROTEIN_FILES[@]}" -eq 0 ]; then
  echo "[ERROR] No predicted protein files found"
  exit 1
fi

seqkit stats \
  -a \
  -T \
  "${GENE_FILES[@]}" \
  > "${OUT_DIR}/predicted_gene_stats.tsv"

seqkit stats \
  -a \
  -T \
  "${PROTEIN_FILES[@]}" \
  > "${OUT_DIR}/predicted_protein_stats.tsv"

echo
echo "[INFO] Predicted nucleotide-gene summary:"
cat "${OUT_DIR}/predicted_gene_stats.tsv"

echo
echo "[INFO] Predicted protein summary:"
cat "${OUT_DIR}/predicted_protein_stats.tsv"

echo
echo "============================================================"
echo "[INFO] U02 gene prediction completed"
echo "============================================================"
EOF

chmod +x scripts/assembly_based/run_U02_predict_genes.sh
```

#### U03. build non-redundant unigene catalog
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/assembly_based/run_U03_build_unigene_catalog.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# U03. Build a cohort-level non-redundant unigene catalog
#
# Required conda environment:
#   conda activate metagenomics-assembly
#
# Input:
#   results/assembly_based/U02_gene_prediction/<sample>/<sample>.genes.fna
#   results/assembly_based/U02_gene_prediction/<sample>/<sample>.proteins.faa
#
# Output:
#   results/assembly_based/U03_unigene_catalog/
#   ├── combined_predicted_genes.fna
#   ├── combined_predicted_proteins.faa
#   ├── cd_hit_est/
#   │   ├── representative_genes.raw.fna
#   │   └── representative_genes.raw.fna.clstr
#   ├── unigene_catalog.fna
#   ├── unigene_catalog.faa
#   ├── unigene_id_mapping.tsv
#   ├── unigene_lengths.tsv
#   ├── unigene_catalog_stats.tsv
#   └── logs/
#
# Clustering rule:
#   - nucleotide sequence identity >= 95%
#   - alignment covers >= 90% of the shorter sequence
#
# Notes:
#   - Representative genes are renamed as unigene_1, unigene_2, ...
#   - Original representative IDs are retained in unigene_id_mapping.tsv.
#   - The raw CD-HIT-EST representative sequences and cluster listing are kept
#     for traceability.
# ==============================================================================

THREADS=12
MEMORY_MB=90000

IDENTITY=0.95
SHORTER_SEQUENCE_COVERAGE=0.90

GENE_PREDICTION_DIR="results/assembly_based/U02_gene_prediction"
OUT_DIR="results/assembly_based/U03_unigene_catalog"
CLUSTER_DIR="${OUT_DIR}/cd_hit_est"
LOG_DIR="${OUT_DIR}/logs"

SAMPLES=(
  "YZA"
  "YZB"
)

COMBINED_GENES="${OUT_DIR}/combined_predicted_genes.fna"
COMBINED_PROTEINS="${OUT_DIR}/combined_predicted_proteins.faa"

RAW_REPRESENTATIVE_GENES="${CLUSTER_DIR}/representative_genes.raw.fna"

UNIGENE_CATALOG_FNA="${OUT_DIR}/unigene_catalog.fna"
UNIGENE_CATALOG_FAA="${OUT_DIR}/unigene_catalog.faa"

UNIGENE_ID_MAPPING="${OUT_DIR}/unigene_id_mapping.tsv"
UNIGENE_LENGTHS="${OUT_DIR}/unigene_lengths.tsv"
CATALOG_STATS="${OUT_DIR}/unigene_catalog_stats.tsv"

CD_HIT_LOG="${LOG_DIR}/cd_hit_est.log"

mkdir -p "${OUT_DIR}"
mkdir -p "${CLUSTER_DIR}"
mkdir -p "${LOG_DIR}"

# ==============================================================================
# Preflight checks
# ==============================================================================

echo "============================================================"
echo "[INFO] U03. Build non-redundant unigene catalog"
echo "============================================================"

command -v cd-hit-est >/dev/null 2>&1 || {
  echo "[ERROR] cd-hit-est command not found"
  echo "[ERROR] Please run:"
  echo "        conda activate metagenomics-assembly"
  exit 1
}

command -v seqkit >/dev/null 2>&1 || {
  echo "[ERROR] seqkit command not found"
  echo "[ERROR] Please run:"
  echo "        conda activate metagenomics-assembly"
  exit 1
}

command -v python >/dev/null 2>&1 || {
  echo "[ERROR] python command not found"
  exit 1
}

echo "[INFO] CD-HIT-EST command:"
command -v cd-hit-est

echo "[INFO] Threads: ${THREADS}"
echo "[INFO] CD-HIT memory limit: ${MEMORY_MB} MB"
echo "[INFO] Identity threshold: ${IDENTITY}"
echo "[INFO] Shorter-sequence coverage threshold: ${SHORTER_SEQUENCE_COVERAGE}"

# ==============================================================================
# Check input files
# ==============================================================================

GENE_FILES=()
PROTEIN_FILES=()

for sample in "${SAMPLES[@]}"; do
  genes="${GENE_PREDICTION_DIR}/${sample}/${sample}.genes.fna"
  proteins="${GENE_PREDICTION_DIR}/${sample}/${sample}.proteins.faa"

  for input_file in "${genes}" "${proteins}"; do
    if [ ! -s "${input_file}" ]; then
      echo "[ERROR] Missing or empty input file:"
      echo "        ${input_file}"
      exit 1
    fi
  done

  GENE_FILES+=("${genes}")
  PROTEIN_FILES+=("${proteins}")
done

# ==============================================================================
# Merge predicted genes and proteins across samples
# ==============================================================================

if [ ! -s "${COMBINED_GENES}" ]; then
  echo
  echo "[INFO] Combining predicted nucleotide genes"

  cat "${GENE_FILES[@]}" > "${COMBINED_GENES}"
else
  echo
  echo "[INFO] Existing combined nucleotide-gene FASTA found. Reuse:"
  echo "       ${COMBINED_GENES}"
fi

if [ ! -s "${COMBINED_PROTEINS}" ]; then
  echo
  echo "[INFO] Combining predicted protein sequences"

  cat "${PROTEIN_FILES[@]}" > "${COMBINED_PROTEINS}"
else
  echo
  echo "[INFO] Existing combined protein FASTA found. Reuse:"
  echo "       ${COMBINED_PROTEINS}"
fi

echo
echo "[INFO] Combined nucleotide genes:"
seqkit stats -a -T "${COMBINED_GENES}"

echo
echo "[INFO] Combined proteins:"
seqkit stats -a -T "${COMBINED_PROTEINS}"

# ==============================================================================
# Cluster nucleotide genes using CD-HIT-EST
#
# -c  : nucleotide identity threshold
# -aS : minimum alignment coverage of the shorter sequence
# -G 0: use local sequence identity
# -g 1: use more accurate clustering mode
# -d 0: preserve complete sequence identifiers
# -n 10: word length suitable for >= 0.95 nucleotide identity
# ==============================================================================

if [ ! -s "${RAW_REPRESENTATIVE_GENES}" ] || \
   [ ! -s "${RAW_REPRESENTATIVE_GENES}.clstr" ]; then

  echo
  echo "============================================================"
  echo "[INFO] Running CD-HIT-EST clustering"
  echo "============================================================"

  cd-hit-est \
    -i "${COMBINED_GENES}" \
    -o "${RAW_REPRESENTATIVE_GENES}" \
    -c "${IDENTITY}" \
    -aS "${SHORTER_SEQUENCE_COVERAGE}" \
    -G 0 \
    -g 1 \
    -d 0 \
    -n 10 \
    -T "${THREADS}" \
    -M "${MEMORY_MB}" \
    2>&1 | tee "${CD_HIT_LOG}"
else
  echo
  echo "[INFO] Existing CD-HIT-EST results found. Skip clustering:"
  echo "       ${RAW_REPRESENTATIVE_GENES}"
  echo "       ${RAW_REPRESENTATIVE_GENES}.clstr"
fi

if [ ! -s "${RAW_REPRESENTATIVE_GENES}" ]; then
  echo "[ERROR] CD-HIT-EST representative-gene FASTA missing or empty:"
  echo "        ${RAW_REPRESENTATIVE_GENES}"
  exit 1
fi

if [ ! -s "${RAW_REPRESENTATIVE_GENES}.clstr" ]; then
  echo "[ERROR] CD-HIT-EST cluster listing missing or empty:"
  echo "        ${RAW_REPRESENTATIVE_GENES}.clstr"
  exit 1
fi

# ==============================================================================
# Rename representative sequences as unigene_1, unigene_2, ...
#
# The Python block:
#   1. Reads representative nucleotide genes.
#   2. Builds a deterministic original-ID -> unigene-ID mapping.
#   3. Extracts corresponding representative proteins.
#   4. Writes nucleotide and protein unigene catalogs.
#   5. Writes a length table for later normalization.
# ==============================================================================

echo
echo "============================================================"
echo "[INFO] Renaming representative genes as unigenes"
echo "============================================================"

python - <<'PY'
from __future__ import annotations

from pathlib import Path
from typing import Iterator

OUT_DIR = Path("results/assembly_based/U03_unigene_catalog")
CLUSTER_DIR = OUT_DIR / "cd_hit_est"

RAW_REPRESENTATIVE_GENES = (
    CLUSTER_DIR / "representative_genes.raw.fna"
)
COMBINED_PROTEINS = (
    OUT_DIR / "combined_predicted_proteins.faa"
)

UNIGENE_CATALOG_FNA = OUT_DIR / "unigene_catalog.fna"
UNIGENE_CATALOG_FAA = OUT_DIR / "unigene_catalog.faa"

UNIGENE_ID_MAPPING = OUT_DIR / "unigene_id_mapping.tsv"
UNIGENE_LENGTHS = OUT_DIR / "unigene_lengths.tsv"


def read_fasta(path: Path) -> Iterator[tuple[str, str, str]]:
    """
    Yield:
        sequence_id
        original_header
        sequence
    """
    sequence_id: str | None = None
    header: str | None = None
    sequence_parts: list[str] = []

    with path.open("rt", encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")

            if line.startswith(">"):
                if sequence_id is not None and header is not None:
                    yield (
                        sequence_id,
                        header,
                        "".join(sequence_parts),
                    )

                header = line[1:]
                sequence_id = header.split()[0]
                sequence_parts = []
            else:
                sequence_parts.append(line.strip())

    if sequence_id is not None and header is not None:
        yield (
            sequence_id,
            header,
            "".join(sequence_parts),
        )


def write_wrapped_sequence(
    handle,
    sequence: str,
    width: int = 80,
) -> None:
    for start in range(0, len(sequence), width):
        handle.write(sequence[start:start + width] + "\n")


# -------------------------------------------------------------------------
# Read representative nucleotide genes and establish stable unigene IDs
# -------------------------------------------------------------------------
representative_genes = list(
    read_fasta(RAW_REPRESENTATIVE_GENES)
)

if not representative_genes:
    raise SystemExit(
        "[ERROR] No representative genes found in CD-HIT-EST output"
    )

original_to_unigene: dict[str, str] = {}

with (
    UNIGENE_CATALOG_FNA.open("wt", encoding="utf-8") as fna_handle,
    UNIGENE_ID_MAPPING.open("wt", encoding="utf-8") as map_handle,
    UNIGENE_LENGTHS.open("wt", encoding="utf-8") as length_handle,
):
    map_handle.write(
        "unigene_id\trepresentative_original_id\n"
    )

    length_handle.write(
        "unigene_id\tgene_length_bp\n"
    )

    for index, (
        original_id,
        _original_header,
        sequence,
    ) in enumerate(
        representative_genes,
        start=1,
    ):
        unigene_id = f"unigene_{index}"

        if original_id in original_to_unigene:
            raise SystemExit(
                f"[ERROR] Duplicated representative gene ID: "
                f"{original_id}"
            )

        original_to_unigene[original_id] = unigene_id

        fna_handle.write(f">{unigene_id}\n")
        write_wrapped_sequence(
            fna_handle,
            sequence,
        )

        map_handle.write(
            f"{unigene_id}\t{original_id}\n"
        )

        length_handle.write(
            f"{unigene_id}\t{len(sequence)}\n"
        )

# -------------------------------------------------------------------------
# Extract matching representative proteins and rename them consistently
# -------------------------------------------------------------------------
protein_count = 0

with UNIGENE_CATALOG_FAA.open(
    "wt",
    encoding="utf-8",
) as faa_handle:
    for (
        original_id,
        _original_header,
        sequence,
    ) in read_fasta(COMBINED_PROTEINS):
        unigene_id = original_to_unigene.get(original_id)

        if unigene_id is None:
            continue

        faa_handle.write(f">{unigene_id}\n")
        write_wrapped_sequence(
            faa_handle,
            sequence,
        )

        protein_count += 1

expected_count = len(original_to_unigene)

if protein_count != expected_count:
    raise SystemExit(
        "[ERROR] Representative protein extraction mismatch: "
        f"expected={expected_count}, found={protein_count}"
    )

print(
    "[INFO] Representative nucleotide genes: "
    f"{expected_count}"
)

print(
    "[INFO] Representative protein sequences: "
    f"{protein_count}"
)
PY

# ==============================================================================
# Validate final catalogs
# ==============================================================================

for output_file in \
  "${UNIGENE_CATALOG_FNA}" \
  "${UNIGENE_CATALOG_FAA}" \
  "${UNIGENE_ID_MAPPING}" \
  "${UNIGENE_LENGTHS}"
do
  if [ ! -s "${output_file}" ]; then
    echo "[ERROR] Final unigene-catalog output missing or empty:"
    echo "        ${output_file}"
    exit 1
  fi
done

# ==============================================================================
# Catalog statistics
# ==============================================================================

seqkit stats \
  -a \
  -T \
  "${UNIGENE_CATALOG_FNA}" \
  "${UNIGENE_CATALOG_FAA}" \
  > "${CATALOG_STATS}"

echo
echo "============================================================"
echo "[INFO] U03 unigene catalog completed"
echo "============================================================"

echo
echo "[INFO] Catalog summary:"
cat "${CATALOG_STATS}"

echo
echo "[INFO] Main outputs:"
echo "       ${UNIGENE_CATALOG_FNA}"
echo "       ${UNIGENE_CATALOG_FAA}"
echo "       ${UNIGENE_ID_MAPPING}"
echo "       ${UNIGENE_LENGTHS}"
echo "       ${RAW_REPRESENTATIVE_GENES}.clstr"
EOF

chmod +x scripts/assembly_based/run_U03_build_unigene_catalog.sh
```

#### U04. Reads mapping to unigene catalog
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/assembly_based/run_U04_map_reads_to_catalog.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# U04. Map host-depleted reads back to the non-redundant unigene catalog
#
# Required conda environment:
#   conda activate metagenomics-assembly
#
# Input:
#   results/02_dehost/clean_reads/<sample>_R1.dehost.fq.gz
#   results/02_dehost/clean_reads/<sample>_R2.dehost.fq.gz
#
#   results/assembly_based/U03_unigene_catalog/unigene_catalog.fna
#
# Output:
#   results/assembly_based/U04_mapping/
#   ├── bowtie2_index/
#   ├── bam/
#   │   ├── <sample>.unigene.primary_mapped.sorted.bam
#   │   └── <sample>.unigene.primary_mapped.sorted.bam.bai
#   ├── idxstats/
#   │   └── <sample>.unigene.idxstats.tsv
#   ├── flagstat/
#   │   └── <sample>.unigene.flagstat.txt
#   └── logs/
#       ├── bowtie2_build.log
#       └── <sample>.bowtie2.log
#
# Alignment policy:
#   - Bowtie2 paired-end mapping
#   - --very-sensitive preset
#   - retain primary mapped alignments only
#
# SAM flags excluded by samtools view -F 2308:
#   0x4    = unmapped
#   0x100  = secondary alignment
#   0x800  = supplementary alignment
#
# Notes:
#   - U04 generates mapping files and per-unigene mapped-read statistics.
#   - U05 will merge samples and calculate count / normalized-abundance tables.
# ==============================================================================

THREADS=12

DEHOST_DIR="results/02_dehost/clean_reads"

CATALOG_FNA="results/assembly_based/U03_unigene_catalog/unigene_catalog.fna"

OUT_DIR="results/assembly_based/U04_mapping"

INDEX_DIR="${OUT_DIR}/bowtie2_index"
INDEX_PREFIX="${INDEX_DIR}/unigene_catalog"

BAM_DIR="${OUT_DIR}/bam"
IDXSTATS_DIR="${OUT_DIR}/idxstats"
FLAGSTAT_DIR="${OUT_DIR}/flagstat"
LOG_DIR="${OUT_DIR}/logs"

SAMPLES=(
  "YZA"
  "YZB"
)

mkdir -p "${INDEX_DIR}"
mkdir -p "${BAM_DIR}"
mkdir -p "${IDXSTATS_DIR}"
mkdir -p "${FLAGSTAT_DIR}"
mkdir -p "${LOG_DIR}"

# ==============================================================================
# Preflight checks
# ==============================================================================

echo "============================================================"
echo "[INFO] U04. Map reads back to unigene catalog"
echo "============================================================"

command -v bowtie2 >/dev/null 2>&1 || {
  echo "[ERROR] bowtie2 command not found"
  echo "[ERROR] Please run:"
  echo "        conda activate metagenomics-assembly"
  exit 1
}

command -v bowtie2-build >/dev/null 2>&1 || {
  echo "[ERROR] bowtie2-build command not found"
  echo "[ERROR] Please run:"
  echo "        conda activate metagenomics-assembly"
  exit 1
}

command -v samtools >/dev/null 2>&1 || {
  echo "[ERROR] samtools command not found"
  echo "[ERROR] Please run:"
  echo "        conda activate metagenomics-assembly"
  exit 1
}

if [ ! -s "${CATALOG_FNA}" ]; then
  echo "[ERROR] Unigene catalog missing or empty:"
  echo "        ${CATALOG_FNA}"
  exit 1
fi

echo "[INFO] Bowtie2 version:"
bowtie2 --version | head -n 1

echo
echo "[INFO] Samtools version:"
samtools --version | head -n 1

# ==============================================================================
# Build Bowtie2 index once
# ==============================================================================

if compgen -G "${INDEX_PREFIX}*.bt2*" >/dev/null; then
  echo
  echo "[INFO] Existing Bowtie2 unigene-catalog index found. Reuse:"
  echo "       ${INDEX_PREFIX}"
else
  echo
  echo "============================================================"
  echo "[INFO] Building Bowtie2 unigene-catalog index"
  echo "============================================================"

  bowtie2-build \
    "${CATALOG_FNA}" \
    "${INDEX_PREFIX}" \
    2>&1 | tee "${LOG_DIR}/bowtie2_build.log"
fi

if ! compgen -G "${INDEX_PREFIX}*.bt2*" >/dev/null; then
  echo "[ERROR] Bowtie2 index construction failed:"
  echo "        ${INDEX_PREFIX}*.bt2*"
  exit 1
fi

# ==============================================================================
# Map reads for each sample
# ==============================================================================

for sample in "${SAMPLES[@]}"; do
  echo
  echo "============================================================"
  echo "[INFO] Sample: ${sample}"
  echo "============================================================"

  r1="${DEHOST_DIR}/${sample}_R1.dehost.fq.gz"
  r2="${DEHOST_DIR}/${sample}_R2.dehost.fq.gz"

  bam="${BAM_DIR}/${sample}.unigene.primary_mapped.sorted.bam"
  bai="${bam}.bai"

  idxstats="${IDXSTATS_DIR}/${sample}.unigene.idxstats.tsv"
  flagstat="${FLAGSTAT_DIR}/${sample}.unigene.flagstat.txt"

  bowtie2_log="${LOG_DIR}/${sample}.bowtie2.log"

  for input_file in "${r1}" "${r2}"; do
    if [ ! -s "${input_file}" ]; then
      echo "[ERROR] Missing or empty input file:"
      echo "        ${input_file}"
      exit 1
    fi
  done

  # --------------------------------------------------------------------------
  # Skip completed sample
  # --------------------------------------------------------------------------
  if [ -s "${bam}" ] && \
     [ -s "${bai}" ] && \
     [ -s "${idxstats}" ] && \
     [ -s "${flagstat}" ]; then

    echo "[INFO] Mapping outputs already exist. Skip:"
    echo "       ${sample}"
    continue
  fi

  # --------------------------------------------------------------------------
  # Bowtie2 alignment
  #
  # samtools view -F 2308:
  #   discard unmapped, secondary, and supplementary alignments.
  #
  # samtools sort:
  #   coordinate-sort mapped primary alignments.
  # --------------------------------------------------------------------------
  echo "[INFO] Mapping reads to unigene catalog:"
  echo "       sample=${sample}"

  bowtie2 \
    -x "${INDEX_PREFIX}" \
    -1 "${r1}" \
    -2 "${r2}" \
    --very-sensitive \
    --threads "${THREADS}" \
    2> "${bowtie2_log}" \
  | samtools view \
      -@ "${THREADS}" \
      -b \
      -F 2308 \
      - \
  | samtools sort \
      -@ "${THREADS}" \
      -o "${bam}" \
      -

  # --------------------------------------------------------------------------
  # BAM index and mapping statistics
  # --------------------------------------------------------------------------
  samtools index \
    -@ "${THREADS}" \
    "${bam}"

  samtools flagstat \
    -@ "${THREADS}" \
    "${bam}" \
    > "${flagstat}"

  samtools idxstats \
    "${bam}" \
    > "${idxstats}"

  # --------------------------------------------------------------------------
  # Validate outputs
  # --------------------------------------------------------------------------
  for output_file in \
    "${bam}" \
    "${bai}" \
    "${idxstats}" \
    "${flagstat}" \
    "${bowtie2_log}"
  do
    if [ ! -s "${output_file}" ]; then
      echo "[ERROR] Mapping output missing or empty:"
      echo "        ${output_file}"
      exit 1
    fi
  done

  echo
  echo "[INFO] Mapping completed:"
  echo "       sample=${sample}"

  echo
  echo "[INFO] Bowtie2 mapping summary:"
  tail -n 8 "${bowtie2_log}"

  echo
  echo "[INFO] Samtools flagstat:"
  cat "${flagstat}"
done

# ==============================================================================
# Summary
# ==============================================================================

echo
echo "============================================================"
echo "[INFO] U04 mapping completed"
echo "============================================================"

echo
echo "[INFO] BAM files:"
find "${BAM_DIR}" \
  -maxdepth 1 \
  -type f \
  -name "*.bam" \
  -print | sort

echo
echo "[INFO] Per-unigene idxstats files:"
find "${IDXSTATS_DIR}" \
  -maxdepth 1 \
  -type f \
  -name "*.idxstats.tsv" \
  -print | sort
EOF

chmod +x scripts/assembly_based/run_U04_map_reads_to_catalog.sh
```

#### U05. Quantify unigenes
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/assembly_based/run_U05_quantify_unigenes.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# U05. Build cohort-level unigene abundance tables
#
# Required conda environment:
#   conda activate metagenomics-assembly
#
# Input:
#   results/assembly_based/U04_mapping/idxstats/
#   ├── <sample>.unigene.idxstats.tsv
#
#   results/assembly_based/U03_unigene_catalog/
#   └── unigene_lengths.tsv
#
# Output:
#   results/assembly_based/U05_unigene_abundance/
#   ├── unigene_mapped_read_segments.tsv
#   ├── unigene_rpk.tsv
#   ├── unigene_tpm.tsv
#   ├── unigene_relative_abundance.tsv
#   ├── unigene_quantification_summary.tsv
#   └── README.md
#
# Matrix orientation:
#   rows    = unigenes
#   columns = samples
#
# Definitions:
#   mapped_read_segments:
#       Number of mapped read-segments reported by samtools idxstats.
#
#   RPK:
#       mapped_read_segments / gene_length_kb
#
#   TPM:
#       RPK / sum(RPK within sample) * 1,000,000
#
#   relative_abundance:
#       RPK / sum(RPK within sample)
#
# Notes:
#   - relative_abundance equals TPM / 1,000,000.
#   - This is a transparent, reproducible BGI-like unigene-abundance workflow.
#   - It should not be described as an exact reproduction of any proprietary
#     normalization formula unless the original provider documents its method.
# ==============================================================================

IDXSTATS_DIR="results/assembly_based/U04_mapping/idxstats"

UNIGENE_LENGTHS="results/assembly_based/U03_unigene_catalog/unigene_lengths.tsv"

OUT_DIR="results/assembly_based/U05_unigene_abundance"

mkdir -p "${OUT_DIR}"

# ==============================================================================
# Preflight checks
# ==============================================================================

echo "============================================================"
echo "[INFO] U05. Quantify cohort-level unigene abundance"
echo "============================================================"

command -v python >/dev/null 2>&1 || {
  echo "[ERROR] python command not found"
  exit 1
}

python - <<'PY'
try:
    import pandas  # noqa: F401
except ImportError as exc:
    raise SystemExit(
        "[ERROR] Python package not found: pandas\n"
        "[ERROR] Please install pandas in metagenomics-assembly environment."
    ) from exc
PY

if [ ! -s "${UNIGENE_LENGTHS}" ]; then
  echo "[ERROR] Unigene-length table missing or empty:"
  echo "        ${UNIGENE_LENGTHS}"
  exit 1
fi

if ! compgen -G "${IDXSTATS_DIR}/*.unigene.idxstats.tsv" >/dev/null; then
  echo "[ERROR] No samtools idxstats tables found:"
  echo "        ${IDXSTATS_DIR}/*.unigene.idxstats.tsv"
  exit 1
fi

# ==============================================================================
# Build cohort-level abundance matrices
# ==============================================================================

python - <<'PY'
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd


# =============================================================================
# Configuration
# =============================================================================

IDXSTATS_DIR = Path(
    "results/assembly_based/U04_mapping/idxstats"
)

UNIGENE_LENGTHS_PATH = Path(
    "results/assembly_based/U03_unigene_catalog/unigene_lengths.tsv"
)

OUT_DIR = Path(
    "results/assembly_based/U05_unigene_abundance"
)

MAPPED_SEGMENTS_OUT = (
    OUT_DIR / "unigene_mapped_read_segments.tsv"
)

RPK_OUT = (
    OUT_DIR / "unigene_rpk.tsv"
)

TPM_OUT = (
    OUT_DIR / "unigene_tpm.tsv"
)

RELATIVE_ABUNDANCE_OUT = (
    OUT_DIR / "unigene_relative_abundance.tsv"
)

SUMMARY_OUT = (
    OUT_DIR / "unigene_quantification_summary.tsv"
)


# =============================================================================
# Load unigene lengths
# =============================================================================

lengths_df = pd.read_csv(
    UNIGENE_LENGTHS_PATH,
    sep="\t",
)

required_length_cols = {
    "unigene_id",
    "gene_length_bp",
}

missing_length_cols = required_length_cols.difference(
    lengths_df.columns
)

if missing_length_cols:
    raise ValueError(
        f"{UNIGENE_LENGTHS_PATH} is missing required columns: "
        f"{sorted(missing_length_cols)}"
    )

lengths_df["unigene_id"] = (
    lengths_df["unigene_id"]
    .astype(str)
)

lengths_df["gene_length_bp"] = pd.to_numeric(
    lengths_df["gene_length_bp"],
    errors="raise",
)

if lengths_df["unigene_id"].duplicated().any():
    duplicated_ids = (
        lengths_df.loc[
            lengths_df["unigene_id"].duplicated(),
            "unigene_id",
        ]
        .head()
        .tolist()
    )

    raise ValueError(
        "Duplicated unigene IDs found in length table: "
        f"{duplicated_ids}"
    )

if (lengths_df["gene_length_bp"] <= 0).any():
    raise ValueError(
        "All unigene lengths must be positive."
    )

lengths = (
    lengths_df
    .set_index("unigene_id")["gene_length_bp"]
    .sort_index()
)

lengths.index.name = "unigene_id"


# =============================================================================
# Load sample-level samtools idxstats
#
# idxstats columns:
#   reference_name
#   reference_length
#   mapped_read_segments
#   unmapped_read_segments
# =============================================================================

sample_series_list: list[pd.Series] = []

summary_rows: list[dict[str, int | float | str]] = []

idxstats_paths = sorted(
    IDXSTATS_DIR.glob("*.unigene.idxstats.tsv")
)

if not idxstats_paths:
    raise FileNotFoundError(
        f"No idxstats tables found in: {IDXSTATS_DIR}"
    )

for path in idxstats_paths:
    sample_id = path.name.removesuffix(
        ".unigene.idxstats.tsv"
    )

    idxstats_df = pd.read_csv(
        path,
        sep="\t",
        header=None,
        names=[
            "reference_name",
            "reference_length",
            "mapped_read_segments",
            "unmapped_read_segments",
        ],
        dtype={
            "reference_name": str,
        },
    )

    # samtools idxstats includes a final '*' row for unmapped reads.
    idxstats_df = idxstats_df.loc[
        idxstats_df["reference_name"] != "*"
    ].copy()

    idxstats_df["reference_name"] = (
        idxstats_df["reference_name"]
        .astype(str)
    )

    idxstats_df["reference_length"] = pd.to_numeric(
        idxstats_df["reference_length"],
        errors="raise",
    )

    idxstats_df["mapped_read_segments"] = pd.to_numeric(
        idxstats_df["mapped_read_segments"],
        errors="raise",
    ).astype(np.int64)

    idxstats_df["unmapped_read_segments"] = pd.to_numeric(
        idxstats_df["unmapped_read_segments"],
        errors="raise",
    ).astype(np.int64)

    if idxstats_df["reference_name"].duplicated().any():
        raise ValueError(
            f"Duplicated reference names found in: {path}"
        )

    sample_counts = (
        idxstats_df
        .set_index("reference_name")["mapped_read_segments"]
        .rename(sample_id)
    )

    sample_counts.index.name = "unigene_id"

    # Validate catalog consistency.
    missing_from_idxstats = lengths.index.difference(
        sample_counts.index
    )

    unexpected_in_idxstats = sample_counts.index.difference(
        lengths.index
    )

    if len(missing_from_idxstats) > 0:
        raise ValueError(
            f"{path} is missing {len(missing_from_idxstats)} "
            "catalog unigenes."
        )

    if len(unexpected_in_idxstats) > 0:
        raise ValueError(
            f"{path} contains {len(unexpected_in_idxstats)} "
            "unexpected references."
        )

    sample_counts = sample_counts.reindex(
        lengths.index,
        fill_value=0,
    )

    sample_series_list.append(
        sample_counts
    )

    detected_unigenes = int(
        (sample_counts > 0).sum()
    )

    total_mapped_segments = int(
        sample_counts.sum()
    )

    summary_rows.append(
        {
            "sample_id": sample_id,
            "catalog_unigenes": int(len(sample_counts)),
            "detected_unigenes": detected_unigenes,
            "detected_unigene_fraction": (
                detected_unigenes / len(sample_counts)
            ),
            "total_mapped_read_segments": total_mapped_segments,
        }
    )


# =============================================================================
# Build mapped-read-segment count matrix
# =============================================================================

counts_df = pd.concat(
    sample_series_list,
    axis=1,
)

counts_df.index.name = "unigene_id"

counts_df = counts_df.astype(np.int64)


# =============================================================================
# Normalize by gene length
#
# RPK:
#   mapped_read_segments / gene_length_kb
#
# TPM:
#   RPK / sum(RPK within sample) * 1,000,000
#
# Relative abundance:
#   RPK / sum(RPK within sample)
# =============================================================================

gene_length_kb = lengths / 1000.0

rpk_df = counts_df.div(
    gene_length_kb,
    axis=0,
)

rpk_sums = rpk_df.sum(
    axis=0,
)

if (rpk_sums <= 0).any():
    failed_samples = rpk_sums.loc[
        rpk_sums <= 0
    ].index.tolist()

    raise ValueError(
        "One or more samples have zero total RPK: "
        f"{failed_samples}"
    )

relative_abundance_df = rpk_df.div(
    rpk_sums,
    axis=1,
)

tpm_df = relative_abundance_df * 1_000_000.0


# =============================================================================
# Write tables
# =============================================================================

counts_df.to_csv(
    MAPPED_SEGMENTS_OUT,
    sep="\t",
    index=True,
)

rpk_df.to_csv(
    RPK_OUT,
    sep="\t",
    index=True,
    float_format="%.10g",
)

tpm_df.to_csv(
    TPM_OUT,
    sep="\t",
    index=True,
    float_format="%.10g",
)

relative_abundance_df.to_csv(
    RELATIVE_ABUNDANCE_OUT,
    sep="\t",
    index=True,
    float_format="%.10g",
)

summary_df = pd.DataFrame(
    summary_rows
)

summary_df.to_csv(
    SUMMARY_OUT,
    sep="\t",
    index=False,
    float_format="%.10g",
)


# =============================================================================
# Validate output sums
# =============================================================================

relative_abundance_sums = (
    relative_abundance_df.sum(axis=0)
)

tpm_sums = (
    tpm_df.sum(axis=0)
)

print()
print("============================================================")
print("[INFO] U05 unigene quantification completed")
print("============================================================")

print(
    "[INFO] Catalog unigenes: "
    f"{counts_df.shape[0]:,}"
)

print(
    "[INFO] Samples: "
    f"{counts_df.shape[1]}"
)

print()
print("[INFO] Summary:")
print(
    summary_df.to_string(
        index=False,
    )
)

print()
print("[INFO] Relative-abundance column sums:")
print(
    relative_abundance_sums.to_string()
)

print()
print("[INFO] TPM column sums:")
print(
    tpm_sums.to_string()
)
PY

# ==============================================================================
# Write README
# ==============================================================================

cat > "${OUT_DIR}/README.md" <<'EOF_README'
# U05 unigene abundance tables

## Input

The tables were generated from `samtools idxstats` outputs produced after
mapping host-depleted paired-end reads back to the non-redundant unigene
catalog.

## Matrix orientation

- Rows: unigenes
- Columns: samples

## Output tables

### `unigene_mapped_read_segments.tsv`

Mapped read-segment counts reported by `samtools idxstats`.

For paired-end sequencing, R1 and R2 are counted as separate mapped
read-segments when both are aligned. This table must not be described as an
ASV table or as an exact read-pair count table.

### `unigene_rpk.tsv`

Mapped read-segments divided by unigene length in kilobases.

### `unigene_tpm.tsv`

Length-normalized abundance scaled so that each sample sums to 1,000,000.

### `unigene_relative_abundance.tsv`

Length-normalized relative abundance scaled so that each sample sums to 1.

This output is suitable for producing a BGI-like `all_gene_abundance_transpose`
table, but it should not be described as an exact reproduction of a
proprietary workflow unless the original normalization formula is documented.

### `unigene_quantification_summary.tsv`

Sample-level quantification summary for quality control.
EOF_README

# ==============================================================================
# Validate outputs
# ==============================================================================

for output_file in \
  "${OUT_DIR}/unigene_mapped_read_segments.tsv" \
  "${OUT_DIR}/unigene_rpk.tsv" \
  "${OUT_DIR}/unigene_tpm.tsv" \
  "${OUT_DIR}/unigene_relative_abundance.tsv" \
  "${OUT_DIR}/unigene_quantification_summary.tsv" \
  "${OUT_DIR}/README.md"
do
  if [ ! -s "${output_file}" ]; then
    echo "[ERROR] Expected U05 output missing or empty:"
    echo "        ${output_file}"
    exit 1
  fi
done

echo
echo "[INFO] U05 output files:"

find "${OUT_DIR}" \
  -maxdepth 1 \
  -type f \
  -printf "%f\n" \
  | sort
EOF

chmod +x scripts/assembly_based/run_U05_quantify_unigenes.sh
```

#### U06. Unigene taxonomy by Kraken2 PlusPF
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/assembly_based/run_U06_unigene_taxonomy_kraken2.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# U06. Taxonomic classification of unigene catalog using Kraken2 PlusPF
#
# Required conda environment:
#   conda activate metagenomics-taxonomy
#
# Input:
#   results/assembly_based/U03_unigene_catalog/unigene_catalog.fna
#
# Output:
#   results/assembly_based/U06_unigene_taxonomy_kraken2/
#   ├── unigene.kraken2.output.tsv
#   ├── unigene.kraken2.report.tsv
#   └── unigene_taxid.tsv
#
# Notes:
#   - Kraken2 is used here to classify assembled unigene nucleotide sequences.
#   - Bracken is NOT used here, because Bracken is for abundance re-estimation
#     from read-level Kraken2 reports.
# ==============================================================================

KRAKEN2_DB="/home/adprc/databases/metagenomics/kraken2/pluspf_20260226"
THREADS=12

UNIGENE_FASTA="results/assembly_based/U03_unigene_catalog/unigene_catalog.fna"
OUT_DIR="results/assembly_based/U06_unigene_taxonomy_kraken2"

mkdir -p "${OUT_DIR}"

OUTPUT="${OUT_DIR}/unigene.kraken2.output.tsv"
REPORT="${OUT_DIR}/unigene.kraken2.report.tsv"
TAXID_TABLE="${OUT_DIR}/unigene_taxid.tsv"
LOG="${OUT_DIR}/unigene.kraken2.log"

echo "============================================================"
echo "[INFO] U06. Classify unigene catalog using Kraken2 PlusPF"
echo "============================================================"

command -v kraken2 >/dev/null 2>&1 || {
  echo "[ERROR] kraken2 command not found"
  echo "[ERROR] Please run: conda activate metagenomics-taxonomy"
  exit 1
}

if [ ! -d "${KRAKEN2_DB}" ]; then
  echo "[ERROR] Kraken2 database not found:"
  echo "        ${KRAKEN2_DB}"
  exit 1
fi

if [ ! -s "${UNIGENE_FASTA}" ]; then
  echo "[ERROR] Unigene FASTA missing or empty:"
  echo "        ${UNIGENE_FASTA}"
  exit 1
fi

kraken2 \
  --db "${KRAKEN2_DB}" \
  --threads "${THREADS}" \
  --report "${REPORT}" \
  --output "${OUTPUT}" \
  "${UNIGENE_FASTA}" \
  2>&1 | tee "${LOG}"

if [ ! -s "${OUTPUT}" ]; then
  echo "[ERROR] Kraken2 unigene output missing or empty:"
  echo "        ${OUTPUT}"
  exit 1
fi

if [ ! -s "${REPORT}" ]; then
  echo "[ERROR] Kraken2 unigene report missing or empty:"
  echo "        ${REPORT}"
  exit 1
fi

# Kraken2 output columns:
#   1 = C/U
#   2 = sequence ID
#   3 = taxid
#   4 = sequence length
#   5 = LCA mapping information
awk -F '\t' '
BEGIN {
  OFS = "\t"
  print "unigene_id", "kraken2_status", "taxid", "sequence_length"
}
{
  print $2, $1, $3, $4
}
' "${OUTPUT}" > "${TAXID_TABLE}"

if [ ! -s "${TAXID_TABLE}" ]; then
  echo "[ERROR] unigene taxid table missing or empty:"
  echo "        ${TAXID_TABLE}"
  exit 1
fi

echo
echo "[INFO] U06 completed"
echo "[INFO] Output directory: ${OUT_DIR}"
echo
echo "[INFO] Files:"
find "${OUT_DIR}" -maxdepth 1 -type f -printf "%f\n" | sort
EOF

chmod +x scripts/assembly_based/run_U06_unigene_taxonomy_kraken2.sh

#### U07
```bash
```

#### U06b. Build taxonomy × unigene × sample abundance table
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/assembly_based/run_U06b_build_taxonomy_gene_abundance_table.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# U06b. Build taxonomy × unigene × sample abundance tables
#
# Required conda environment:
#   conda activate metagenomics-taxonomy
#
# Input:
#   results/assembly_based/U06_unigene_taxonomy_kraken2/unigene_taxid.tsv
#   results/assembly_based/U05_unigene_abundance/unigene_mapped_read_segments.tsv
#   results/assembly_based/U05_unigene_abundance/unigene_relative_abundance.tsv
#   results/assembly_based/U05_unigene_abundance/unigene_tpm.tsv
#
# Output:
#   results/assembly_based/U06b_taxonomy_gene_abundance/
#   ├── unigene_taxonomy_lineage.tsv
#   ├── all_level_species_gene_mapped_read_segments.tsv
#   ├── all_level_species_gene_relative_abundance.tsv
#   └── all_level_species_gene_tpm.tsv
#
# Notes:
#   - This step generates a BGI-like taxonomy × unigene × sample table.
#   - This step is NOT KEGG annotation.
#   - U07 is reserved for functional annotation, such as KEGG / eggNOG / COG / GO.
#   - NORMALIZE_KINGDOM=true converts NCBI kingdom-like labels into broader
#     BGI-like labels: Bacteria, Archaea, Viruses, Eukaryota, unclassified.
# ==============================================================================

KRAKEN2_DB="/home/adprc/databases/metagenomics/kraken2/pluspf_20260226"

UNIGENE_TAXID="results/assembly_based/U06_unigene_taxonomy_kraken2/unigene_taxid.tsv"

MAPPED_SEGMENTS="results/assembly_based/U05_unigene_abundance/unigene_mapped_read_segments.tsv"
RELATIVE_ABUNDANCE="results/assembly_based/U05_unigene_abundance/unigene_relative_abundance.tsv"
TPM_TABLE="results/assembly_based/U05_unigene_abundance/unigene_tpm.tsv"

OUT_DIR="results/assembly_based/U06b_taxonomy_gene_abundance"

# true  = BGI-like kingdom labels: k__Bacteria, k__Viruses, k__Archaea, k__Eukaryota
# false = use the original NCBI rank-derived kingdom label
# Default: BGI-like kingdom normalization enabled.
NORMALIZE_KINGDOM="${NORMALIZE_KINGDOM:-true}"

mkdir -p "${OUT_DIR}"

echo "============================================================"
echo "[INFO] U06b. Build taxonomy × unigene × sample abundance tables"
echo "============================================================"
echo "[INFO] NORMALIZE_KINGDOM=${NORMALIZE_KINGDOM}"

command -v python >/dev/null 2>&1 || {
  echo "[ERROR] python command not found"
  exit 1
}

python - <<'PY'
try:
    import pandas  # noqa: F401
except ImportError as exc:
    raise SystemExit(
        "[ERROR] Python package not found: pandas\n"
        "[ERROR] Please install pandas in the current conda environment."
    ) from exc
PY

for input_file in \
  "${UNIGENE_TAXID}" \
  "${MAPPED_SEGMENTS}" \
  "${RELATIVE_ABUNDANCE}" \
  "${TPM_TABLE}"
do
  if [ ! -s "${input_file}" ]; then
    echo "[ERROR] Required input missing or empty:"
    echo "        ${input_file}"
    exit 1
  fi
done

export NORMALIZE_KINGDOM

python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path
import pandas as pd


# =============================================================================
# Configuration
# =============================================================================

KRAKEN2_DB = Path(
    "/home/adprc/databases/metagenomics/kraken2/pluspf_20260226"
)

UNIGENE_TAXID_PATH = Path(
    "results/assembly_based/U06_unigene_taxonomy_kraken2/unigene_taxid.tsv"
)

MAPPED_SEGMENTS_PATH = Path(
    "results/assembly_based/U05_unigene_abundance/unigene_mapped_read_segments.tsv"
)

RELATIVE_ABUNDANCE_PATH = Path(
    "results/assembly_based/U05_unigene_abundance/unigene_relative_abundance.tsv"
)

TPM_PATH = Path(
    "results/assembly_based/U05_unigene_abundance/unigene_tpm.tsv"
)

OUT_DIR = Path(
    "results/assembly_based/U06b_taxonomy_gene_abundance"
)

LINEAGE_OUT = OUT_DIR / "unigene_taxonomy_lineage.tsv"

MAPPED_OUT = OUT_DIR / "all_level_species_gene_mapped_read_segments.tsv"
RELATIVE_OUT = OUT_DIR / "all_level_species_gene_relative_abundance.tsv"
TPM_OUT = OUT_DIR / "all_level_species_gene_tpm.tsv"

NORMALIZE_KINGDOM = (
    os.environ.get("NORMALIZE_KINGDOM", "true").strip().lower()
    in {"1", "true", "yes", "y"}
)


# =============================================================================
# Locate nodes.dmp and names.dmp
# =============================================================================

candidate_nodes = [
    KRAKEN2_DB / "nodes.dmp",
    KRAKEN2_DB / "taxonomy" / "nodes.dmp",
]

candidate_names = [
    KRAKEN2_DB / "names.dmp",
    KRAKEN2_DB / "taxonomy" / "names.dmp",
]

NODES_DMP_PATH = next(
    (
        path
        for path in candidate_nodes
        if path.is_file() and path.stat().st_size > 0
    ),
    None,
)

NAMES_DMP_PATH = next(
    (
        path
        for path in candidate_names
        if path.is_file() and path.stat().st_size > 0
    ),
    None,
)

if NODES_DMP_PATH is None:
    raise FileNotFoundError(
        "nodes.dmp not found. Checked:\n"
        + "\n".join(str(path) for path in candidate_nodes)
    )

if NAMES_DMP_PATH is None:
    raise FileNotFoundError(
        "names.dmp not found. Checked:\n"
        + "\n".join(str(path) for path in candidate_names)
    )


# =============================================================================
# Taxonomy utilities
# =============================================================================

OUTPUT_RANKS = [
    "kingdom",
    "phylum",
    "class",
    "order",
    "family",
    "genus",
    "species",
]

PREFIX_BY_OUTPUT_RANK = {
    "kingdom": "k",
    "phylum": "p",
    "class": "c",
    "order": "o",
    "family": "f",
    "genus": "g",
    "species": "s",
}


def clean_taxon_name(name: str) -> str:
    name = str(name).strip()
    name = name.replace(" ", "_")
    name = name.replace("\t", "_")
    name = name.replace(";", "_")
    return name


def parse_dmp_line(line: str) -> list[str]:
    return [
        field.strip()
        for field in line.rstrip("\n").split("|")
    ]


# =============================================================================
# Load NCBI taxonomy names
# =============================================================================

taxid_to_name: dict[int, str] = {}

with NAMES_DMP_PATH.open("r", encoding="utf-8", errors="replace") as handle:
    for line in handle:
        fields = parse_dmp_line(line)

        if len(fields) < 4:
            continue

        taxid_text = fields[0]
        name_txt = fields[1]
        name_class = fields[3]

        if name_class != "scientific name":
            continue

        taxid = int(taxid_text)
        taxid_to_name[taxid] = clean_taxon_name(name_txt)


# =============================================================================
# Load NCBI taxonomy nodes
# =============================================================================

taxid_to_parent: dict[int, int] = {}
taxid_to_rank: dict[int, str] = {}

with NODES_DMP_PATH.open("r", encoding="utf-8", errors="replace") as handle:
    for line in handle:
        fields = parse_dmp_line(line)

        if len(fields) < 3:
            continue

        taxid = int(fields[0])
        parent_taxid = int(fields[1])
        rank = fields[2]

        taxid_to_parent[taxid] = parent_taxid
        taxid_to_rank[taxid] = rank


def build_rank_lineage(taxid: int) -> dict[str, str]:
    lineage = {
        rank: ""
        for rank in OUTPUT_RANKS
    }

    if taxid == 0:
        lineage["kingdom"] = "_unclassified"
        return lineage

    if taxid not in taxid_to_parent:
        lineage["kingdom"] = "_unclassified"
        return lineage

    observed: dict[str, str] = {}

    current = taxid
    visited: set[int] = set()

    while True:
        if current in visited:
            break

        visited.add(current)

        rank = taxid_to_rank.get(current, "")
        name = taxid_to_name.get(current, "")

        if rank in {
            "superkingdom",
            "kingdom",
            "phylum",
            "class",
            "order",
            "family",
            "genus",
            "species",
        }:
            output_rank = "kingdom" if rank in {"superkingdom", "kingdom"} else rank

            if output_rank not in observed and name:
                observed[output_rank] = name

        parent = taxid_to_parent.get(current)

        if parent is None or parent == current:
            break

        current = parent

    for rank in OUTPUT_RANKS:
        lineage[rank] = observed.get(rank, "")

    if lineage["kingdom"] == "":
        lineage["kingdom"] = "_unclassified"

    return lineage


def normalize_kingdom_label(row: pd.Series) -> str:
    """
    Convert NCBI rank-derived kingdom labels into broad BGI-like labels.

    This is a formatting normalization step, not a claim about BGI's internal
    proprietary implementation.
    """

    kingdom = str(row.get("kingdom", ""))
    phylum = str(row.get("phylum", ""))
    taxid = int(row.get("taxid", 0))

    if taxid == 0 or kingdom == "_unclassified":
        return "_unclassified"

    # Bacterial kingdom-like labels observed in current NCBI taxonomy.
    bacteria_like = {
        "Bacillati",
        "Pseudomonadati",
        "Fusobacteriati",
        "Thermotogati",
    }

    # Archaeal kingdom-like labels observed in current NCBI taxonomy.
    archaea_like = {
        "Methanobacteriati",
        "Thermoproteati",
        "Promethearchaeati",
    }

    # Viral realm / high-level labels observed from Kraken2 PlusPF taxonomy.
    virus_like = {
        "Heunggongvirae",
        "Bamfordvirae",
        "Orthornavirae",
        "Shotokuvirae",
    }

    # Eukaryotic high-level labels.
    eukaryota_like = {
        "Fungi",
        "Metazoa",
        "Viridiplantae",
    }

    if kingdom in bacteria_like:
        return "Bacteria"

    if kingdom in archaea_like:
        return "Archaea"

    if kingdom in virus_like:
        return "Viruses"

    if kingdom in eukaryota_like:
        return "Eukaryota"

    # Fallback rules based on phylum names.
    if phylum in {
        "Bacillota",
        "Bacteroidota",
        "Pseudomonadota",
        "Actinomycetota",
        "Fusobacteriota",
        "Thermodesulfobacteriota",
        "Thermotogota",
    }:
        return "Bacteria"

    if phylum in {
        "Euryarchaeota",
        "Thermoproteota",
        "Promethearchaeota",
    }:
        return "Archaea"

    # Keep original label when no normalization rule matched.
    return kingdom


def format_taxonomy(row: pd.Series) -> str:
    parts: list[str] = []

    for rank in OUTPUT_RANKS:
        prefix = PREFIX_BY_OUTPUT_RANK[rank]
        value = str(row[rank])

        if rank == "kingdom" and value == "_unclassified":
            return "k___unclassified"

        parts.append(f"{prefix}__{value}")

    return ";".join(parts)


# =============================================================================
# Build unigene lineage table
# =============================================================================

taxid_df = pd.read_csv(
    UNIGENE_TAXID_PATH,
    sep="\t",
    dtype={
        "unigene_id": str,
        "kraken2_status": str,
        "taxid": int,
        "sequence_length": int,
    },
)

required_taxid_cols = {
    "unigene_id",
    "kraken2_status",
    "taxid",
    "sequence_length",
}

missing_taxid_cols = required_taxid_cols.difference(
    taxid_df.columns
)

if missing_taxid_cols:
    raise ValueError(
        f"{UNIGENE_TAXID_PATH} is missing required columns: "
        f"{sorted(missing_taxid_cols)}"
    )

if taxid_df["unigene_id"].duplicated().any():
    duplicated = (
        taxid_df.loc[
            taxid_df["unigene_id"].duplicated(),
            "unigene_id",
        ]
        .head()
        .tolist()
    )

    raise ValueError(
        f"Duplicated unigene IDs found in taxid table: {duplicated}"
    )

lineage_records: list[dict[str, str]] = []

for taxid in taxid_df["taxid"].tolist():
    lineage_records.append(
        build_rank_lineage(int(taxid))
    )

lineage_df = pd.DataFrame(lineage_records)

lineage_full_df = pd.concat(
    [
        taxid_df.reset_index(drop=True),
        lineage_df,
    ],
    axis=1,
)

lineage_full_df["original_kingdom"] = lineage_full_df["kingdom"]

if NORMALIZE_KINGDOM:
    lineage_full_df["kingdom"] = lineage_full_df.apply(
        normalize_kingdom_label,
        axis=1,
    )

lineage_full_df["taxonomy"] = lineage_full_df.apply(
    format_taxonomy,
    axis=1,
)

lineage_full_df.to_csv(
    LINEAGE_OUT,
    sep="\t",
    index=False,
)


# =============================================================================
# Merge taxonomy with abundance matrices
# =============================================================================

def build_taxonomy_gene_abundance(
    abundance_path: Path,
    output_path: Path,
) -> pd.DataFrame:
    abundance_df = pd.read_csv(
        abundance_path,
        sep="\t",
        dtype={
            "unigene_id": str,
        },
    )

    if "unigene_id" not in abundance_df.columns:
        raise ValueError(
            f"{abundance_path} must contain column: unigene_id"
        )

    if abundance_df["unigene_id"].duplicated().any():
        duplicated = (
            abundance_df.loc[
                abundance_df["unigene_id"].duplicated(),
                "unigene_id",
            ]
            .head()
            .tolist()
        )

        raise ValueError(
            f"Duplicated unigene IDs found in {abundance_path}: {duplicated}"
        )

    merged_df = lineage_full_df[
        [
            "unigene_id",
            "taxonomy",
        ]
    ].merge(
        abundance_df,
        on="unigene_id",
        how="inner",
        validate="one_to_one",
    )

    if merged_df.shape[0] != lineage_full_df.shape[0]:
        raise ValueError(
            f"Merge row count mismatch for {abundance_path}: "
            f"{merged_df.shape[0]} vs {lineage_full_df.shape[0]}"
        )

    merged_df = merged_df.rename(
        columns={
            "unigene_id": "gene",
        }
    )

    sample_columns = [
        col
        for col in merged_df.columns
        if col not in {
            "taxonomy",
            "gene",
        }
    ]

    merged_df = merged_df[
        [
            "taxonomy",
            "gene",
            *sample_columns,
        ]
    ]

    merged_df.to_csv(
        output_path,
        sep="\t",
        index=False,
    )

    return merged_df


mapped_df = build_taxonomy_gene_abundance(
    MAPPED_SEGMENTS_PATH,
    MAPPED_OUT,
)

relative_df = build_taxonomy_gene_abundance(
    RELATIVE_ABUNDANCE_PATH,
    RELATIVE_OUT,
)

tpm_df = build_taxonomy_gene_abundance(
    TPM_PATH,
    TPM_OUT,
)


# =============================================================================
# Summary
# =============================================================================

status_counts = (
    taxid_df["kraken2_status"]
    .value_counts()
    .sort_index()
)

original_kingdom_counts = (
    lineage_full_df["original_kingdom"]
    .value_counts()
    .sort_values(ascending=False)
)

kingdom_counts = (
    lineage_full_df["kingdom"]
    .value_counts()
    .sort_values(ascending=False)
)

print()
print("============================================================")
print("[INFO] U06b completed")
print("============================================================")

print(f"[INFO] NORMALIZE_KINGDOM: {NORMALIZE_KINGDOM}")
print(f"[INFO] nodes.dmp: {NODES_DMP_PATH}")
print(f"[INFO] names.dmp: {NAMES_DMP_PATH}")
print(f"[INFO] Unigenes: {lineage_full_df.shape[0]:,}")

print()
print("[INFO] Kraken2 status counts:")
print(status_counts.to_string())

print()
print("[INFO] Original kingdom counts:")
print(original_kingdom_counts.to_string())

print()
print("[INFO] Output kingdom counts:")
print(kingdom_counts.to_string())

print()
print("[INFO] Output files:")
for path in [
    LINEAGE_OUT,
    MAPPED_OUT,
    RELATIVE_OUT,
    TPM_OUT,
]:
    print(f"  {path}")
PY

for output_file in \
  "${OUT_DIR}/unigene_taxonomy_lineage.tsv" \
  "${OUT_DIR}/all_level_species_gene_mapped_read_segments.tsv" \
  "${OUT_DIR}/all_level_species_gene_relative_abundance.tsv" \
  "${OUT_DIR}/all_level_species_gene_tpm.tsv"
do
  if [ ! -s "${output_file}" ]; then
    echo "[ERROR] Expected output missing or empty:"
    echo "        ${output_file}"
    exit 1
  fi
done

echo
echo "[INFO] U06b output files:"
find "${OUT_DIR}" -maxdepth 1 -type f -printf "%f\n" | sort
EOF

chmod +x scripts/assembly_based/run_U06b_build_taxonomy_gene_abundance_table.sh
```

#### U07. Functional annotation using eggNOG-mapper
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/assembly_based/run_U07_functional_annotation_eggnog.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# U07. Functional annotation of unigene catalog using eggNOG-mapper
#
# Required conda environment:
#   conda activate metagenomics-eggnog
#
# Input:
#   results/assembly_based/U03_unigene_catalog/unigene_catalog.faa
#
# Output:
#   results/assembly_based/U07_functional_annotation_eggnog/
#   ├── unigene.emapper.annotations
#   ├── unigene.emapper.seed_orthologs
#   ├── unigene.emapper.hits
#   └── logs/
#
# Notes:
#   - This step performs functional annotation, not taxonomic annotation.
#   - eggNOG-mapper can provide KO, KEGG pathway, COG category, GO terms,
#     EC numbers, eggNOG OGs, and functional descriptions.
#   - U08 will parse this annotation and merge functional terms with U05
#     unigene abundance tables.
# ==============================================================================

THREADS=12

INPUT_FASTA="results/assembly_based/U03_unigene_catalog/unigene_catalog.faa"

EGGNOG_DATA_DIR="/home/adprc/databases/metagenomics/eggnog_mapper/data"

OUT_DIR="results/assembly_based/U07_functional_annotation_eggnog"
OUT_PREFIX="unigene"

mkdir -p "${OUT_DIR}/logs"

LOG="${OUT_DIR}/logs/${OUT_PREFIX}.emapper.log"

echo "============================================================"
echo "[INFO] U07. Functional annotation using eggNOG-mapper"
echo "============================================================"
echo "[INFO] Input FASTA: ${INPUT_FASTA}"
echo "[INFO] eggNOG data dir: ${EGGNOG_DATA_DIR}"
echo "[INFO] Output dir: ${OUT_DIR}"
echo "[INFO] Threads: ${THREADS}"

command -v emapper.py >/dev/null 2>&1 || {
  echo "[ERROR] emapper.py command not found"
  echo "[ERROR] Please run: conda activate metagenomics-eggnog"
  exit 1
}

command -v diamond >/dev/null 2>&1 || {
  echo "[ERROR] diamond command not found"
  echo "[ERROR] Please run: conda activate metagenomics-eggnog"
  exit 1
}

if [ ! -s "${INPUT_FASTA}" ]; then
  echo "[ERROR] Input protein FASTA missing or empty:"
  echo "        ${INPUT_FASTA}"
  exit 1
fi

for db_file in \
  "${EGGNOG_DATA_DIR}/eggnog.db" \
  "${EGGNOG_DATA_DIR}/eggnog.taxa.db" \
  "${EGGNOG_DATA_DIR}/eggnog_proteins.dmnd"
do
  if [ ! -s "${db_file}" ]; then
    echo "[ERROR] Required eggNOG database file missing or empty:"
    echo "        ${db_file}"
    exit 1
  fi
done

emapper.py \
  -i "${INPUT_FASTA}" \
  --itype proteins \
  --data_dir "${EGGNOG_DATA_DIR}" \
  --cpu "${THREADS}" \
  -m diamond \
  --sensmode more-sensitive \
  --override \
  --output "${OUT_PREFIX}" \
  --output_dir "${OUT_DIR}" \
  2>&1 | tee "${LOG}"

ANNOTATION_FILE="${OUT_DIR}/${OUT_PREFIX}.emapper.annotations"

if [ ! -s "${ANNOTATION_FILE}" ]; then
  echo "[ERROR] eggNOG-mapper annotation file missing or empty:"
  echo "        ${ANNOTATION_FILE}"
  exit 1
fi

echo
echo "============================================================"
echo "[INFO] U07 eggNOG functional annotation completed"
echo "============================================================"

echo "[INFO] Output files:"
find "${OUT_DIR}" -maxdepth 2 -type f -printf "%p\n" | sort
EOF

chmod +x scripts/assembly_based/run_U07_functional_annotation_eggnog.sh
```

#### U08. Build KEGG gene abundance tables from eggNOG-mapper annotation
```bash
cd ~/workspaces/Bing/bgi/WMS_project

cat > scripts/assembly_based/run_U08_build_kegg_abundance_tables.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# U08. Build KEGG gene abundance tables from eggNOG-mapper annotation
#
# Required conda environment:
#   conda activate metagenomics-assembly
#
# Input:
#   results/assembly_based/U07_functional_annotation_eggnog/unigene.emapper.annotations
#   results/assembly_based/U05_unigene_abundance/unigene_mapped_read_segments.tsv
#   results/assembly_based/U05_unigene_abundance/unigene_relative_abundance.tsv
#   results/assembly_based/U05_unigene_abundance/unigene_tpm.tsv
#
# Output:
#   results/assembly_based/U08_kegg_abundance/
#   ├── gene_kegg_annotation.tsv
#   ├── all_relab_gene_kegg_unstratified.tsv
#   ├── all_tpm_gene_kegg_unstratified.tsv
#   ├── all_mapped_segments_gene_kegg_unstratified.tsv
#   └── kegg_abundance_summary.tsv
#
# Notes:
#   - This step parses KEGG-related columns from eggNOG-mapper output.
#   - The main BGI-like output is all_relab_gene_kegg_unstratified.tsv.
#   - "unstratified" here means gene-level KEGG annotation merged with abundance,
#     not taxon-stratified functional profiling.
# ==============================================================================

ANNOTATION_FILE="results/assembly_based/U07_functional_annotation_eggnog/unigene.emapper.annotations"

MAPPED_SEGMENTS="results/assembly_based/U05_unigene_abundance/unigene_mapped_read_segments.tsv"
RELATIVE_ABUNDANCE="results/assembly_based/U05_unigene_abundance/unigene_relative_abundance.tsv"
TPM_TABLE="results/assembly_based/U05_unigene_abundance/unigene_tpm.tsv"

OUT_DIR="results/assembly_based/U08_kegg_abundance"

mkdir -p "${OUT_DIR}"

echo "============================================================"
echo "[INFO] U08. Build KEGG gene abundance tables"
echo "============================================================"

command -v python >/dev/null 2>&1 || {
  echo "[ERROR] python command not found"
  exit 1
}

python - <<'PY'
try:
    import pandas  # noqa: F401
except ImportError as exc:
    raise SystemExit(
        "[ERROR] Python package not found: pandas\n"
        "[ERROR] Please install pandas in the current conda environment."
    ) from exc
PY

for input_file in \
  "${ANNOTATION_FILE}" \
  "${MAPPED_SEGMENTS}" \
  "${RELATIVE_ABUNDANCE}" \
  "${TPM_TABLE}"
do
  if [ ! -s "${input_file}" ]; then
    echo "[ERROR] Required input missing or empty:"
    echo "        ${input_file}"
    exit 1
  fi
done

python - <<'PY'
from __future__ import annotations

from pathlib import Path
import pandas as pd


# =============================================================================
# Configuration
# =============================================================================

ANNOTATION_PATH = Path(
    "results/assembly_based/U07_functional_annotation_eggnog/unigene.emapper.annotations"
)

MAPPED_SEGMENTS_PATH = Path(
    "results/assembly_based/U05_unigene_abundance/unigene_mapped_read_segments.tsv"
)

RELATIVE_ABUNDANCE_PATH = Path(
    "results/assembly_based/U05_unigene_abundance/unigene_relative_abundance.tsv"
)

TPM_PATH = Path(
    "results/assembly_based/U05_unigene_abundance/unigene_tpm.tsv"
)

OUT_DIR = Path(
    "results/assembly_based/U08_kegg_abundance"
)

GENE_KEGG_ANNOTATION_OUT = OUT_DIR / "gene_kegg_annotation.tsv"

RELATIVE_OUT = OUT_DIR / "all_relab_gene_kegg_unstratified.tsv"
TPM_OUT = OUT_DIR / "all_tpm_gene_kegg_unstratified.tsv"
MAPPED_OUT = OUT_DIR / "all_mapped_segments_gene_kegg_unstratified.tsv"

SUMMARY_OUT = OUT_DIR / "kegg_abundance_summary.tsv"


# =============================================================================
# Read eggNOG-mapper annotation
# =============================================================================

def read_emapper_annotations(path: Path) -> pd.DataFrame:
    header_line = None
    data_start_line = None

    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line_number, line in enumerate(handle):
            stripped = line.rstrip("\n")

            if stripped.startswith("#query"):
                header_line = stripped.lstrip("#").split("\t")
                data_start_line = line_number + 1
                break

    if header_line is None or data_start_line is None:
        raise ValueError(
            f"Cannot find '#query' header line in {path}"
        )

    df = pd.read_csv(
        path,
        sep="\t",
        comment="#",
        names=header_line,
        header=None,
        skiprows=data_start_line,
        dtype=str,
    )

    if "query" not in df.columns:
        raise ValueError(
            f"{path} does not contain required column: query"
        )

    return df


annotation_df = read_emapper_annotations(
    ANNOTATION_PATH
)

annotation_df = annotation_df.rename(
    columns={
        "query": "gene",
    }
)

annotation_df["gene"] = annotation_df["gene"].astype(str)

if annotation_df["gene"].duplicated().any():
    duplicated = (
        annotation_df.loc[
            annotation_df["gene"].duplicated(),
            "gene",
        ]
        .head()
        .tolist()
    )

    raise ValueError(
        f"Duplicated gene IDs found in eggNOG annotation: {duplicated}"
    )


# =============================================================================
# Identify KEGG-related columns
# =============================================================================

candidate_columns = {
    "KEGG_ko": [
        "KEGG_ko",
        "KEGG KO",
        "kegg_ko",
    ],
    "KEGG_Pathway": [
        "KEGG_Pathway",
        "KEGG Pathway",
        "kegg_pathway",
    ],
    "KEGG_Module": [
        "KEGG_Module",
        "KEGG Module",
        "kegg_module",
    ],
    "KEGG_Reaction": [
        "KEGG_Reaction",
        "KEGG Reaction",
        "kegg_reaction",
    ],
    "KEGG_rclass": [
        "KEGG_rclass",
        "KEGG rclass",
        "kegg_rclass",
    ],
    "BRITE": [
        "BRITE",
        "brite",
    ],
    "KEGG_TC": [
        "KEGG_TC",
        "KEGG TC",
        "kegg_tc",
    ],
    "CAZy": [
        "CAZy",
        "cazy",
    ],
    "BiGG_Reaction": [
        "BiGG_Reaction",
        "BiGG Reaction",
        "bigg_reaction",
    ],
    "EC": [
        "EC",
        "EC_number",
        "EC number",
    ],
    "COG_category": [
        "COG_category",
        "COG category",
        "cog_category",
    ],
    "Description": [
        "Description",
        "description",
    ],
    "Preferred_name": [
        "Preferred_name",
        "Preferred name",
        "preferred_name",
    ],
}

resolved_columns: dict[str, str | None] = {}

for output_col, candidates in candidate_columns.items():
    resolved_columns[output_col] = next(
        (
            col
            for col in candidates
            if col in annotation_df.columns
        ),
        None,
    )


def get_annotation_column(output_col: str) -> pd.Series:
    source_col = resolved_columns[output_col]

    if source_col is None:
        return pd.Series(
            ["-"] * annotation_df.shape[0],
            index=annotation_df.index,
        )

    return (
        annotation_df[source_col]
        .fillna("-")
        .replace("", "-")
    )


gene_kegg_df = pd.DataFrame(
    {
        "gene": annotation_df["gene"],
        "KEGG_ko": get_annotation_column("KEGG_ko"),
        "KEGG_Pathway": get_annotation_column("KEGG_Pathway"),
        "KEGG_Module": get_annotation_column("KEGG_Module"),
        "KEGG_Reaction": get_annotation_column("KEGG_Reaction"),
        "KEGG_rclass": get_annotation_column("KEGG_rclass"),
        "BRITE": get_annotation_column("BRITE"),
        "KEGG_TC": get_annotation_column("KEGG_TC"),
        "CAZy": get_annotation_column("CAZy"),
        "BiGG_Reaction": get_annotation_column("BiGG_Reaction"),
        "EC": get_annotation_column("EC"),
        "COG_category": get_annotation_column("COG_category"),
        "Preferred_name": get_annotation_column("Preferred_name"),
        "Description": get_annotation_column("Description"),
    }
)

# Keep genes with at least one KEGG-related annotation.
kegg_related_cols = [
    "KEGG_ko",
    "KEGG_Pathway",
    "KEGG_Module",
    "KEGG_Reaction",
    "KEGG_rclass",
    "BRITE",
    "KEGG_TC",
    "EC",
]

has_kegg_annotation = (
    gene_kegg_df[kegg_related_cols]
    .ne("-")
    .any(axis=1)
)

gene_kegg_df = gene_kegg_df.loc[
    has_kegg_annotation
].copy()

gene_kegg_df.to_csv(
    GENE_KEGG_ANNOTATION_OUT,
    sep="\t",
    index=False,
)


# =============================================================================
# Merge KEGG annotation with abundance matrices
# =============================================================================

def build_gene_kegg_abundance(
    abundance_path: Path,
    output_path: Path,
) -> pd.DataFrame:
    abundance_df = pd.read_csv(
        abundance_path,
        sep="\t",
        dtype={
            "unigene_id": str,
        },
    )

    if "unigene_id" not in abundance_df.columns:
        raise ValueError(
            f"{abundance_path} must contain column: unigene_id"
        )

    if abundance_df["unigene_id"].duplicated().any():
        duplicated = (
            abundance_df.loc[
                abundance_df["unigene_id"].duplicated(),
                "unigene_id",
            ]
            .head()
            .tolist()
        )

        raise ValueError(
            f"Duplicated unigene IDs found in {abundance_path}: {duplicated}"
        )

    abundance_df = abundance_df.rename(
        columns={
            "unigene_id": "gene",
        }
    )

    merged_df = gene_kegg_df.merge(
        abundance_df,
        on="gene",
        how="inner",
        validate="one_to_one",
    )

    sample_columns = [
        col
        for col in merged_df.columns
        if col not in {
            "gene",
            "KEGG_ko",
            "KEGG_Pathway",
            "KEGG_Module",
            "KEGG_Reaction",
            "KEGG_rclass",
            "BRITE",
            "KEGG_TC",
            "CAZy",
            "BiGG_Reaction",
            "EC",
            "COG_category",
            "Preferred_name",
            "Description",
        }
    ]

    merged_df = merged_df[
        [
            "gene",
            "KEGG_ko",
            "KEGG_Pathway",
            "KEGG_Module",
            "KEGG_Reaction",
            "KEGG_rclass",
            "BRITE",
            "KEGG_TC",
            "CAZy",
            "BiGG_Reaction",
            "EC",
            "COG_category",
            "Preferred_name",
            "Description",
            *sample_columns,
        ]
    ]

    merged_df.to_csv(
        output_path,
        sep="\t",
        index=False,
    )

    return merged_df


relative_df = build_gene_kegg_abundance(
    RELATIVE_ABUNDANCE_PATH,
    RELATIVE_OUT,
)

tpm_df = build_gene_kegg_abundance(
    TPM_PATH,
    TPM_OUT,
)

mapped_df = build_gene_kegg_abundance(
    MAPPED_SEGMENTS_PATH,
    MAPPED_OUT,
)


# =============================================================================
# Summary
# =============================================================================

summary_rows = [
    {
        "metric": "total_emapper_annotated_genes",
        "value": int(annotation_df.shape[0]),
    },
    {
        "metric": "genes_with_kegg_related_annotation",
        "value": int(gene_kegg_df.shape[0]),
    },
    {
        "metric": "relative_abundance_output_rows",
        "value": int(relative_df.shape[0]),
    },
    {
        "metric": "tpm_output_rows",
        "value": int(tpm_df.shape[0]),
    },
    {
        "metric": "mapped_segments_output_rows",
        "value": int(mapped_df.shape[0]),
    },
]

summary_df = pd.DataFrame(
    summary_rows
)

summary_df.to_csv(
    SUMMARY_OUT,
    sep="\t",
    index=False,
)

print()
print("============================================================")
print("[INFO] U08 completed")
print("============================================================")

print()
print("[INFO] Resolved eggNOG columns:")
for output_col, source_col in resolved_columns.items():
    print(f"{output_col}: {source_col}")

print()
print("[INFO] Summary:")
print(summary_df.to_string(index=False))

print()
print("[INFO] Output files:")
for path in [
    GENE_KEGG_ANNOTATION_OUT,
    RELATIVE_OUT,
    TPM_OUT,
    MAPPED_OUT,
    SUMMARY_OUT,
]:
    print(f"  {path}")
PY

for output_file in \
  "${OUT_DIR}/gene_kegg_annotation.tsv" \
  "${OUT_DIR}/all_relab_gene_kegg_unstratified.tsv" \
  "${OUT_DIR}/all_tpm_gene_kegg_unstratified.tsv" \
  "${OUT_DIR}/all_mapped_segments_gene_kegg_unstratified.tsv" \
  "${OUT_DIR}/kegg_abundance_summary.tsv"
do
  if [ ! -s "${output_file}" ]; then
    echo "[ERROR] Expected output missing or empty:"
    echo "        ${output_file}"
    exit 1
  fi
done

echo
echo "[INFO] U08 output files:"
find "${OUT_DIR}" -maxdepth 1 -type f -printf "%f\n" | sort
EOF

chmod +x scripts/assembly_based/run_U08_build_kegg_abundance_tables.sh
```


### 原始資料確認
```bash
conda activate host-tools
```
品質處理：
1. 檢查 read 品質
2. 偵測與去除 adapter
3. 移除低品質 reads
4. 修剪低品質尾端
5. 過濾太短的 reads
6. 處理 polyG / polyX tail
7. 產生 HTML / JSON QC 報告

```bash
bash scripts/run_01_fastp.sh
```

統計clean reads數量確認：
```bash
cat results/01_fastp/seqkit_clean_stats.tsv
```

主要檢查：
1. clean read pairs 保留比例
2. 是否有 adapter trimming
3. Q30 是否維持很高
4. R1/R2 clean reads 是否仍然一致


### Dehost
```bash
bash scripts/run_02_dehost_human.sh
```

```
grep "overall alignment rate" results/02_dehost/logs/*.bowtie2.log
```

``` bash
cat results/02_dehost/seqkit_dehost_stats.tsv
cat results/02_dehost/logs/YZA.bowtie2.log
cat results/02_dehost/logs/YZB.bowtie2.log
du -sh results/02_dehost
```


### Taxonomic profiling
啟動 metagenomics-taxonomy conda 環境：
* [MetaPhlAn version 4.2.4 (21 Oct 2025)](https://github.com/biobakery/metaphlan)   
```
Blanco-Míguez A, Beghini F, Cumbo F, McIver LJ, Thompson KN, Zolfo M, Manghi P, Dubois L, Huang KD, Thomas AM, Nickols WA, Piccinno G, Piperni E, Punčochář M, Valles-Colomer M, Tett A, Giordano F, Davies R, Wolf J, Berry SE, Spector TD, Franzosa EA, Pasolli E, Asnicar F, Huttenhower C, Segata N. Extending and improving metagenomic taxonomic profiling with uncharacterized species using MetaPhlAn 4. Nat Biotechnol. 2023 Nov;41(11):1633-1644. doi: 10.1038/s41587-023-01688-w. Epub 2023 Feb 23. PMID: 36823356; PMCID: PMC10635831.
``` 
* [Kraken version 2.17.1](https://github.com/DerrickWood/kraken2)
```
Lu J, Rincon N, Wood DE, Breitwieser FP, Pockrandt C, Langmead B, Salzberg SL, Steinegger M. Metagenome analysis using the Kraken software suite. Nat Protoc. 2022 Dec;17(12):2815-2839. doi: 10.1038/s41596-022-00738-y. Epub 2022 Sep 28. Erratum in: Nat Protoc. 2026 Feb;21(2):872. doi: 10.1038/s41596-024-01064-1. PMID: 36171387; PMCID: PMC9725748.
```
* [Bracken version 3.0.1](https://github.com/jenniferlu717/Bracken)
```
Lu J, Breitwieser FP, Thielen P, Salzberg SL. Bracken: estimating species abundance in metagenomics data. PeerJ Comput Sci. 2017;3:e104. doi: 10.7717/peerj-cs.104. Epub 2017 Jan 2. PMID: 40271438; PMCID: PMC12016282.
```
```bash
conda activate metagenomics-taxonomy
```
        
#### MetaPhlAn
使用新版 MetaPhlAn database mpa_vJan25_CHOCOPhlAnSGB_202503 for taxonomic profiling
```bash
ls -lh /home/adprc/databases/metagenomics/metaphlan
du -sh /home/adprc/databases/metagenomics/metaphlan
tail -n 30 /home/adprc/databases/metagenomics/metaphlan/metaphlan_install.log
```

```bash
bash scripts/run_03_metaphlan.sh
```

#### Kraken2
[Kraken2: PlusPF prebuilt DB](https://benlangmead.github.io/aws-indexes/k2)
* Includes RefSeq complete genomes plus GTDB representative genomes (bacteria, archaea, viruses, fungi, protozoa)

判斷 reads 可能屬於哪個分類節點
```bash
bash scripts/run_04_kraken2.sh
```

#### Bracken
重新分配 reads，估算 species/genus abundance
```bash
bash scripts/run_05_bracken_all_ranks.sh
```

#### Merge tables for samples
```bash
bash scripts/run_06_merge_taxonomy_tables.sh
```
檢查
```
ls -lh results/06_taxonomy_tables/
```

#-----
1. 合併 MetaPhlAn
```
mkdir -p results/06_taxonomy_tables
```
```bash
merge_metaphlan_tables.py \
  results/03_metaphlan/profiles/YZA_profile.txt \
  results/03_metaphlan/profiles/YZB_profile.txt \
  > results/06_taxonomy_tables/metaphlan_all_levels.tsv
```
只取species level
```bash
grep -E '^#|s__' \
  results/06_taxonomy_tables/metaphlan_all_levels.tsv \
  > results/06_taxonomy_tables/metaphlan_species.tsv
```
2. 合併 Bracken species
```bash
combine_bracken_outputs.py \
  --files results/05_bracken/species/*.bracken.S.tsv \
  -o results/06_taxonomy_tables/bracken_species.tsv
```
合併 Bracken genus
```bash
combine_bracken_outputs.py \
  --files results/05_bracken/genus/*.bracken.G.tsv \
  -o results/06_taxonomy_tables/bracken_genus.tsv
```

### Functional profiling
啟動 metagenomics-function conda 環境：
* [HUMAnN version 3.9.0](https://github.com/biobakery/humann)
- ChocoPhlAn：nucleotide database
- UniRef：protein database
* 使用 HUMAnN 可相容的 MetaPhlAn database mpa_vJun23_CHOCOPhlAnSGB_202403

運作順序:
```
MetaPhlAn-compatible profile
↓
ChocoPhlAn nucleotide search
↓
未比對 reads 再進 DIAMOND translated search >> 時間最久
↓
gene families 彙整
↓
reactions 彙整
↓
pathway abundance / coverage reconstruction
```

```bash
conda activate metagenomics-humann
```

``` bash
bash scripts/run_03b_metaphlan_humann_compatible.sh
```

```bash
bash scripts/run_07_humann.sh
```
#### HUMAnN

合併單一樣本的基因家族 / pathway abundance / pathway coverage 表格成 cohort-level 矩陣
```bash
conda activate metagenomics-humann

bash -n scripts/run_08_humann_tables.sh && echo "[OK] shell syntax valid"

bash scripts/run_08_humann_tables.sh
```

檢查結果
```bash
ls -lh results/08_humann_tables/

head -n 5 results/08_humann_tables/humann_genefamilies_cpm.tsv
head -n 5 results/08_humann_tables/humann_pathabundance_relab.tsv
head -n 5 results/08_humann_tables/humann_pathcoverage.tsv
```

確認 07_humann 完整完成，可以刪除 R1、R2 串接出的暫存檔：
```bash
rm -rf tmp/humann_input

du -sh results/07_humann
du -sh results/08_humann_tables
df -h
```

### Assembly-based analysis
reads
  ↓ 拼接
contig
  ↓ gene prediction
┌────────────────────────────────────────────┐
│ gene_1 │ gene_2 │ gene_3 │ gene_4 │ gene_5 │
└────────────────────────────────────────────┘

#### MEGAHIT assembly
[MEGAHIT v1.2.9](https://github.com/voutcn/MEGAHIT)
```
Li D, Liu CM, Luo R, Sadakane K, Lam TW. MEGAHIT: an ultra-fast single-node solution for large and complex metagenomics assembly via succinct de Bruijn graph. Bioinformatics. 2015 May 15;31(10):1674-6. doi: 10.1093/bioinformatics/btv033. Epub 2015 Jan 20. PMID: 25609793; PMCID: PMC4410642.
```
```bash
conda activate metagenomics-assembly
```
```bash
bash scripts/assembly_based/run_U01_megahit_assembly.sh
```

### Gene prediction
```bash
bash scripts/assembly_based/run_U02_predict_genes.sh
```

#### Build non-redundant unigene catalog
```bash
bash scripts/assembly_based/run_U03_build_unigene_catalog.sh
```

### Mapping reads to unigene catalog
```bash
bash scripts/assembly_based/run_U04_map_reads_to_catalog.sh
```

### Quantify unigenes
```bash
bash scripts/assembly_based/run_U05_quantify_unigenes.sh
```

### Build Taxonomy Tables
Using Kraken2 PlusPF to classify unigene catalog sequences and generate taxonomy tables.
```bash
bash scripts/assembly_based/run_U06_unigene_taxonomy_kraken2.sh
```

Build taxonomy × unigene × sample abundance tables by merging Kraken2 taxonomy with unigene abundance matrices.
* Normalize kingdom labels into broad BGI-like labels (Bacteria, Archaea, Viruses, Eukaryota, unclassified) to facilitate downstream analysis and interpretation.
```bash
bash scripts/assembly_based/run_U06b_build_taxonomy_gene_abundance_table.sh
```

### Functional annotation
[eggNOG-mapper 2.1.13](https://github.com/eggnogdb/eggnog-mapper)
* eggNOG DB version: 5.0.2
```
Ana Hernández-Plaza, Ziqi Deng, Fabian Robledo-Yagüe, Damian Szklarczyk, Christian von Mering, Peer Bork, Jaime Huerta-Cepas, eggNOG v7: phylogeny-based orthology predictions and functional annotations, Nucleic Acids Research, Volume 54, Issue D1, 6 January 2026, Pages D402–D408, https://doi.org/10.1093/nar/gkaf1249
```

```bash
conda activate metagenomics-eggnog
bash scripts/assembly_based/run_U07_functional_annotation_eggnog.sh
```

### Build KEGG gene abundance tables from eggNOG-mapper annotation
```bash
conda activate metagenomics-assembly
bash scripts/assembly_based/run_U08_build_kegg_abundance_tables.sh
```

### 06. 下游統計與視覺化
連接外部或是客製化的 python/R 腳本進行統計分析與視覺化，例如：
1. alpha / beta diversity
2. differential abundance testing
3. heatmap / barplot / volcano plot / network plot


### 分析架構應用
MetaPhlAn = 論文 taxonomy 主線
Kraken2 + Bracken = 補充驗證與廣泛掃描
HUMAnN = functional profiling 主線
Bracken × HUMAnN pathway = 可以做統計關聯

```bash
Primary taxonomy analysis
└── MetaPhlAn 4.2.4 + vJan25
    ├── all-level taxonomy table
    └── species abundance table

Secondary taxonomy validation
└── Kraken2 Standard DB
    ├── read-level classification output
    ├── all-level taxonomy report
    └── all-level cohort matrix
        │
        └── Bracken re-estimation
            ├── genus abundance table
            └── species abundance table

Primary functional analysis
└── HUMAnN 3.9
    ├── gene family CPM table
    ├── pathway relative-abundance table
    └── pathway coverage table
```