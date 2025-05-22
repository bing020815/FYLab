# FYLab
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


# QIIME2 - Preparation 分析前準備
對檢體資料清單絕對路徑輸出(更新排除掉'file_path.txt'列入清單)
```
find . -maxdepth 1 -type f ! -name 'file_path.txt' -exec realpath {} \; > file_path.txt
```

## 留下檢體的絕對路徑資料,按照儲存格式存成manifest.csv
## (按照順序: R1_forward, R2_reverse)
 sample-id,absolute-filepath,direction
 CH4773,/home/fyadmin/Desktop/Hong-Ying/CL/CH4773_S29_L001_R1_01.fastq.gz,forward
 CH4773,/home/fyadmin/Desktop/Hong-Ying/CL/CH4773_S29_L001_R2_001.fastq.gz,reverse

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
生成 manifest.csv
```
echo "sample-id,absolute-filepath,direction" > manifest.csv && awk -F'/' '{file=$NF; split(file, parts, "_"); sample=parts[1]; if (file ~ /R1/) dir="forward"; else if (file ~ /R2/) dir="reverse"; print sample","$0","dir}' file_path.txt >> manifest.csv
```

## 將表有csv轉成逗號分個的txt檔案 
### (fastq轉黨qiime2用)
```
cp manifest.csv manifest.txt
```

## 把逗號分隔的csv改成製表符\t的tsv 
### (metadata才需要用到)
```
sed 's/,/\t/g' manifest.csv > manifest.tsv
```

# Import Data and Preprocessing
## 進入qiime2環境
```
conda activate qiime2-2023.2
```

## FASTQ 匯入轉檔 QIIME 2 可使用的格式 (.qza)
### (need to wait process time, use 'top' command to check, press 'q' to leave)
### 會產出 paired-end-demux.qza 檔案
### 依照manifest.txt將兩段序列配對
```
nohup qiime tools import --type 'SampleData[PairedEndSequencesWithQuality]' --input-path manifest.txt --output-path paired-end-demux.qza --input-format PairedEndFastqManifestPhred33 &
```

## 轉成可視化報表
### 利用 qza 檔案，轉黨輸出成qzv，可以畫成可視化報表
### https://view.qiime2.org/
```
nohup qiime demux summarize --i-data paired-end-demux.qza --o-visualization paired-end-demux.qzv &
```

## Denoise 去除雜訊 [標準流程: 290-240]
### 將qza檔案去完雜訊後，輸出成： table.qza, stats.qza, rep-seqs.qza 
### (need to take a long process time, use 'top'/'htop' command to check, press 'q' to leave)
### --p-trim-left-* 的數值應根據使用的 primer 長度設定。
### --p-trunc-len-* 需保留足夠長度供 forward + reverse read 重疊（overlap）至少約 20～30 bp。
### 例如：290 + 240 = 530，V3-V4的 amplicon 長度為 約460 bp，則 overlap 為 70 bp，屬於合理值(overlap 通常建議 >20-30 bp)
### (將雙端測序數據處理為高品質的序列數據，並輸出相關結果)
### table.qzv - 可以看到Sample的取樣深度
```
nohup qiime dada2 denoise-paired \
--i-demultiplexed-seqs paired-end-demux.qza \
--p-trim-left-f 17 --p-trim-left-r 21 \
--p-trunc-len-f 290 --p-trunc-len-r 240 \
--p-n-threads 2 \
--o-representative-sequences rep-seqs.qza \
--o-table table.qza \
--o-denoising-stats stats.qza > nohup.out 2>&1 &
```
紀錄denoise設定
```
echo "--p-trim-left-f 17 --p-trim-left-r 21" >> denoise_settings.txt
echo "--p-trunc-len-f 290 --p-trunc-len-r 240" >> denoise_settings.txt
```

### 檢查stats檔案denosis狀態圖表
### 利用 qza 檔案，轉黨輸出成qzv，可以畫成可視化報表
### stats.qzv - 確認denoise中的資訊。
### https://view.qiime2.org/
```
qiime metadata tabulate \
  --m-input-file stats.qza \
  --o-visualization stats.qzv
```
### 直接看序列表長度[optional]
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
### 輸入去除雜訊後的table.qza，再輸出成biom format: feature-table.biom
```
qiime tools export \
--input-path table.qza \
--output-path phyloseq
```

