# PacBio HiFi 16S pre-upstream SOP
用於 PacBio HiFi full-length 16S 原始 fastq.gz 的前段分析。


# Table of Contents:
1. [|First-setup| 建立環境](#建立環境)
2. [|First-setup| 建立官方 workflow](#建立官方-workflow)
3. [|First-setup| 建立官方資料庫](#建立官方資料庫)
4. [|Pre-upstream| 建立專案](#建立專案)
5. [|Pre-upstream| 官方nextflow](#官方nextflow)
6. [|Pre-upstream| Taxonomy 檔案資料整理](#Taxonomy-檔案資料整理)
7. [|Post-upstream| 接續模型分類流程](#接續模型分類流程)


# 建立環境
建立 pacbio16s conda 環境
```bash
curl -O https://raw.githubusercontent.com/bing020815/FYLab/main/scripts/pacbio/setup_pacbio_env.sh
chmod +x setup_pacbio_env.sh
./setup_pacbio_env.sh
```
完成後可用啟動環境
```bash
conda activate pacbio16s
```
<p align="center"><a href="#PacBio-HiFi-16S-pre-upstream-SOP">Top</a></p>

# 建立官方 workflow
下載 [PacBio 官方 workflow](https://github.com/pacificbiosciences/HiFi-16S-workflow)
```bash
curl -O https://raw.githubusercontent.com/bing020815/FYLab/main/scripts/pacbio/setup_pacbio_workflow.sh
chmod +x setup_pacbio_workflow.sh
./setup_pacbio_workflow.sh
```
workflow預設放在
```bash
~/tools/HiFi-16S-workflow
```
<p align="center"><a href="#PacBio-HiFi-16S-pre-upstream-SOP">Top</a></p>

# 建立官方資料庫
下載官方資料庫
```bash
conda activate pacbio16s
cd ~/tools/HiFi-16S-workflow
nextflow run main.nf --download_db
```
<p align="center"><a href="#PacBio-HiFi-16S-pre-upstream-SOP">Top</a></p>

# 建立專案
基本專案資料夾

* raw_fastq/：原始 PacBio .fastq.gz
* samples.tsv：官方 workflow 的樣本輸入清單
* metadata.tsv：樣本分組與描述資料
* pacbio_results/：官方 workflow 
* logs/：Nextflow 執行紀錄
* work/：Nextflow 中間資料夾

```
project_name/
├─ raw_fastq/        << 自行建立
├─ samples.tsv       << 系統產出
├─ metadata.tsv      << 系統產出
├─ pacbio_results/   << 系統產出
├─ logs/             << 系統產出
└─ work/             << 系統產出
```

Step1. 啟動環境
```bash
conda activate pacbio16s
```

Step2. 所有 PacBio .fastq.gz 放入 raw_fastq/，並確認：
```bash
ls raw_fastq/*.fastq.gz
```
```bash
 # 範例格式，無需執行
m84036_230702_205216_s2.MAS16S_Fwd_01--MAS16S_Rev_13.hifi_reads.fastq.gz
m84036_230702_205216_s2.MAS16S_Fwd_01--MAS16S_Rev_25.hifi_reads.fastq.gz
m84036_230702_205216_s2.MAS16S_Fwd_01--MAS16S_Rev_37.hifi_reads.fastq.gz
```

Step3. 建立sample和metadata檔案
```bash
curl -O https://raw.githubusercontent.com/bing020815/FYLab/main/scripts/pacbio/make_manifest_pacbio.sh
chmod +x make_manifest_pacbio.sh
./make_manifest_pacbio.sh .
```

Step4. 檢查`sample.tsv`檔案
```bash
cat samples.tsv
```
```bash
 # 範例格式，無需執行
sample-id   absolute-filepath
sample1 /home/adprc/user/pacbio_run_YYYYMMDD/raw_fastq/sample1.fastq.gz
sample2 /home/adprc/user/pacbio_run_YYYYMMDD/raw_fastq/sample2.fastq.gz
```

Step5. 檢查`metadata.tsv`檔案
```bash
cat metadata.tsv
```
```bash
 # 範例格式，無需執行
sample_name condition
sample1 Control
sample2 Treatment
```
* condition 官方也把它設成 HTML report 裡會拿來做不同群組的區分
* condition 預設為 `Unknown`，若後續需要正式分組分析，需再手動修改。

<p align="center"><a href="#PacBio-HiFi-16S-pre-upstream-SOP">Top</a></p>

# 官方nextflow
[PacBio 官方 nextflow ](https://github.com/pacificbiosciences/HiFi-16S-workflow)流程步驟包含:
1. samples.tsv 與 metadata.tsv
2. 初始 QC
3. Primer trimming 與方向統一
4. 匯入 QIIME 2
5. DADA2 去噪生成 ASV
6. Rarefaction 與 diversity 相關輸出
7. Taxonomy classification
    * Naive Bayes：會產出 best_taxonomy_withDB.tsv、best_tax_merged_freq_tax.tsv、feature-table-tax.biom
    * VSEARCH：會產出 vsearch_merged_freq_tax.tsv、feature-table-tax_vsearch.biom、taxonomy_barplot_vsearch.qzv

Step1. 下載workflow執行檔案
``` bash
curl -O https://raw.githubusercontent.com/bing020815/FYLab/main/scripts/pacbio/run_pacbio_workflow.sh
chmod +x run_pacbio_workflow.sh
```

Step2. 啟動執行 workflow
* `CPU` 可調整
* 需要前景除錯資訊可改:`RUN_IN_TMUX=false CPU=8 ./run_pacbio_workflow.sh .`
* 需要補充官方 workflow 參數:
    + 已先修過 primer: `EXTRA_ARGS="--skip_primer_trim" CPU=8 ./run_pacbio_workflow.sh .`
    + 改 primer: `EXTRA_ARGS="--front_p AGRGTTYGATYMTGGCTCAG --adapter_p AAGTCGTAACAAGGTARCY" CPU=8 ./run_pacbio_workflow.sh .`
    + filter條件: `EXTRA_ARGS="--filterQ 20 --min_len 1200 --max_len 1550 --max_ee 2" CPU=8 ./run_pacbio_workflow.sh .`
```bash
EXTRA_ARGS="--filterQ 20 --min_len 1000 --max_len 1600 --max_ee 2" CPU=8 ./run_pacbio_workflow.sh .
```
腳本預設會使用 tmux 建立背景 session，以避免遠端斷線導致任務中止。
預設 session 命名規則：
```bash
pacbio_<project>_<yyyymmdd_HHMMSS>
```
使用 `run_pacbio_workflow.sh` 預設 tmux 模式時，
tmux 的主要用途是讓長時間任務在遠端斷線後仍持續執行。
workflow 輸出會導向：
- logs/nextflow.stdout.log 日誌
```bash
tail -f logs/nextflow.stdout.log
```
- logs/nextflow.stderr.log 監看與除錯
```bash
tail -f logs/nextflow.stderr.log
```
查看session進度狀態
``` bash
curl -O https://raw.githubusercontent.com/bing020815/FYLab/main/scripts/pacbio/check_pacbio_sessions.sh
chmod +x check_pacbio_sessions.sh
./scripts/pacbio/check_pacbio_sessions.sh
```

<p align="center"><a href="#PacBio-HiFi-16S-pre-upstream-SOP">Top</a></p>

# Taxonomy 檔案資料整理
PacBio workflow 完成後，可依需求選擇兩種整理模式：
1. `MODE=official`
   - 沿用 Nextflow workflow 的官方資料庫分類結果
   - 會將官方 taxonomy 整理成專案根目錄的 `taxonomy.tsv`

2. `MODE=fylab`
   - 只整理 DADA2 產生的核心中間產物
   - 官方 taxonomy 僅保留為參考檔
   - 後續 taxonomy classification 由 FYLab 自訂分類器處理

兩種模式都會產生 `taxonomy_source.txt`，用於標記 taxonomy 來源。

此腳本預設會使用 `tmux` 建立背景 session，以避免遠端 terminal 斷線導致任務中止。
預設 session 命名規則:
```
# 範例格式，無需執行
pacbio_<project>_<yyyymmdd_HHMMSS>
```

若需要自行命名，可使用 `TMUX_SESSION_NAME` 指定。


Step1. 下載資料整理執行檔
```bash
curl -O https://raw.githubusercontent.com/bing020815/FYLab/main/scripts/pacbio/collect_pacbio_output.sh
chmod +x collect_pacbio_output.sh
```


<details>
<summary><strong>使用官方分類模型結果</strong></summary>
 
* 用官方的 Naive Bayes classifier 分類結果接續後面的 Downstream Analysis
* Naive-Bayes classifier 來做分類會同時使用 3 個資料庫: GreenGenes2、GTDB、Silva
* 優先順序是 GG2 → GTDB → Silva
* 先嘗試做 species level，如果不行再做 genus level

```bash
MODE=official ./collect_pacbio_output.sh .
```
</details>

<details>
<summary><strong>使用 FYLab 自訂分類模型模式</strong></summary>

* 接續應用 Lab 客製化 Database 分類器和後面的 Downstream Analysis

```bash
MODE=fylab ./collect_pacbio_output.sh .
```
</details>

<p align="center"><a href="#PacBio-HiFi-16S-pre-upstream-SOP">Top</a></p>

# 接續模型分類流程

[接續回到主要共同步驟](../README.md)

<p align="center"><a href="#PacBio-HiFi-16S-pre-upstream-SOP">Top</a></p>

