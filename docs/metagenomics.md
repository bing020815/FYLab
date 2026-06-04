# Shotgun Metagenomics Pipeline

A. Metagenomics SOP 定位

用途： analysis
輸入：.R1.fastq.gz + .R2.fastq.gz + metadata.tsv
核心工具：fastp + kraken2 + bracken + R/Python plotting
輸出：統計圖、pathway、heatmap、barplot

fastp = 把原始 reads 整理乾淨
MetaPhlAn / Kraken2 = 判斷有哪些菌
HUMAnN = 判斷有哪些功能與 pathway
Bowtie2 / KneadData = 去宿主 reads

metagenomics-taxonomy
└── MetaPhlAn 4.2.4 + vJan25 DB
    用於正式 taxonomy profiling

metagenomics-humann
└── HUMAnN 3.9 + MetaPhlAn 4.1.1 + vJun23 DB
    用於 functional profiling

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
│
├── scripts/
│   ├── run_01_fastp.sh
│   ├── run_02_dehost_human.sh
│   └── run_02_dehost_human.sh.bak
│
├── db/ # 放 WMS 分析用資料庫路徑紀錄或 symbolic link
│
├── tmp/ # 暫存檔，可清理
│
├── logs/ # 全域 logs，可放總流程 log
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
    │   ├── logs/
    │   │   ├── YZA.metaphlan.log
    │   │   └── YZB.metaphlan.log
    │   │
    │   └── merged_abundance.tsv
    │
    ├── 04_kraken2/
    │   ├── reports/
    │   ├── outputs/
    │   └── logs/
    │
    ├── 05_bracken/
    │   ├── genus/
    │   ├── species/
    │   └── merged_tables/
    │
    ├── 06_humann/
    │   ├── sample_outputs/
    │   ├── genefamilies/
    │   ├── pathabundance/
    │   ├── pathcoverage/
    │   └── logs/
    │
    ├── 07_tables/
    │   ├── species_abundance.tsv
    │   ├── genus_abundance.tsv
    │   ├── pathway_abundance.tsv
    │   └── gene_family_abundance.tsv
    │
    └── 08_figures/
        ├── barplots/
        ├── heatmaps/
        ├── pcoa/
        └── qc_summary/
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
└── 06. 下游統計與視覺化
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
#!/usr/bin/env bash
set -euo pipefail

METAPHLAN_DB="/home/adprc/databases/metagenomics/metaphlan"
THREADS=12

mkdir -p results/03_metaphlan/profiles
mkdir -p results/03_metaphlan/bowtie2out
mkdir -p results/03_metaphlan/logs

for sample in YZA YZB; do
  echo "[INFO] Running MetaPhlAn for ${sample}"

  metaphlan \
    results/02_dehost/clean_reads/${sample}_R1.dehost.fq.gz,results/02_dehost/clean_reads/${sample}_R2.dehost.fq.gz \
    --input_type fastq \
    --db_dir "${METAPHLAN_DB}" \
    --nproc "${THREADS}" \
    --mapout results/03_metaphlan/bowtie2out/${sample}.bowtie2.bz2 \
    -o results/03_metaphlan/profiles/${sample}_profile.txt \
    2>&1 | tee results/03_metaphlan/logs/${sample}.metaphlan.log

  echo "[INFO] Done: ${sample}"
done
EOF

chmod +x scripts/run_03_metaphlan.sh
```

04. Kraken2
```bash
#!/usr/bin/env bash
set -euo pipefail

KRAKEN2_DB="/home/adprc/databases/metagenomics/kraken2/standard"
THREADS=12

mkdir -p results/04_kraken2/reports
mkdir -p results/04_kraken2/outputs
mkdir -p results/04_kraken2/logs

for sample in YZA YZB; do
  echo "[INFO] Running Kraken2 for ${sample}"

  kraken2 \
    --db "${KRAKEN2_DB}" \
    --threads "${THREADS}" \
    --paired \
    --report results/04_kraken2/reports/${sample}.kraken2.report \
    --output results/04_kraken2/outputs/${sample}.kraken2.output \
    results/02_dehost/clean_reads/${sample}_R1.dehost.fq.gz \
    results/02_dehost/clean_reads/${sample}_R2.dehost.fq.gz \
    2>&1 | tee results/04_kraken2/logs/${sample}.kraken2.log

  echo "[INFO] Done: ${sample}"
