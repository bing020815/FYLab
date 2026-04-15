# ASV Pipeline

A. PacBio SOP 的定位

用途：PacBio HiFi full-length 16S upstream analysis
輸入：.hifi_reads.fastq.gz + metadata.tsv
核心工具：Nextflow + PacBio HiFi-16S-workflow + Singularity/Docker
輸出：ASV table、rep seqs、taxonomy、biom、qzv、report

B. FYLab common downstream SOP 的定位

用途：平台無關的共用分析
輸入：table.qza, rep-seqs.qza, taxonomy.tsv, metadata.tsv
核心工具：QIIME2 export、PICRUSt2、R/Python plotting
輸出：統計圖、pathway、heatmap、barplot、後續報告

### Repo Structure:
FYLab/
├─ README.md
├─ docs/
│  ├─ miseq_pre_upstream.md
│  ├─ pacbio_pre_upstream.md
│  ├─ common_post_upstream.md
│  └─ downstream_taxonomy.md
├─ scripts/
│  ├─ miseq/
│  │  ├─ trim_all.sh
│  │  ├─ make_manifest_miseq.sh
│  │  └─ run_miseq_qiime2.sh
│  ├─ pacbio/
│  │  ├─ setup_pacbio_env.sh
│  │  ├─ download_pacbio_workflow.sh
│  │  ├─ make_manifest_pacbio.sh
│  │  ├─ run_pacbio_workflow.sh
│  │  └─ collect_pacbio_output.sh
│  └─ common/
│     ├─ summarize_qiime2.sh
│     ├─ export_qiime2_artifacts.sh
│     └─ prepare_downstream_taxonomy.sh


### setup_pacbio_env.sh
```
#!/usr/bin/env bash
set -euo pipefail

ENV_NAME="pacbio16s"

if ! command -v conda >/dev/null 2>&1; then
    echo "[ERROR] 找不到 conda，請先安裝或先載入 conda。"
    exit 1
fi

if conda env list | awk '{print $1}' | grep -qx "${ENV_NAME}"; then
    echo "[INFO] conda 環境 ${ENV_NAME} 已存在，略過建立。"
else
    echo "[INFO] 建立 conda 環境: ${ENV_NAME}"
    conda create -n "${ENV_NAME}" -c conda-forge -c bioconda nextflow openjdk=17 git wget curl -y
fi

echo "[INFO] 完成。請使用以下指令啟動環境："
echo "conda activate ${ENV_NAME}"
```

### setup_pacbio_workflow.sh
```
#!/usr/bin/env bash
set -euo pipefail

TOOLS_DIR="${HOME}/tools"
WORKFLOW_DIR="${TOOLS_DIR}/HiFi-16S-workflow"

mkdir -p "${TOOLS_DIR}"

if [ -d "${WORKFLOW_DIR}/.git" ]; then
    echo "[INFO] 官方 workflow 已存在：${WORKFLOW_DIR}"
    echo "[INFO] 如需更新，請手動執行："
    echo "cd ${WORKFLOW_DIR} && git pull"
else
    echo "[INFO] 下載 PacBio 官方 workflow 到 ${WORKFLOW_DIR}"
    git clone https://github.com/PacificBiosciences/HiFi-16S-workflow.git "${WORKFLOW_DIR}"
fi

echo "[INFO] 完成。workflow 位置：${WORKFLOW_DIR}"
```

### make_manifest_pacbio.sh
```
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
RAW_DIR="${PROJECT_DIR}/raw_fastq"
SAMPLES_TSV="${PROJECT_DIR}/samples.tsv"
METADATA_TSV="${PROJECT_DIR}/metadata.tsv"

if [ ! -d "${RAW_DIR}" ]; then
    echo "[ERROR] 找不到資料夾：${RAW_DIR}"
    exit 1
fi

FASTQ_COUNT=$(find "${RAW_DIR}" -maxdepth 1 -name "*.fastq.gz" | wc -l)

if [ "${FASTQ_COUNT}" -eq 0 ]; then
    echo "[ERROR] ${RAW_DIR} 內沒有 fastq.gz 檔案"
    exit 1
fi

echo -e "sample-id\tabsolute-filepath" > "${SAMPLES_TSV}"
echo -e "sample_name\tcondition" > "${METADATA_TSV}"

for f in "${RAW_DIR}"/*.fastq.gz; do
    base=$(basename "${f}")
    sample=$(echo "${base}" | sed 's/\.hifi_reads\.fastq\.gz$//')
    abs=$(realpath "${f}")

    echo -e "${sample}\t${abs}" >> "${SAMPLES_TSV}"
    echo -e "${sample}\tUnknown" >> "${METADATA_TSV}"
done

echo "[INFO] 已建立：${SAMPLES_TSV}"
echo "[INFO] 已建立：${METADATA_TSV}"
echo "[INFO] 請確認 metadata.tsv 的 condition 是否需要手動修改。"
```


