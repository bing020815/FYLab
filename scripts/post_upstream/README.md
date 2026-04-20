# Dehost 與共同輸出腳本說明

本區整理 4 支與共同流程、dehost 與 downstream 準備相關的腳本說明，包含用途、輸入、輸出與使用方式。

---

## 1. `export_table_qza_to_phyloseq.sh`

### 用途
將共同流程中的核心 QIIME2 輸出整理為 `phyloseq/` 資料夾下可直接使用的基礎檔案，供後續：

- dehost
- PICRUSt2
- downstream 分析
- 一般表格檢視

使用。

此腳本主要負責：

- 匯出 `table.qza`
- 轉出 `feature-table.biom`
- 轉出 `otu_table.tsv`
- 匯出 `rep-seqs.qza` 為 `dna-sequences.fasta`
- 根據 `taxonomy_source.txt` 或本地 `taxonomy.qza / taxonomy.tsv` 準備 `taxonomy.tsv`

---

### 需要的輸入
專案根目錄至少需要：

- `table.qza`
- `rep-seqs.qza`

taxonomy 來源可為下列其中一種：

#### 方式 A：使用 `taxonomy_source.txt`
若專案根目錄存在 `taxonomy_source.txt`，腳本會讀取：

- `taxonomy_mode`
- `taxonomy_source_type`
- `taxonomy_source_file`

並依 `taxonomy_source_file` 指定的檔案作為 taxonomy 來源。

#### 方式 B：自動判斷
若沒有 `taxonomy_source.txt`，則會依序尋找：

1. `taxonomy.qza`
2. `taxonomy.tsv`

---

### 主要輸出
預設輸出至：

- `phyloseq/`

產生的主要檔案包含：
- `phyloseq/feature-table.biom`
- `phyloseq/otu_table.tsv`
- `phyloseq/dna-sequences.fasta`
- `phyloseq/taxonomy.tsv`
- `phyloseq/taxonomy_source.txt`

---

### 使用方式
```bash
./shell_tools/export_table_qza_to_phyloseq.sh .
```

### 備註
* 需先啟用含有 qiime 與 biom 的環境
* 預設使用環境名稱提示為 qiime2-2023.2
* 此腳本不處理 dehost，只負責產生 downstream 的基礎資料


## 2. `run_dehost_on_fasta.sh`

### 用途
對代表性序列 FASTA 執行 host genome 比對與去除宿主序列（dehost）。

此腳本的功能是：
1. 判斷要使用原始 FASTA 或長度過濾後 FASTA
2. 使用指定物種的 host genome bowtie2 index 進行比對
3. 匯出 host 與 non-host 序列
4. 顯示 dehost 前後序列統計與 alignment 摘要

此腳本屬於 dehost 過程工作區 的建立工具，輸出放在：
* phyloseq/dehost_work/


### 需要的輸入
至少需存在其中一種 FASTA：
* phyloseq/dehost_work/filtered_dna-sequences.fasta
* phyloseq/dna-sequences.fasta

其中：
* 若已存在 filtered_dna-sequences.fasta，會優先使用
* 否則使用原始 dna-sequences.fasta

並且需要：
* bowtie2
* samtools
* seqkit

以及對應物種的 bowtie2 index 檔案。

### 可調整參數
HOST_DB

指定要比對的宿主基因組。

支援：
* all
* dog
* cat
* mouse
* cattle
* duck
* goat
* horse
* pig

### THREADS

指定 bowtie2 / samtools / seqkit 使用的執行緒數。

### 主要輸出
輸出至：
* phyloseq/dehost_work/

主要檔案包含：
* filtered_dna-sequences.fasta（若前一步已有）
* mapping_host_genome.sam
* mapping_host_genome.bam
* mapped_host_genome.bam
* sorted_host.bam
* host_reads.fasta
* nonhost.bam
* nonhost_sorted.bam
* nonhost.fasta
* mapping_host_genome.txt

### 使用方式
```bash
HOST_DB=dog THREADS=2 ./shell_tools/run_dehost_on_fasta.sh .
```
例如比對到 dog host genome，使用 2 threads。

### 備註
* 此腳本只負責 dehost 比對與 nonhost 結果產生
* 不會直接建立 downstream 正式的 dehost 表格與 QIIME2 檔案
* downstream 正式輸出會由後續腳本整理到 dehost_output/


## 3. `filter_phyloseq_by_nonhost_ids.sh`

### 用途
根據 nonhost.fasta 中保留下來的 feature IDs，去過濾：