done
EOF

chmod +x scripts/run_04_kraken2.sh
```

05. Bracken
```bash
#!/usr/bin/env bash
set -euo pipefail

KRAKEN2_DB="/home/adprc/databases/metagenomics/kraken2/standard"
READ_LEN=150
LEVEL="S"

mkdir -p results/05_bracken/species
mkdir -p results/05_bracken/logs

for sample in YZA YZB; do
  echo "[INFO] Running Bracken species-level for ${sample}"

  bracken \
    -d "${KRAKEN2_DB}" \
    -i results/04_kraken2/reports/${sample}.kraken2.report \
    -o results/05_bracken/species/${sample}.bracken.S.tsv \
    -w results/05_bracken/species/${sample}.bracken.S.report \
    -r "${READ_LEN}" \
    -l "${LEVEL}" \
    2>&1 | tee results/05_bracken/logs/${sample}.bracken.S.log

  echo "[INFO] Done: ${sample}"
done
EOF

chmod +x scripts/run_05_bracken_species.sh
```

06. merge tables for samples
```bash
#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="results/06_taxonomy_tables"
METAPHLAN_PROFILE_DIR="results/03_metaphlan/profiles"
BRACKEN_SPECIES_DIR="results/05_bracken/species"
BRACKEN_GENUS_DIR="results/05_bracken/genus"

mkdir -p "${OUT_DIR}"

echo "[INFO] Checking input files"