### run_pacbio_official.sh
```
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
ENV_NAME="pacbio16s"
WORKFLOW_DIR="${HOME}/tools/HiFi-16S-workflow"

SAMPLES_TSV="${PROJECT_DIR}/samples.tsv"
METADATA_TSV="${PROJECT_DIR}/metadata.tsv"
RESULTS_DIR="${PROJECT_DIR}/results"
LOGS_DIR="${PROJECT_DIR}/logs"
WORK_DIR="${PROJECT_DIR}/work"

CPU="${CPU:-8}"

mkdir -p "${RESULTS_DIR}" "${LOGS_DIR}" "${WORK_DIR}"

if [ ! -f "${SAMPLES_TSV}" ]; then
    echo "[ERROR] 找不到 ${SAMPLES_TSV}"
    exit 1
fi

if [ ! -f "${METADATA_TSV}" ]; then
    echo "[ERROR] 找不到 ${METADATA_TSV}"
    exit 1
fi

if [ ! -d "${WORKFLOW_DIR}" ]; then
    echo "[ERROR] 找不到官方 workflow：${WORKFLOW_DIR}"
    echo "請先執行 setup_pacbio_workflow.sh"
    exit 1
fi

if ! command -v conda >/dev/null 2>&1; then
    echo "[ERROR] 找不到 conda"
    exit 1
fi

source "$(conda info --base)/etc/profile.d/conda.sh"
conda activate "${ENV_NAME}"

cd "${PROJECT_DIR}"

echo "[INFO] 開始執行 PacBio workflow"
echo "[INFO] PROJECT_DIR = ${PROJECT_DIR}"
echo "[INFO] CPU = ${CPU}"

nextflow run "${WORKFLOW_DIR}/main.nf" \
    --input "${SAMPLES_TSV}" \
    --metadata "${METADATA_TSV}" \
    --dada2_cpu "${CPU}" \
    --vsearch_cpu "${CPU}" \
    -work-dir "${WORK_DIR}" \
    > "${LOGS_DIR}/nextflow.stdout.log" \
    2> "${LOGS_DIR}/nextflow.stderr.log"

echo "[INFO] PacBio workflow 執行完成"
echo "[INFO] 請查看 logs/ 與 workflow 輸出資料夾"
```

### collect_pacbio_output.sh
```
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$(pwd)}"
RESULTS_DIR="${PROJECT_DIR}/results"
FYLAB_DIR="${PROJECT_DIR}/fylab_results"

mkdir -p "${FYLAB_DIR}"

copy_if_exists () {
    local src="$1"
    local dst="$2"
    if [ -f "$src" ]; then
        cp "$src" "$dst"
        echo "[INFO] 已複製: $src -> $dst"
    else
        echo "[WARN] 找不到: $src"
    fi
}

# 你之後可依實際跑出來的檔案名稱再微調
copy_if_exists "${RESULTS_DIR}/dada2-ccs_table_filtered.qza" "${FYLAB_DIR}/table.qza"
copy_if_exists "${RESULTS_DIR}/dada2-ccs_rep_filtered.qza" "${FYLAB_DIR}/rep-seqs.qza"
copy_if_exists "${RESULTS_DIR}/dada2-ccs_stats.qza" "${FYLAB_DIR}/denoise-stats.qza"
copy_if_exists "${RESULTS_DIR}/best_taxonomy_withDB.tsv" "${FYLAB_DIR}/taxonomy.tsv"
copy_if_exists "${RESULTS_DIR}/feature-table-tax.biom" "${FYLAB_DIR}/feature-table-tax.biom"

echo "[INFO] 整理完成"
echo "[INFO] FYLab 共用結果位於：${FYLAB_DIR}"
```

### export_pacbio_for_fylab.sh
```
#!/usr/bin/env bash
set -euo pipefail

mkdir -p results

cp output/dada2/dada2-ccs_table_filtered.qza results/table.qza
cp output/dada2/dada2-ccs_rep_filtered.qza results/rep-seqs.qza
cp output/results/feature-table-tax.biom results/feature-table-tax.biom
cp output/results/best_taxonomy_withDB.tsv results/taxonomy.tsv
```


## PacBio HiFi full-length 16S
Step 1. 準備 PacBio input
官方要求 samples.tsv 至少有：
	•	sample-id
	•	absolute-filepath

Step 2. 跑官方 workflow
```
git clone https://github.com/PacificBiosciences/HiFi-16S-workflow.git
cd HiFi-16S-workflow

nextflow run main.nf \
  --input /path/to/samples.tsv \
  --metadata /path/to/metadata.tsv \
  --dada2_cpu 8 \
  --vsearch_cpu 8 \
  -profile singularity
```

Step 3. 匯整結果到 FYLab downstream format
	•	dada2-ccs_table_filtered.qza → table.qza
	•	dada2-ccs_rep_filtered.qza → rep-seqs.qza
	•	best_taxonomy_withDB.tsv 或 best_tax_merged_freq_tax.tsv → taxonomy.tsv
	•	feature-table-tax.biom → feature-table-tax.biom