* taxonomy.tsv
* otu_table.tsv

建立 dehost 後正式使用的表格檔。

此腳本屬於 dehost 正式輸出整理 的第一步，輸出放在：

* phyloseq/dehost_output/

### 需要的輸入
需存在以下檔案：

* phyloseq/dehost_work/nonhost.fasta
* phyloseq/taxonomy.tsv
* phyloseq/otu_table.tsv

### 主要輸出
輸出至：
* phyloseq/dehost_output/

主要檔案包含：
* keep_ids.txt
* dehost_taxonomy.tsv
* dehost_otu_table.tsv


### 使用方式
```bash
./shell_tools/filter_phyloseq_by_nonhost_ids.sh .
```

### 處理邏輯

1. 從 nonhost.fasta 抽出保留的 feature IDs
2. 建立 keep_ids.txt
3. 用 keep_ids.txt 過濾 taxonomy.tsv
4. 用 keep_ids.txt 過濾 otu_table.tsv

### 備註
* keep_ids.txt 是後續 downstream 過濾的重要中間索引
* 此腳本不建立 .biom、.qza 或 rep-seqs.qza
* 這些會由下一支 prepare_dehost_qiime2_inputs.sh 進一步處理


## 4. `prepare_dehost_qiime2_inputs.sh`

### 用途
將 dehost 後的表格整理為 downstream 可直接接續使用的 QIIME2 與相關輸入檔。

此腳本主要負責：
1. dehost_otu_table.tsv 轉成 .biom
2. .biom 匯入為 dehost_otu_table.qza
3. 使用 dehost table 過濾原始 rep-seqs.qza
4. 匯入 dehost_taxonomy.tsv 成 dehost_taxonomy.qza
5. 準備 dehost_dna-sequences.fasta

此腳本屬於 dehost 正式輸出整理 的第二步，輸出放在：
* phyloseq/dehost_output/

### 需要的輸入
需存在以下檔案：
* phyloseq/dehost_output/dehost_otu_table.tsv
* phyloseq/dehost_output/dehost_taxonomy.tsv
* rep-seqs.qza

若 LINK_DEHOST_FASTA=true，且要建立 fasta symlink，則還需：
* phyloseq/dehost_work/nonhost.fasta

### 主要輸出
輸出至：
* phyloseq/dehost_output/

主要檔案包含：
* dehost_otu_table.biom
* dehost_otu_table.qza
* dehost_rep_seqs.qza
* dehost_taxonomy.qza
* dehost_dna-sequences.fasta

### dehost_dna-sequences.fasta 的處理方式
預設：使用 symlink
預設：
```bash
LINK_DEHOST_FASTA=true
```
此時會建立：
* dehost_output/dehost_dna-sequences.fasta -> ../dehost_work/nonhost.fasta

優點：
* 路徑固定，方便 downstream 使用
* 不重複複製 FASTA，節省空間

若停用 symlink
可使用：
```bash
LINK_DEHOST_FASTA=false ./shell_tools/prepare_dehost_qiime2_inputs.sh .
```
此時會改由：
* dehost_rep_seqs.qza

匯出實體 FASTA，再複製成：
* dehost_dna-sequences.fasta

### 使用方式
```bash
./shell_tools/prepare_dehost_qiime2_inputs.sh .
```
若想停用 symlink：
```bash
LINK_DEHOST_FASTA=false ./shell_tools/prepare_dehost_qiime2_inputs.sh .
```

### 備註
* 需先啟用含有 qiime 與 biom 的環境
* 預設提示環境名稱為 qiime2-2023.2
* 此腳本完成後，dehost_output/ 內的資料即可作為：
    * dehost downstream 分析
    * PICRUSt2
    * pathway 分析
    * 其他後續流程輸入



## 資料夾角色總結
### phyloseq/

共同流程基礎輸出區，包含：
* otu_table.tsv
* taxonomy.tsv
* dna-sequences.fasta
* feature-table.biom

### phyloseq/dehost_work/

dehost 過程工作區，放中間檔與 host / nonhost 結果，例如：
* filtered_dna-sequences.fasta
* mapping_host_genome.sam
* mapping_host_genome.bam
* host_reads.fasta
* nonhost.fasta

### phyloseq/dehost_output/

dehost 後正式輸出區，放 downstream 直接使用的檔案，例如：
* dehost_otu_table.tsv
* dehost_taxonomy.tsv
* dehost_otu_table.qza
* dehost_rep_seqs.qza
* dehost_dna-sequences.fasta