## Biom 轉黨
### 將輸出成biom format的當案轉黨成otu_table.tsv 
### biom 記錄樣本與 OTU/ASV 之間的豐度矩陣
```
biom convert \
-i phyloseq/feature-table.biom \
-o phyloseq/otu_table.tsv \
--to-tsv
```

## 下載模型
### 下載 2023.09發布的Naive Bayes分類器，訓練用資料：GreenGenes 13_8，99% OTUs
```
wget https://data.qiime2.org/2023.9/common/gg-13-8-99-nb-classifier.qza
```

## 模型分類
### 透過已訓練好的模型gg-13-8-99-nb-classifier.qza來預測，並輸出taxonomy.qza
gg-13-8-99-nb-classifier.qza 要放在與 Fastq同層的資料夾，需要一些時間
```
nohup qiime feature-classifier classify-sklearn \
--i-classifier gg-13-8-99-nb-classifier.qza \
--i-reads rep-seqs.qza \
--o-classification taxonomy.qza \
--p-n-jobs 2 > nohup.out 2>&1 &
```

## qza格式轉檔
###  將分類好的輸出檔案taxonomy.qza轉黨為成taxonomy.tsv，存至phyloseq
```
qiime tools export \
--input-path taxonomy.qza \
--output-path phyloseq
```

### -- 轉換 rep-seqs.qza 檔案，產生dna-sequences.fasta，方便查詢Sequence --
### https://blast.ncbi.nlm.nih.gov/Blast.cgi?PAGE_TYPE=BlastSearch&BLAST_SPEC=MicrobialGenomes
```
qiime tools export \
  --input-path rep-seqs.qza \
  --output-path phyloseq
```

# Dehost 排除host基因
## 啟動host-tools package 

包含: bowtie2, samtools, seqkit 工具包 
https://useast.ensembl.org/index.html
```
conda activate host-tools
```
## 使用 Bowtie2 比對至[人類human/老鼠mouse/狗dog/貓cat]基因組
  ### human [pick one fits the project]
  ```
  nohup bowtie2 -x /home/adprc/host_genome/human_genome/host_genome_index \
         -f phyloseq/dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  ### mouse [pick one fits the project]
  ```
  nohup bowtie2 -x /home/adprc/host_genome/mouse_genome/host_genome_index \
         -f phyloseq/dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  ### dog [pick one fits the project]
  ```
  nohup bowtie2 -x /home/adprc/host_genome/dog_genome/host_genome_index \
         -f phyloseq/dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  ### cat [pick one fits the project]
  ```
  nohup bowtie2 -x /home/adprc/host_genome/cat_genome/host_genome_index \
         -f phyloseq/dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
  ### all(human, mouse, dog, cat, cattle, duck, goat, horse, pig, rabbit, turkey, chicken, sheep) [pick one fits the project]
  ```
  nohup bowtie2 -x /home/adprc/host_genome/all_genome/host_genome_index \
         -f phyloseq/dna-sequences.fasta \
         -S phyloseq/mapping_host_genome.sam \
         -p 2 \
         2> phyloseq/mapping_host_genome.txt &
  ```
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
  ```
  cat phyloseq/mapping_host_genome.txt
  ```
  ### 查看host基因佔比 [option2]
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
### Dehost pathway 流程前期準備: dehost_otu_table.tsv 轉檔 dehost_otu_table.biom
```
biom convert \
  -i phyloseq/filtered_host/dehost_otu_table.tsv \
  -o phyloseq/filtered_host/dehost_otu_table.biom \
  --to-hdf5 \
  --table-type="OTU table"
```
### Dehost pathway 流程前期準備: 把 dehost_otu_table.biom 匯入為 QIIME2 格式
```
qiime tools import \
  --input-path phyloseq/filtered_host/dehost_otu_table.biom \
  --type 'FeatureTable[Frequency]' \
  --input-format BIOMV210Format \
  --output-path phyloseq/filtered_host/dehost_otu_table.qza
```
### Dehost pathway 流程前期準備: 從原始 rep-seqs.qza 過濾出 dehost 用的 rep-seqs.qza
```
qiime feature-table filter-seqs \
  --i-data rep-seqs.qza \
  --i-table phyloseq/filtered_host/dehost_otu_table.qza \
  --o-filtered-data phyloseq/filtered_host/dehost_rep_seqs.qza
```
### Dehost pathway 流程前期準備: 匯出 過濾出 dehost 用的 rep-seqsfasta
```
qiime tools export \
  --input-path phyloseq/filtered_host/dehost_rep_seqs.qza \
  --output-path phyloseq/filtered_host/
```

