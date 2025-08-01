# FYLab 
* 20250728 updated
```
  + 新增序列模型資料庫: Greengenes, SILVA
  + Naive Bayesian 模型採用 V3-V4 段提升預測精準度
```

## Folder Management
* Window -> File WINSCP
* Mac -> Filezilla

主機名稱：140.127.97.45
使⽤者名稱：adprc

## Puty/terminal
Windos: Putty
  + IP: adprc@140.127.97.45

Mac: Terminal
  + run: ssh adprc@140.127.97.45


# Table of Content:
1. [FastQ files Preprocess：前處理Primer](#FastQ-files-Preprocess-前處理Primer)
2. [QIIME2 - Preparation 分析前準備](#QIIME2---Preparation-分析前準備)
3. [Dehost 排除host基因](#Dehost-排除host基因)
4. [畫圖](#畫圖)
5. [PICRUSt2 - Metabolism Pathway](#PICRUSt2---Metabolism-Pathway)


# FastQ files Preprocess 前處理Primer
FastQ現存現象:
* 舊機型上機(600 cycle): 有些有設定去除primer，不含primer的序列長度300 bp，但有少部分舊設定保有primer
* 新機型上機(600 cycle): 沒有額外設定，序列長度為含primer共計 300 bp
* 解決方法：統一所有FasqQ長度
  + 有prime的序列刪掉要去除掉primer
  + 沒primer的序列則保留不動，不切序列前段
![Primer](img/primer-idx.png)

## 啟用cutadapt環境
```
conda activate cutadapt310
```

## 建立一個資料夾放原始fastq檔
在自己的工作資料夾中，建立raw_fastq資料夾，並且移動所有fastq檔案至raw_fastq資料夾
```
mkdir raw_fastq
mv *.fastq.gz raw_fastq/
```

## 下載去除primer腳本與執行
```
curl -o trim_all.sh https://raw.githubusercontent.com/bing020815/FYLab/main/trim_all.sh
```

## 賦予執行權限
```
chmod +x trim_all.sh
```

## 執行去除primer腳本
* 腳本會尋找 raw_fastq/*_R1_*.fastq.gz 形式的檔案，請確認你已將 FASTQ 放在正確路徑下（raw_fastq/ 資料夾中）
* 剪完的檔案會輸出至 trimmed_fastq/ 目錄下
* raw_fastq/*_R1_*.fastq.gz 形式的檔案則不會被修改或刪除，需要清理空間時可優先清理這邊
```
./trim_all.sh
```

## 移動統一格式fastq資料至專案資料夾
* 將trimmed_fastq/ 目錄下所有剪完的fastq移動回專案資料夾下
* 會將舊存在的fastq覆蓋掉(原始fastq還是有在raw_fastq裡有保留)
```
mv -f trimmed_fastq/*.fastq.gz .
```

<p align="center"><a href="#fylab">Top</a></p>

# QIIME2 - Preparation 分析前準備
![QIIME2](img/QIIME2_flow.png)
## 對檢體資料清單絕對路徑輸出(更新排除掉'file_path.txt'列入清單)
```
find . -maxdepth 1 -type f \( ! -name 'file_path.txt' ! -name 'trim_all.sh' \) -exec realpath {} \; > file_path.txt
```

## 留下檢體的絕對路徑資料,按照儲存格式存成manifest.csv
* (按照順序: R1_forward, R2_reverse)
``` csv
 # 此為範例格式，無需執行
 sample-id,absolute-filepath,direction
 CH4773,/home/fyadmin/Desktop/Hong-Ying/CL/CH4773_S29_L001_R1_01.fastq.gz,forward
 CH4773,/home/fyadmin/Desktop/Hong-Ying/CL/CH4773_S29_L001_R2_001.fastq.gz,reverse
```
<details>
<summary>(Optional) 確認file_path.txt檔案與處理資料</summary>

(option)確認'file_path.txt'的資料紀錄是否存在
```
cat file_path.txt
```
  (option1): 去除最後一行資料
  ```
  sed -i '$d' file_path.txt
  ```
  (option2): 去除最後一行資料
  ```
  head -n -1 file_path.txt > temp_file.txt && mv temp_file.txt file_path.txt
  ```
  (option3): 手動抓資料下來，移除file_path.txt資料紀錄後上傳上去
  ```
  使用excel修改
  ```

(option)確認file_path.txt的資料紀錄已移除
```
cat file_path.txt
```
</details><br>

## 生成 manifest.csv
```
echo "sample-id,absolute-filepath,direction" > manifest.csv && \
awk -F'/' '
BEGIN { OFS="," }
{
  file = $NF
  split(file, parts, "_")
  sample = parts[1]
  if (file ~ /_R1_/) dir = "forward"
  else if (file ~ /_R2_/) dir = "reverse"
  else next

  key = sample"-"dir
  if (!seen[key]++) {
    print sample, $0, dir
  }
}' file_path.txt >> manifest.csv
```

## 將表有csv轉成逗號分個的txt檔案 
* (fastq轉黨qiime2用)
```
cp manifest.csv manifest.txt
```

## 把逗號分隔的csv改成製表符\t的tsv 
* (metadata才需要用到)
```
sed 's/,/\t/g' manifest.csv > manifest.tsv
```

# Import Data and Preprocessing
## 進入qiime2環境
```
conda activate qiime2-2023.2
```

## FASTQ 匯入轉檔 QIIME 2 可使用的格式 (.qza)
* (need to wait process time, use 'top' command to check, press 'q' to leave)
* 會產出 paired-end-demux.qza 檔案
* 依照manifest.txt將兩段序列配對
```
nohup qiime tools import --type 'SampleData[PairedEndSequencesWithQuality]' --input-path manifest.txt --output-path paired-end-demux.qza --input-format PairedEndFastqManifestPhred33 &
```

## 轉成可視化報表
* 利用 qza 檔案，轉黨輸出成qzv，可以畫成可視化報表
* https://view.qiime2.org/
```
nohup qiime demux summarize --i-data paired-end-demux.qza --o-visualization paired-end-demux.qzv &
```

## Denoise 去除雜訊 [標準流程: 270-240]
* 將qza檔案去完雜訊後，輸出成： table.qza, stats.qza, rep-seqs.qza 
* (need to take a long process time, use 'top'/'htop' command to check, press 'q' to leave)
* --p-trim-left-* 的數值應根據使用的 primer 長度設定。
* --p-trunc-len-* 需保留足夠長度供 forward + reverse read 重疊（overlap）至少約 20～30 bp。
* 例如：270 + 240 = 510，V3-V4的 amplicon 長度為 約460 bp，則 overlap 為 50 bp，屬於合理值(overlap 通常建議 >20-30 bp)
* (將雙端測序數據處理為高品質的序列數據，並輸出相關結果)
* 流程會先各自 denoise（F / R）→ 再合併 → 再去 chimera → 再輸出 ASV
* 不足trucLen的reads會被剃除、去除可能是拼接自高豐度序列的 chimera (default method:consensus)
* table.qzv - 可以看到Sample的取樣深度
```
nohup qiime dada2 denoise-paired \
--i-demultiplexed-seqs paired-end-demux.qza \
--p-trim-left-f 0 --p-trim-left-r 0 \
--p-trunc-len-f 270 --p-trunc-len-r 240 \
--p-n-threads 2 \
--o-representative-sequences rep-seqs.qza \
--o-table table.qza \
--o-denoising-stats stats.qza > nohup.out 2>&1 &
```
## 紀錄denoise設定
```
echo "--p-trim-left-f 0 --p-trim-left-r 0" >> denoise_settings.txt
echo "--p-trunc-len-f 270 --p-trunc-len-r 240" >> denoise_settings.txt
```

### 檢查stats檔案denosis狀態圖表
* 利用 qza 檔案，轉黨輸出成qzv，可以畫成可視化報表
* stats.qzv - 確認denoise中的資訊。
* https://view.qiime2.org/
```
qiime metadata tabulate \
  --m-input-file stats.qza \
  --o-visualization stats.qzv
```
### 直接看序列表長度[optional]
* (產出rep-seqs-summary.qzv)
```
qiime feature-table tabulate-seqs \
  --i-data rep-seqs.qza \
  --o-visualization rep-seqs-summary.qzv
```


# Analysis 導出特征表
## 建立導出用資料夾
```
mkdir phyloseq
```
## 轉黨qza檔案成biom檔案
* 輸入去除雜訊後的table.qza，再輸出成biom format: feature-table.biom
```
qiime tools export \
--input-path table.qza \
--output-path phyloseq
```

## Biom 轉黨
* 將輸出成biom format的當案轉黨成otu_table.tsv 
* biom 記錄樣本與 OTU/ASV 之間的豐度矩陣
```
biom convert \
-i phyloseq/feature-table.biom \
-o phyloseq/otu_table.tsv \
--to-tsv
```

## 模型分類
根據資料庫預測代表序列的ASV，資料庫可採用 GreenGenes 16S rRNA gene database、SILVA ribosomal RNA database 兩大資料庫。

<details>
<summary><strong>Greengenes 13_8 16S Self-trained [20250728 新增]</strong></summary>

GreenGenes 16S rRNA gene databas:
  + Greengene 1 13-8 只有更新到 2013.08，可參考序列數較多 (約 100,000 條)
  + Greengenes2 從 2022 年起開始重新建構，採用全基因體（WoL），但可參考序列數少 (約 21,000 條)

[Cite 參考資訊](https://docs.qiime2.org/2023.2/data-resources/)

### Option1: Naive Bayes 模型分類 (V3-V4)
```
nohup qiime feature-classifier classify-sklearn \
--i-classifier /home/adprc/classifier/gg/gg_13_8_99_NB_classifier_V3V4.qza \
--i-reads rep-seqs.qza \
--o-classification taxonomy.qza \
--p-n-jobs 2 > nohup.out 2>&1 &
```

### Option2: vsearch 模型分類 (full-length)
```
nohup qiime feature-classifier classify-consensus-vsearch \
  --i-query rep-seqs.qza \
  --i-reference-reads /home/adprc/classifier/gg/gg_13_8_99_RefSeq.qza \
  --i-reference-taxonomy /home/adprc/classifier/gg/gg_13_8_99_Taxonomy.qza \
  --p-threads 4 \
  --o-classification taxonomy.qza \
  --verbose > nohup_vsearch.out 2>&1 &
```

</details><br>

<details>
<summary><strong>SILVA 138 16S Self-trained [20250728 新增]</strong></summary>

SILVA ribosomal RNA database: 官方公開參考序列持續更新 (約 129,000 條)

[Cite 參考資訊](https://docs.qiime2.org/2024.10/data-resources/)
  
### Option1: Naive Bayes 模型分類 (V3-V4)
```
nohup qiime feature-classifier classify-sklearn \
--i-classifier /home/adprc/classifier/SILVA/silva_138_99_NB_classifier_V3V4.qza \
--i-reads rep-seqs.qza \
--o-classification taxonomy.qza \
--p-n-jobs 2 > nohup.out 2>&1 &
```

### Option2: vsearch 模型分類 (full-length)
```
nohup qiime feature-classifier classify-consensus-vsearch \
  --i-query rep-seqs.qza \
  --i-reference-reads /home/adprc/classifier/SILVA/silva_138_99_RefSeq.qza \
  --i-reference-taxonomy /home/adprc/classifier/SILVA/silva_138_99_Taxonomy.qzaa \
  --p-threads 4 \
  --o-classification taxonomy.qza \
  --verbose > nohup_vsearch.out 2>&1 &
```

</details><br>

<details>
<summary><strong>Greengenes 13_8 16S full-length</strong></summary>
  
### Step 1. 下載模型
* 下載 2023.09發布的Naive Bayes分類器，訓練用資料：GreenGenes 13_8，99% OTUs
* https://greengenes.lbl.gov/
* https://www.lcsciences.com/documents/sample_data/16S_sequencing/src/html/top2.html
```
wget https://data.qiime2.org/2023.9/common/gg-13-8-99-nb-classifier.qza
```

### Step2. Naive Bayes 模型分類
* 透過已訓練好的模型gg-13-8-99-nb-classifier.qza來預測，並輸出taxonomy.qza
* gg-13-8-99-nb-classifier.qza 要放在與 Fastq同層的資料夾，需要一些時間
```
nohup qiime feature-classifier classify-sklearn \
--i-classifier gg-13-8-99-nb-classifier.qza \
--i-reads rep-seqs.qza \
--o-classification taxonomy.qza \
--p-n-jobs 2 > nohup.out 2>&1 &
```

</details><br>


## qza格式轉檔
*  將分類好的輸出檔案taxonomy.qza轉黨為成taxonomy.tsv，存至phyloseq
```
qiime tools export \
--input-path taxonomy.qza \
--output-path phyloseq
```

### -- 解壓縮 rep-seqs.qza 檔案，產生dna-sequences.fasta，方便查詢Sequence、篩選350bp長度 --
* https://blast.ncbi.nlm.nih.gov/Blast.cgi?PAGE_TYPE=BlastSearch&BLAST_SPEC=MicrobialGenomes
```
qiime tools export \
  --input-path rep-seqs.qza \
  --output-path phyloseq
```

<p align="center"><a href="#fylab">Top</a></p>

# Dehost 排除host基因
## 啟動host-tools package 

包含: bowtie2, samtools, seqkit 工具包 
https://useast.ensembl.org/index.html
```
conda activate host-tools
```
### Step 1: 檢查代表性序列品質（QC）
```
seqkit stats phyloseq/dna-sequences.fasta
```

### Step 2: 加強篩選與過濾（可選）
* 去除R1, R2合併後小於 350 bp序列
* 保守篩選濾除低於 350 bp 序列，減少過多序列定序停留於Family
* 需要高品質、高分類準確度的研究，例如 菌種層級分析、生物標記開發
```
nohup seqkit seq -m 350 -M 500 -v phyloseq/dna-sequences.fasta -o phyloseq/filtered_dna-sequences.fasta &
```

### Step 3: 再檢查代表性序列品質（QC）
<details>
<summary><strong>使用加強篩選與過濾後語法</strong></summary>

```
seqkit stats phyloseq/filtered_dna-sequences.fasta
```
</details><br>
<details>
<summary><strong>未使用加強篩選與過濾語法</strong></summary>

```
seqkit stats phyloseq/dna-sequences.fasta
```
</details><br>

## 使用 Bowtie2 比對至[人類human/老鼠mouse/狗dog/貓cat/綜合物種all]基因組

<details>
<summary><strong>請選擇一項適合專案的基因組執行dehost</strong></summary>

  ### human [pick one fits the project]
  <details>
  <summary><strong>使用加強篩選與過濾後語法</strong></summary>
  
  ```
  nohup bowtie2 -x /home/adprc/host_genome/human_genome/host_genome_index \
         -f phyloseq/filtered_dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  </details><br>
  <details>
  <summary><strong>未使用加強篩選與過濾語法</strong></summary>
  
  ```
  nohup bowtie2 -x /home/adprc/host_genome/human_genome/host_genome_index \
         -f phyloseq/dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  </details><br>
  
  ### mouse [pick one fits the project]
  <details>
  <summary><strong>使用加強篩選與過濾後語法</strong></summary>
  
  ```
  nohup bowtie2 -x /home/adprc/host_genome/mouse_genome/host_genome_index \
         -f phyloseq/filtered_dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  </details><br>
  <details>
  <summary><strong>未使用加強篩選與過濾語法</strong></summary>
  
  ```
  nohup bowtie2 -x /home/adprc/host_genome/mouse_genome/host_genome_index \
         -f phyloseq/dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  </details><br>

  ### dog [pick one fits the project]
  <details>
  <summary><strong>使用加強篩選與過濾後語法</strong></summary>
  
  ```
  nohup bowtie2 -x /home/adprc/host_genome/dog_genome/host_genome_index \
         -f phyloseq/filtered_dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  </details><br>
  <details>
  <summary><strong>未使用加強篩選與過濾語法</strong></summary>
  
  ```
  nohup bowtie2 -x /home/adprc/host_genome/dog_genome/host_genome_index \
         -f phyloseq/dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  </details><br>
  
  
  ### cat [pick one fits the project]
  <details>
  <summary><strong>使用加強篩選與過濾後語法</strong></summary>
  
  ```
  nohup bowtie2 -x /home/adprc/host_genome/cat_genome/host_genome_index \
         -f phyloseq/filtered_dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  </details><br>
  <details>
  <summary><strong>未使用加強篩選與過濾語法</strong></summary>
  
  ```
  nohup bowtie2 -x /home/adprc/host_genome/cat_genome/host_genome_index \
         -f phyloseq/dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  </details><br>
  
  ### all(human, mouse, dog, cat, cattle, duck, goat, horse, pig, rabbit, turkey, chicken, sheep) [pick one fits the project]
  <details>
  <summary><strong>使用加強篩選與過濾後語法</strong></summary>
  
  ```
  nohup bowtie2 -x /home/adprc/host_genome/all_genome/host_genome_index \
         -f phyloseq/filtered_dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  </details><br>
  <details>
  <summary><strong>未使用加強篩選與過濾語法</strong></summary>
  
  ```
  nohup bowtie2 -x /home/adprc/host_genome/all_genome/host_genome_index \
         -f phyloseq/dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  </details><br>
</details><br>

## samtools 處理宿主基因
### 1.將 .sam 轉換為 .bam（二進位格式，處理效率更高）
```
samtools view -h -b phyloseq/mapping_host_genome.sam -o phyloseq/mapping_host_genome.bam
```
### 2.篩選出「成功比對上的宿主序列」
```
samtools view -h -b -F 4 phyloseq/mapping_host_genome.bam > phyloseq/mapped_host_genome.bam
```
### 3.排序 BAM 檔（按 read name）
```
samtools sort -n phyloseq/mapped_host_genome.bam -o phyloseq/sorted.bam
```
### 4.把比對上的宿主 reads 轉回 FASTA
```
samtools fasta -@ 2 phyloseq/sorted.bam -F 4 -0 phyloseq/host_reads.fasta
```
### 5.篩選出「未比對上的非宿主序列」
```
samtools view -h -b -f 4 phyloseq/mapping_host_genome.bam > phyloseq/nonhost.bam
```
### 6.排序未比對序列
```
samtools sort -n phyloseq/nonhost.bam -o phyloseq/nonhost_sorted.bam
```
### 7.匯出非宿主 reads 為 FASTA
```
samtools fasta -@ 2 phyloseq/nonhost_sorted.bam -f 4 -0 phyloseq/nonhost.fasta
```
### 查看host基因佔比 [option1]
* overall alignment rate: 宿主基因佔比
```
cat phyloseq/mapping_host_genome.txt
```
### 查看host基因佔比 [option2]
* dna-sequences.fasta: 原始代表性序列（未過濾長度）
* filtered_dna-sequences.fasta: 只保留長度 350~500 bp 的序列
* host_reads.fasta: 成功比對到宿主的序列（被剃除）
* nonhost.fasta: 未比對到宿主的序列（保留分析）
```
seqkit stats -T phyloseq/*.fasta | awk '{print $1, $4}' | column -t
```
## 輸出去除宿主基因otu_table.tsv, taxonomy.tsv
### 0.建立filtered資料夾
```
mkdir -p phyloseq/filtered_host
```
### 1.建立keep_ids
```
grep '^>' phyloseq/nonhost.fasta | sed 's/^>//' > phyloseq/filtered_host/keep_ids.txt
```
### 2.建立 dehost_taxonomy.tsv
```
awk 'FNR==NR {keep[$1]; next} FNR==1 || $1 in keep' phyloseq/filtered_host/keep_ids.txt phyloseq/taxonomy.tsv > phyloseq/filtered_host/dehost_taxonomy.tsv
```
### 3.建立 dehost_otu_table.tsv
```
awk 'FNR==NR {keep[$1]; next} FNR<=2 || $1 in keep' phyloseq/filtered_host/keep_ids.txt phyloseq/otu_table.tsv > phyloseq/filtered_host/dehost_otu_table.tsv
```
## 進入qiime2環境
```
conda activate qiime2-2023.2
```
### 1. Dehost pathway 流程前期準備: dehost_otu_table.tsv 轉檔 dehost_otu_table.biom
```
biom convert \
  -i phyloseq/filtered_host/dehost_otu_table.tsv \
  -o phyloseq/filtered_host/dehost_otu_table.biom \
  --to-hdf5 \
  --table-type="OTU table"
```
### 2. Dehost pathway 流程前期準備: 把 dehost_otu_table.biom 匯入為 QIIME2 格式
```
qiime tools import \
  --input-path phyloseq/filtered_host/dehost_otu_table.biom \
  --type 'FeatureTable[Frequency]' \
  --input-format BIOMV210Format \
  --output-path phyloseq/filtered_host/dehost_otu_table.qza
```
### 3. Dehost pathway 流程前期準備: 從原始 rep-seqs.qza 過濾出 dehost 用的 rep-seqs.qza
```
qiime feature-table filter-seqs \
  --i-data rep-seqs.qza \
  --i-table phyloseq/filtered_host/dehost_otu_table.qza \
  --o-filtered-data phyloseq/filtered_host/dehost_rep_seqs.qza
```
### 4. 把 taxonomy.qza 過濾出與 dehost 一致的分類結果
```
qiime tools import \
  --input-path phyloseq/filtered_host/dehost_taxonomy.tsv \
  --type 'FeatureData[Taxonomy]' \
  --output-path phyloseq/filtered_host/dehost_taxonomy.qza \
  --input-format HeaderlessTSVTaxonomyFormat
```
### 5. Dehost pathway 流程前期準備: 匯出 過濾出 dehost 用的 rep-seqs.fasta
```
qiime tools export \
  --input-path phyloseq/filtered_host/dehost_rep_seqs.qza \
  --output-path phyloseq/filtered_host/
```

<p align="center"><a href="#fylab">Top</a></p>

# 畫圖
## KEGG Pathway 前期準備
### 4.Phylogeny Tree (此步驟要超級久，可以多線程設定)
<details>
<summary><strong>Dehost使後用語法</strong></summary>

```
nohup qiime phylogeny align-to-tree-mafft-fasttree \
--i-sequences phyloseq/filtered_host/dehost_rep_seqs.qza \
--o-alignment aligned-rep-seqs.qza \
--o-masked-alignment masked-aligned-rep-seqs.qza \
--o-tree unrooted-tree.qza \
--o-rooted-tree rooted-tree.qza \
--p-n-threads 2 > nohup.out 2>&1 &
```
</details><br>
<details>
<summary><strong>未Dehost使後語法</strong></summary>

```
nohup qiime phylogeny align-to-tree-mafft-fasttree \
--i-sequences rep-seqs.qza \
--o-alignment aligned-rep-seqs.qza \
--o-masked-alignment masked-aligned-rep-seqs.qza \
--o-tree unrooted-tree.qza \
--o-rooted-tree rooted-tree.qza \
--p-n-threads 2 > nohup.out 2>&1 &
```
</details><br>


### 5.導出代表序列 (這步完成後，可以跳到 #PICRUSt2，直接啟動picrust2)
<details>
<summary><strong>Dehost使後用語法</strong></summary>

註: 產出dehost過的dna-sequences.fasta 於 `phyloseq/filtered_host/`
```
qiime tools export --input-path phyloseq/filtered_host/dehost_rep_seqs.qza --output-path phyloseq/filtered_host/
```
</details><br>
<details>
<summary><strong>未Dehost使後語法</strong></summary>
  
註: 產出dehost過的dna-sequences.fasta 於 `fastq1/`
```
qiime tools export --input-path rep-seqs.qza --output-path fastq1/
```
</details><br>

<p align="center"><a href="#fylab">Top</a></p>

<details>
<summary><strong>點我展開畫進化樹(optional)</strong></summary>
  
### 6.導出無根進化樹 [optional]
```
qiime tools export \
--input-path unrooted-tree.qza \
--output-path phyloseq
cd phyloseq; mv tree.nwk unrooted_tree.nwk; cd ../
```

### 7.導出有根進化樹 [optional]
```
qiime tools export \
--input-path rooted-tree.qza \
--output-path phyloseq
cd phyloseq; mv tree.nwk rooted_tree.nwk; cd ../
```
</details><br>


  
## OTU Bar Plot [optional]

<details>
<summary><strong>點我展開畫OTU圖</strong></summary>

### 產出taxa-bar.qzv
```
qiime taxa barplot \
  --i-table table.qza \
  --m-metadata-file metadata.tsv \
  --i-taxonomy taxonomy.qza \
  --o-visualization taxa-bar.qzv
```
</details><br>

## OTU Percentage(如果有要跑bar圖就要接著跑這個)  [optional]

<details>
<summary><strong>點我展開畫OTU圖</strong></summary>

### 1.Taxanomy Collapse
```
qiime taxa collapse \
--i-table table.qza \
--i-taxonomy taxonomy.qza \
--p-level 7 \
--o-collapsed-table collapse-table.qza
```

### 2.Relative Frequency  [optional]
```
qiime feature-table relative-frequency \
--i-table collapse-table.qza \
--o-relative-frequency-table relative-table.qza
```

### 3.Export  [optional]
```
qiime tools export \
--input-path relative-table.qza \
--output-path export-relative-table
```

### 4.Convert BIOM to TSV (最後用convert-relative-table.tsv上greengene網站跑圖)  [optional]
```
biom convert \
-i export-relative-table/feature-table.biom \
-o convert-relative-table.tsv \
--to-tsv \
--header-key taxonomy
```
</details><br>


  
## Diversity  [optional]
<details>
<summary><strong>點我展開畫Diversity圖</strong></summary>
  
### 1.
```
qiime diversity core-metrics-phylogenetic \
--i-phylogeny rooted-tree.qza \
--i-table table.qza \
--p-sampling-depth _ \
--m-metadata-file metadata.tsv \
--output-dir metrics
```
註:sample depth - 通常會以table.qzv中，觀察 樣本深度最低的數值做為sample depth的數值，才能取樣到所有樣本，若最低的與其他樣本落差太大，則取倒數第二低的數值。


## Alpha Diversity  [optional]
### 1.Alpha 稀疏曲線
```
qiime diversity alpha-rarefaction \
--i-table table.qza \
--p-max-depth _ \ 
--i-phylogeny rooted-tree.qza \
(--m-metadata-file metadata.tsv) \
--o-visualization rare.qzv
```

### 2.Shannon
```
qiime diversity alpha-group-significance \
--i-alpha-diversity metrics/shannon_vector.qza \
--m-metadata-file metadata.tsv \
--o-visualization metrics/shannon_vector.qzv
```

## Beta Diversity  [optional]
### weighted_unifrac
```
qiime diversity beta-group-significance \
--i-distance-matrix metrics/weighted_unifrac_distance_matrix.qza \
--m-metadata-file metadata.tsv \
--m-metadata-column group \
--o-visualization metrics/weighted_unifrac-group-significance.qzv \
--p-pairwise
```
註:
weighted_unifrac
unweighted_unifrac
bray_curtis
jaccard


## Exit QIIME2  [optional]
```
conda deactivate
```
</details><br>

<p align="center"><a href="#fylab">Top</a></p>

# PICRUSt2 - Metabolism Pathway
![PICRUSt2](img/picrust2_flow.png)
## 啟動PICRUSt2 package
```
conda activate picrust2
```

## 1.Place reads into reference tree (此階段需跑一下)

<details>
<summary><strong>Dehost使後用語法</strong></summary>
  
-p 可改設定核心 能設定為4-6
+ 就算最後 log 出現 Exit 1，只要產生的 out.tre 與 place_seqs_out/ 資料夾存在且完整，就可繼續執行後續流程
```
nohup place_seqs.py \
-s phyloseq/filtered_host/dna-sequences.fasta \
-o out.tre \
-p 2 \
--intermediate intermediate/place_seqs &
```
</details><br>
<details>
<summary><strong>未Dehost使用語法</strong></summary>
  
-p 可改設定核心 能設定為4-6
```
nohup place_seqs.py \
-s fastq1/dna-sequences.fasta \
-o out.tre \
-p 2 \
--intermediate intermediate/place_seqs &
```
</details><br>

## 2.Hidden-state prediction
```
nohup hsp.py \
-i 16S \
-t out.tre \
-o marker_predicted_and_nsti.tsv.gz \
-p 2 \
-n &
```
KO
```
nohup hsp.py \
-i KO \
-t out.tre \
-o KO_predicted.tsv.gz \
-p 2 &
```
EC
```
nohup hsp.py \
-i EC \
-t out.tre \
-o EC_predicted.tsv.gz \
-p 2 &
```

## 3.Generate metagenome predictions
KO
<details>
<summary><strong>Dehost使後用語法</strong></summary>

```
nohup metagenome_pipeline.py \
-i phyloseq/filtered_host/dehost_otu_table.biom \
-m marker_predicted_and_nsti.tsv.gz \
-f KO_predicted.tsv.gz \
-o KO_metagenome_out \
--strat_out &
```
</details><br>
<details>
<summary><strong>未Dehost使用語法</strong></summary>

```
nohup metagenome_pipeline.py \
-i phyloseq/feature-table.biom \
-m marker_predicted_and_nsti.tsv.gz \
-f KO_predicted.tsv.gz \
-o KO_metagenome_out \
--strat_out &
```
</details><br>

EC
<details>
<summary><strong>Dehost使後用語法</strong></summary>

```
nohup metagenome_pipeline.py \
-i phyloseq/filtered_host/dehost_otu_table.biom \
-m marker_predicted_and_nsti.tsv.gz \
-f EC_predicted.tsv.gz \
-o EC_metagenome_out \
--strat_out &
```
</details><br>
<details>
<summary><strong>未Dehost使用語法</strong></summary>

```
nohup metagenome_pipeline.py \
-i phyloseq/feature-table.biom \
-m marker_predicted_and_nsti.tsv.gz \
-f EC_predicted.tsv.gz \
-o EC_metagenome_out \
--strat_out &
```
</details><br>


## 4.KEGG pathway
# KEGG pathway - overview
```
nohup pathway_pipeline.py \
-i KO_metagenome_out/pred_metagenome_unstrat.tsv.gz \
-o KEGG_pathways_out \
--no_regroup \
--map /home/adprc/miniconda3/envs/picrust2/lib/python3.8/site-packages/picrust2/default_files/pathway_mapfiles/KEGG_pathways_to_KO.tsv \
-p 2 &
```
```
nohup add_descriptions.py \
-i KEGG_pathways_out/path_abun_unstrat.tsv.gz \
--custom_map_table /home/adprc/miniconda3/envs/picrust2/lib/python3.8/site-packages/picrust2/default_files/description_mapfiles/KEGG_pathways_info.tsv.gz \
-o KEGG_pathways_out/path_abun_unstrat_descrip.tsv.gz &
```
# EC path
```
add_descriptions.py \
-i EC_metagenome_out/pred_metagenome_unstrat.tsv.gz \
-m EC \
-o EC_metagenome_out/path_abun_unstrat_descrip.tsv.gz
```
```
nohup add_descriptions.py \
  -i EC_metagenome_out/pred_metagenome_unstrat.tsv.gz \
  -m EC \
  -o EC_metagenome_out/pred_metagenome_unstrat_descrip.tsv.gz  &
```

# KO pathway - KO under Pathway
```
nohup add_descriptions.py \
  -i KO_metagenome_out/pred_metagenome_unstrat.tsv.gz \
  -m KO \
  -o KO_metagenome_out/pred_metagenome_unstrat_descrip.tsv.gz &
```


<p align="center"><a href="#fylab">Top</a></p>

# Key files relationship
* rep_seqs.qza: QIIME2 .qza 物件, 代表性序列（代表每個 feature 的 DNA 序列, 建立分類器、taxonomy 指派、畫 phylogeny
* taxonomy.qza: QIIME2 .qza 物件, 每條序列對應到的分類資訊（Domain → Species）, 繪製分類組成圖、群落分析
* otu_table.qza: QIIME2 .qza 物件, 每筆樣本與每條 feature 的 abundance 表（ASV/OTU 數量）,多樣性分析、群落結構比較
* dna-sequences.fasta: FASTA（非 QIIME2 格式）,rep_seqs.qza 轉成人可讀的序列格式, 外部工具使用（如 dehost、seqkit、bowtie2 等）
```
DADA2 / Deblur 處理原始 FASTQ 檔案
       │
       ├──→ rep_seqs.qza   ←──────→  (匯出為 fasta) → dna-sequences.fasta
       │                         ↑                     ↑
       ├──→ otu_table.qza        │                     │
       │                         │                     │
       └──→ rep_seqs.qza ──→ classify-sklearn → taxonomy.qza
```

# raw_data structure  [optional]
```
 . 
├── 科研案A
│   └── human
│       └── Stool
│       └── YF
│       └── Stomach
│       └── YF
│   └── metadata
├── 科研案B
│   └── metadata
│   └── human
│       └── Stool
│             └── Fastq 
│             └── Basespace 
│                    └── *BasespaceFiles
│                    └── *SampleTable
│                              └── SampleA.csv
│                              └── SampleB.csv …
│                    └── PopulationTable
│                              └── PopulationTable_abundance.csv
│                              └── PopulationTable_reads.csv
│             └── Qiime2 
│                    └── *Qiime_ver
│                            └── *SampleTable
│                            └── TabularTable
│                                    └── microbes_tabular_level_type_Qiimer_ver.csv
│                                    └── pathway_tabular__Qiimer_ver.csv
│                                    └── enzyme_tabular__Qiimer_ver.csv
│                            └── PopulationTable
│                                    └── PopulationTable_abundance.csv
│                                    └── PopulationTable_reads.csv  
│                                    └── PopulationTable_pathway.csv
│                                    └── PopulationTable_enzyme.csv
│                            └── EC_metagenome_out
│                                    └── pred_metagenome_unstrat_descrip.tsv.gz
│                            └── KEGG_pathways_out
│                                    └── path_abun_unstrat_descrip.tsv.gz
│                            └── KO_metagenome_out
│                            └── raw
│                                    └── otu_table.tsv
│                                    └── taxonomy.tsv
│                                    └── dehost_otu_table.tsv
│                                    └── dehost_taxonomy.tsv
│                                    └── dna-sequences.fasta
│                                    └── denoise_settings.txt
└── 商業案-廠商A 
```