ls "${METAPHLAN_PROFILE_DIR}"/*_profile.txt >/dev/null
ls "${BRACKEN_SPECIES_DIR}"/*.bracken.S.tsv >/dev/null
ls "${BRACKEN_GENUS_DIR}"/*.bracken.G.tsv >/dev/null

echo "[INFO] Merging MetaPhlAn profiles"

merge_metaphlan_tables.py \
  "${METAPHLAN_PROFILE_DIR}"/*_profile.txt \
  > "${OUT_DIR}/metaphlan_all_levels_taxa_by_sample.tsv"

echo "[INFO] Building standardized taxonomy tables"

python - <<'PY'
from __future__ import annotations

from pathlib import Path
import re
import pandas as pd

OUT_DIR = Path("results/06_taxonomy_tables")
METAPHLAN_MERGED = OUT_DIR / "metaphlan_all_levels_taxa_by_sample.tsv"
BRACKEN_SPECIES_DIR = Path("results/05_bracken/species")
BRACKEN_GENUS_DIR = Path("results/05_bracken/genus")


def save_both_orientations(
    taxa_by_sample_df: pd.DataFrame,
    stem: str,
) -> None:
    """Save taxa × sample and sample × taxa matrices."""
    taxa_by_sample_df.to_csv(
        OUT_DIR / f"{stem}_taxa_by_sample.tsv",
        sep="\t",
        index=True,
    )

    taxa_by_sample_df.T.to_csv(
        OUT_DIR / f"{stem}_sample_by_taxa.tsv",
        sep="\t",
        index=True,
        index_label="SampleID",
    )


def load_metaphlan_table(path: Path) -> pd.DataFrame:
    """Load official merge_metaphlan_tables.py output."""
    a_df = pd.read_csv(
        path,
        sep="\t",
        comment="#",
        index_col=0,
    )

    a_df.index.name = "clade_name"

    # Convert all abundance values to numeric and replace missing values with zero.
    a_df = a_df.apply(pd.to_numeric, errors="coerce").fillna(0.0)

    return a_df


def extract_metaphlan_level(
    a_df: pd.DataFrame,
    rank_prefix: str,
) -> pd.DataFrame:
    """Keep rows terminating at a specified MetaPhlAn taxonomy rank."""
    rank_pattern = re.compile(rf"(?:^|\|){re.escape(rank_prefix)}[^|]+$")

    selected_index = [
        taxon
        for taxon in a_df.index.astype(str)
        if rank_pattern.search(taxon)
    ]

    return a_df.loc[selected_index].copy()


def merge_bracken_tables(
    input_dir: Path,
    pattern: str,
    sample_suffix: str,
    value_col: str,
) -> pd.DataFrame:
    """
    Merge Bracken output tables.

    Index combines taxonomy name and taxonomy ID to avoid collisions when
    distinct taxa share the same display name.
    """
    sample_series_list: list[pd.Series] = []

    for path in sorted(input_dir.glob(pattern)):
        sample_id = path.name.removesuffix(sample_suffix)

        a_df = pd.read_csv(path, sep="\t")

        required_cols = {
            "name",
            "taxonomy_id",
            "taxonomy_lvl",
            value_col,
        }
        missing_cols = required_cols.difference(a_df.columns)

        if missing_cols:
            raise ValueError(
                f"{path} is missing required columns: {sorted(missing_cols)}"
            )

        taxon_key = (
            a_df["name"].astype(str)
            + "|taxid__"
            + a_df["taxonomy_id"].astype(str)
        )

        sample_series = pd.Series(
            data=pd.to_numeric(a_df[value_col], errors="coerce").fillna(0.0).values,
            index=taxon_key,
            name=sample_id,
        )

        # Defensive aggregation in case a taxon key appears more than once.
        sample_series = sample_series.groupby(level=0).sum()
        sample_series_list.append(sample_series)

    if not sample_series_list:
        raise FileNotFoundError(
            f"No Bracken tables matched {input_dir / pattern}"
        )

    merged_df = pd.concat(sample_series_list, axis=1).fillna(0.0)
    merged_df.index.name = "taxon"
    return merged_df


# -------------------------------------------------------------------------
# MetaPhlAn: relative abundance
# -------------------------------------------------------------------------
metaphlan_all_df = load_metaphlan_table(METAPHLAN_MERGED)

save_both_orientations(
    metaphlan_all_df,
    "metaphlan_all_levels_relative_abundance",
)

metaphlan_species_df = extract_metaphlan_level(
    metaphlan_all_df,
    rank_prefix="s__",
)

save_both_orientations(
    metaphlan_species_df,
    "metaphlan_species_relative_abundance",
)

# -------------------------------------------------------------------------
# Bracken: species and genus outputs
# -------------------------------------------------------------------------
for rank_name, input_dir, pattern, sample_suffix in [
    (
        "species",
        BRACKEN_SPECIES_DIR,
        "*.bracken.S.tsv",
        ".bracken.S.tsv",
    ),
    (
        "genus",
        BRACKEN_GENUS_DIR,
        "*.bracken.G.tsv",
        ".bracken.G.tsv",
    ),
]:
    fraction_df = merge_bracken_tables(
        input_dir=input_dir,
        pattern=pattern,
        sample_suffix=sample_suffix,
        value_col="fraction_total_reads",
    )

    est_reads_df = merge_bracken_tables(
        input_dir=input_dir,
        pattern=pattern,
        sample_suffix=sample_suffix,
        value_col="new_est_reads",
    )

    save_both_orientations(
        fraction_df,
        f"bracken_{rank_name}_relative_abundance",
    )

    save_both_orientations(
        est_reads_df,
        f"bracken_{rank_name}_estimated_reads",
    )

print("[INFO] Taxonomy table merge completed")
print(f"[INFO] Output directory: {OUT_DIR}")
print(f"[INFO] MetaPhlAn species taxa: {metaphlan_species_df.shape[0]}")
PY

echo "[INFO] Output files:"
find "${OUT_DIR}" -maxdepth 1 -type f -printf "%f\n" | sort
EOF

chmod +x scripts/run_06_merge_taxonomy_tables.sh
```

07. HUMAnN
```bash
#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# HUMAnN functional profiling
#
# Required environment:
#   conda activate metagenomics-function
#
# Input:
#   results/02_dehost/clean_reads/<sample>_R1.dehost.fq.gz
#   results/02_dehost/clean_reads/<sample>_R2.dehost.fq.gz
#   results/03_metaphlan/profiles/<sample>_profile.txt
#
# Output:
#   results/07_humann/<sample>/
# ==============================================================================

THREADS=12

# ------------------------------------------------------------------------------
# MetaPhlAn wrapper
#
# HUMAnN checks `metaphlan --version` during startup.
# This wrapper ensures MetaPhlAn uses the shared DB.
# ------------------------------------------------------------------------------
export PATH="/home/adprc/tools/metaphlan-shared-db/bin:/home/adprc/miniconda3/envs/metagenomics-taxonomy/bin:${PATH}"

# ------------------------------------------------------------------------------
# Shared HUMAnN databases
# ------------------------------------------------------------------------------
NUCLEOTIDE_DB="/home/adprc/databases/metagenomics/humann/chocophlan/chocophlan"
PROTEIN_DB="/home/adprc/databases/metagenomics/humann/uniref/uniref"

# ------------------------------------------------------------------------------
# Project folders
# ------------------------------------------------------------------------------
DEHOST_DIR="results/02_dehost/clean_reads"
METAPHLAN_DIR="results/03_metaphlan/profiles"
OUT_DIR="results/07_humann"
TMP_DIR="tmp/humann_input"
LOG_DIR="${OUT_DIR}/logs"

SAMPLES=("YZA" "YZB")

mkdir -p "${OUT_DIR}" "${TMP_DIR}" "${LOG_DIR}"

# ------------------------------------------------------------------------------
# Preflight checks
# ------------------------------------------------------------------------------
echo "[INFO] Checking required commands"

command -v humann >/dev/null 2>&1 || {
  echo "[ERROR] humann not found"
  exit 1
}

command -v metaphlan >/dev/null 2>&1 || {
  echo "[ERROR] metaphlan not found"
  exit 1
}

echo "[INFO] HUMAnN version:"
humann --version

echo "[INFO] MetaPhlAn command:"
which metaphlan

echo "[INFO] MetaPhlAn version and shared DB:"
metaphlan --version

if [ ! -d "${NUCLEOTIDE_DB}" ]; then
  echo "[ERROR] HUMAnN nucleotide DB not found:"
  echo "        ${NUCLEOTIDE_DB}"
  exit 1
fi

if [ ! -d "${PROTEIN_DB}" ]; then
  echo "[ERROR] HUMAnN protein DB not found:"
  echo "        ${PROTEIN_DB}"
  exit 1
fi

# ------------------------------------------------------------------------------
# Run HUMAnN
# ------------------------------------------------------------------------------
for sample in "${SAMPLES[@]}"; do
  echo
  echo "============================================================"
  echo "[INFO] Sample: ${sample}"
  echo "============================================================"

  r1="${DEHOST_DIR}/${sample}_R1.dehost.fq.gz"
  r2="${DEHOST_DIR}/${sample}_R2.dehost.fq.gz"
  taxonomic_profile="${METAPHLAN_DIR}/${sample}_profile.txt"

  combined_fastq="${TMP_DIR}/${sample}.dehost.combined.fastq.gz"
  sample_out_dir="${OUT_DIR}/${sample}"
  sample_log="${LOG_DIR}/${sample}.humann.log"

  for input_file in "${r1}" "${r2}" "${taxonomic_profile}"; do
    if [ ! -f "${input_file}" ]; then
      echo "[ERROR] Missing input file:"
      echo "        ${input_file}"
      exit 1
    fi
  done

  if [ ! -s "${combined_fastq}" ]; then
    echo "[INFO] Combining paired-end reads for ${sample}"

    cat \
      "${r1}" \
      "${r2}" \
      > "${combined_fastq}"
  else
    echo "[INFO] Reusing combined FASTQ:"
    echo "       ${combined_fastq}"
  fi

  mkdir -p "${sample_out_dir}"

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
    2>&1 | tee "${sample_log}"

  echo "[INFO] Done: ${sample}"
done

echo
echo "============================================================"
echo "[INFO] HUMAnN functional profiling completed"
echo "============================================================"

find "${OUT_DIR}" \
  -maxdepth 2 \
  -type f \
  \( \
    -name "*_genefamilies.tsv" \
    -o -name "*_pathabundance.tsv" \
    -o -name "*_pathcoverage.tsv" \
    -o -name "*_reactions.tsv" \
  \) \
  -print | sort
EOF

chmod +x scripts/run_07_humann.sh
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


### 04. Taxonomic profiling
啟動 metagenomics-taxonomy conda 環境：
* MetaPhlAn version 4.2.4 (21 Oct 2025)      
* Kraken version 2.17.1
* Bracken
```bash
conda activate metagenomics-taxonomy
```
        
#### MetaPhlAn
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
ChocoPhlAn：nucleotide database
UniRef：protein database
```bash
conda activate metagenomics-function
```
```bash
bash scripts/run_07_humann.sh
```
#### HUMAnN

### 06. 下游統計與視覺化