# 畫圖
## KEGG Pathway 前期準備
### 4.Phylogeny Tree (此步驟要超級久，可以多線程設定)
dehost:[--i-sequences phyloseq/filtered_host/dehost_rep_seqs.qza]; not dehost:[--i-sequences rep-seqs.qza]
```
nohup qiime phylogeny align-to-tree-mafft-fasttree \
--i-sequences phyloseq/filtered_host/dehost_rep_seqs.qza \
--o-alignment aligned-rep-seqs.qza \
--o-masked-alignment masked-aligned-rep-seqs.qza \
--o-tree unrooted-tree.qza \
--o-rooted-tree rooted-tree.qza \
--p-n-threads 2 > nohup.out 2>&1 &
```

### 5.導出代表序列 (這步完成後，可以跳到 #PICRUSt2，直接啟動picrust2)
1. Input:
dehost:[--input-path phyloseq/filtered_host/dehost_rep_seqs.qza]; not dehost:[--input-path rep-seqs.qza]
2. Output:
dehost:[--output-path phyloseq/filtered_host/]; not dehost:[--output-path fastq1]
註: 產出dna-sequences.fasta 於 `phyloseq/filtered_host/` or `fastq1/`
```
qiime tools export --input-path phyloseq/filtered_host/dehost_rep_seqs.qza --output-path phyloseq/filtered_host/
```


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

## OTU Bar Plot [optional]
### 產出taxa-bar.qzv
```
qiime taxa barplot \
  --i-table table.qza \
  --m-metadata-file metadata.tsv \
  --i-taxonomy taxonomy.qza \
  --o-visualization taxa-bar.qzv
```

## OTU Percentage(如果有要跑bar圖就要接著跑這個)  [optional]
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

## Diversity  [optional]
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


# PICRUSt2 - Metabolism Pathway
## 啟動PICRUSt2 package
```
conda activate picrust2
```

## 1.Place reads into reference tree (此階段需跑一下)
-p 可改設定核心 能設定為4-6
dehost: [-s phyloseq/filtered_host/dna-sequences.fasta]
not dehost: [-s fastq1/dna-sequences.fasta]
```
nohup place_seqs.py \
-s phyloseq/filtered_host/dna-sequences.fasta \
-o out.tre \
-p 2 \
--intermediate intermediate/place_seqs &
```

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
dehost: [-i phyloseq/filtered_host/dehost_otu_table.biom]
not dehost: [-i phyloseq/feature-table.biom]
```
nohup metagenome_pipeline.py \
-i phyloseq/filtered_host/dehost_otu_table.biom \
-m marker_predicted_and_nsti.tsv.gz \
-f KO_predicted.tsv.gz \
-o KO_metagenome_out \
--strat_out &
```
EC
dehost: [-i phyloseq/filtered_host/dehost_otu_table.biom]
not dehost: [-i phyloseq/feature-table.biom]
```
nohup metagenome_pipeline.py \
-i phyloseq/filtered_host/dehost_otu_table.biom \
-m marker_predicted_and_nsti.tsv.gz \
-f EC_predicted.tsv.gz \
-o EC_metagenome_out \
--strat_out &
```


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


Python to unzip `.gz` file
```
gunzip path_abun_unstrat_descrip.tsv.gz
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
