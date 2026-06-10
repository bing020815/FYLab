# Shotgun Metagenomics Pipeline
Metagenomics SOP 定位

用途： analysis
輸入：.R1.fastq.gz + .R2.fastq.gz + metadata.tsv
核心工具：fastp + kraken2 + bracken + R/Python plotting
輸出：統計圖、pathway、heatmap、barplot

fastp = 原始 reads 品質控制、adapter trimming 與低品質 reads 過濾
Bowtie2 = 對人類基因組 index 比對，去除宿主 reads
MetaPhlAn = marker-based taxonomy profiling
Kraken2 = k-mer-based taxonomy classification
Bracken = 依據 Kraken2 report 重新估算 genus / species abundance
HUMAnN = gene family、pathway abundance 與 pathway coverage profiling
R / Python = 下游統計分析與繪圖

host-tools
└── fastp、seqkit、Bowtie2
    用於 QC 與去宿主 reads

metagenomics-taxonomy
└── MetaPhlAn 4.2.4 + vJan25 DB
    用於正式 taxonomy profiling

metagenomics-humann
└── HUMAnN 3.9 + MetaPhlAn 4.1.1 + vJun23 DB
    用於 functional profiling

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
    │   │   ├── YZA.kraken2.report
    │   │   └── YZB.kraken2.report
    │   │
    │   ├── outputs/
    │   │   ├── YZA.kraken2.output
    │   │   └── YZB.kraken2.output
    │   │
    │   └── logs/
    │       ├── YZA.kraken2.log
    │       └── YZB.kraken2.log
    │
    ├── 05_bracken/
    │   ├── species/
    │   │   ├── YZA.bracken.S.tsv
    │   │   ├── YZA.bracken.S.report
    │   │   ├── YZB.bracken.S.tsv
    │   │   └── YZB.bracken.S.report
    │   │
    │   ├── genus/
    │   │   ├── YZA.bracken.G.tsv
    │   │   ├── YZA.bracken.G.report
    │   │   ├── YZB.bracken.G.tsv
    │   │   └── YZB.bracken.G.report
    │   │
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
```

### Process Flow:
```bash
Raw FASTQ
│
├── 01. 原始資料確認
│   ├── MD5 check
│   ├── seqkit stats
│   └── FastQC / MultiQC
│
├── 02. Read QC / trimming
│   └── fastp
│
├── 03. 去宿主 / 去污染 reads
│   ├── Bowtie2 對宿主 genome
│   └── 保留 unmapped microbial reads
│
├── 04. Taxonomic profiling
│   ├── MetaPhlAn：較乾淨、species-level profiling
│   └── Kraken2 + Bracken：覆蓋率高、速度快、可估豐度
│
├── 05. Functional profiling
│   └── HUMAnN：gene family / pathway / MetaCyc
│
└── 06. 下游統計與視覺化 [可接外部python/R腳本/web服務]
    ├── species abundance table
    ├── pathway abundance table
    ├── alpha / beta diversity
    ├── differential abundance
    └── heatmap / barplot / volcano / network
```

### Shell Script Template:

01. fastp
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

02. dehost
```bash
#!/usr/bin/env bash
set -euo pipefail

HOST_INDEX="/home/adprc/host_genome/genome_index/human_genome/host_genome_index"
THREADS=12

mkdir -p results/02_dehost/clean_reads
mkdir -p results/02_dehost/sam
mkdir -p results/02_dehost/logs

for sample in YZA YZB; do
  echo "[INFO] Dehost human reads for ${sample}"

  bowtie2 \
    -x "${HOST_INDEX}" \
    -1 results/01_fastp/clean_reads/${sample}_R1.clean.fq.gz \
    -2 results/01_fastp/clean_reads/${sample}_R2.clean.fq.gz \
    --very-sensitive \
    --threads "${THREADS}" \
    --un-conc-gz results/02_dehost/clean_reads/${sample}_dehost_R%.fq.gz \
    -S /dev/null \
    2> results/02_dehost/logs/${sample}.bowtie2.log

  # bowtie2 --un-conc-gz 會輸出 R1/R2 為 .1/.2，這裡重新命名成固定格式
  mv results/02_dehost/clean_reads/${sample}_dehost_R1.fq.gz results/02_dehost/clean_reads/${sample}_R1.dehost.fq.gz
  mv results/02_dehost/clean_reads/${sample}_dehost_R2.fq.gz results/02_dehost/clean_reads/${sample}_R2.dehost.fq.gz

  echo "[INFO] Done: ${sample}"
done

seqkit stats results/02_dehost/clean_reads/*.dehost.fq.gz \
  > results/02_dehost/seqkit_dehost_stats.tsv

echo "[INFO] Dehost stats written to results/02_dehost/seqkit_dehost_stats.tsv"
EOF

chmod +x scripts/run_02_dehost_human.sh
```

03. MetaPhlAn
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

03. MetaPhlAn humann compatible
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

04. Kraken2
```bash
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Kraken2 taxonomy classification
#
# Required conda environment:
#   conda activate metagenomics-taxonomy
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

KRAKEN2_DB="/home/adprc/databases/metagenomics/kraken2/standard"
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

05. Bracken
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

KRAKEN2_DB="/home/adprc/databases/metagenomics/kraken2/standard"
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

06. merge tables for samples
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

07. HUMAnN
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

08. humann tables
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
* MetaPhlAn version 4.2.4 (21 Oct 2025)      
* Kraken version 2.17.1
* Bracken
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

```bash
merge_metaphlan_tables.py \
  results/03_metaphlan/profiles/YZA_profile.txt \
  results/03_metaphlan/profiles/YZB_profile.txt \
  > results/03_metaphlan/merged_abundance.tsv
```

#### Kraken2
Kraken2: Standard prebuilt DB[https://benlangmead.github.io/aws-indexes/k2]
判斷 reads 可能屬於哪個分類節點

```bash
bash scripts/run_04_kraken2.sh
```

#### Bracken
重新分配 reads，估算 species/genus abundance
abundance re-estimation

```bash
bash scripts/run_05_bracken_species.sh

bash scripts/run_05_bracken_genus.sh
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

### 05. Functional profiling
啟動 metagenomics-function conda 環境：
* HUMAnN version 3.9.0
- ChocoPhlAn：nucleotide database
- UniRef：protein database
使用 HUMAnN 可相容的 MetaPhlAn database mpa_vJun23_CHOCOPhlAnSGB_202403
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