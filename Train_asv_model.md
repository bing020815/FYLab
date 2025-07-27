Train model for ASV prediction

# greengene1 Database
https://docs.qiime2.org/2023.2/data-resources/

## Naïve Bayesian: 
### step 1. 匯入 99% OTU 的參考序列 fasta 為 .qza; 用於訓練nb模型參考使用
```
qiime tools import \
  --type 'FeatureData[Sequence]' \
  --input-path gg/2023.2/gg_13_8_otus/rep_set/99_otus.fasta \
  --output-path gg/gg_13_8_99_RefSeq.qza
```

### step 1-1.（可選）裁切參考序列為 V3–V4 區段（341F–805R）
```
qiime feature-classifier extract-reads \
  --i-sequences gg/gg_13_8_99_RefSeq.qza \
  --p-f-primer CCTACGGGNGGCWGCAG \
  --p-r-primer GACTACHVGGGTATCTAATCC \
  --o-reads gg/gg_13_8_99_RefSeq_341-805.qza
```

### step 2. 匯入 taxonomy 為 .qza; 用於訓練nb模型參考使用
```
qiime tools import \
  --type 'FeatureData[Taxonomy]' \
  --input-path gg/2023.2/gg_13_8_otus/taxonomy/99_otu_taxonomy.txt \
  --input-format HeaderlessTSVTaxonomyFormat \
  --output-path gg/gg_13_8_99_Taxonomy.qza
```


### step 3.訓練nb模型，並且參考使用reads序列[可用已裁切參考序列]、taxanomy
```
qiime feature-classifier fit-classifier-naive-bayes \
  --i-reference-reads gg/gg_13_8_99_RefSeq_341-805.qza \
  --i-reference-taxonomy gg/gg_13_8_99_Taxonomy.qza \
  --o-classifier gg/gg_13_8_99_NB_classifier_V3V4.qza
```

### 關鍵模型、參考檔案路徑
```
/home/adprc/classifier/gg/gg_13_8_99_RefSeq.qza \
/home/adprc/classifier/gg/gg_13_8_99_Taxonomy.qzaa \
/home/adprc/classifier/gg/gg_13_8_99_NB_classifier_V3V4.qza \
```


## vsearch Method:
### step 1. 使用classify-consensus-vsearch方法，並且參考指定使用reads序列[不需要裁切]、taxanomy
```
qiime feature-classifier classify-consensus-vsearch \
  --i-query dada2_output/representative_sequences.qza \
  --i-reference-reads /home/adprc/classifier/gg/gg_13_8_99_RefSeq.qza \
  --i-reference-taxonomy /home/adprc/classifier/gg/gg_13_8_99_Taxonomy.qzaa \
  --p-threads 8 \
  --verbose \
  --output-dir taxa
```



# SILVA Database
https://docs.qiime2.org/2024.10/data-resources/

## Naïve Bayesian: 
### step 1. 匯入 99% OTU 的參考序列 fasta 為 .qza; 用於訓練nb模型參考使用
```
qiime tools import \
  --type 'FeatureData[Sequence]' \
  --input-path SILVA/2024.10/silva-138-99-seqs/data/dna-sequences.fasta \
  --output-path SILVA/silva_138_99_RefSeq.qza
```

### step 1-1.（可選）裁切參考序列為 V3–V4 區段（341F–805R）
--p-trunc-len 可選，加上可避免過長尾端造成模型過擬合
```
qiime feature-classifier extract-reads \
  --i-sequences SILVA/silva_138_99_RefSeq.qza \
  --p-f-primer CCTACGGGNGGCWGCAG \
  --p-r-primer GACTACHVGGGTATCTAATCC \
  --o-reads SILVA/silva_138_99_RefSeq_341-805.qza
```

### step 2. 匯入 taxonomy 為 .qza
```
qiime tools import \
  --type 'FeatureData[Taxonomy]' \
  --input-path SILVA/2024.10/silva-138-99-tax/data/taxonomy.tsv \
  --input-format HeaderlessTSVTaxonomyFormat \
  --output-path SILVA/silva_138_99_Taxonomy.qza
```


### step 3.訓練 Naive Bayes 模型
```
qiime feature-classifier fit-classifier-naive-bayes \
  --i-reference-reads SILVA/silva_138_99_RefSeq_341-805.qza \
  --i-reference-taxonomy SILVA/silva_138_99_Taxonomy.qza \
  --o-classifier silva_138_99_NB_classifier_V3V4.qza
```

### 關鍵模型、參考檔案路徑
```
/home/adprc/classifier/SILVA/silva_138_99_RefSeq.qza \
/home/adprc/classifier/SILVA/silva_138_99_Taxonomy.qzaa \
/home/adprc/classifier/SILVA/silva_138_99_NB_classifier_V3V4.qza \
```

## vsearch Method:
### VSEARCH 比對方法（不需裁切）
```
qiime feature-classifier classify-consensus-vsearch \
  --i-query dada2_output/representative_sequences.qza \
  --i-reference-reads /home/adprc/classifier/SILVA/silva_138_99_RefSeq.qza \ 
  --i-reference-taxonomy /home/adprc/classifier/SILVA/silva_138_99_Taxonomy.qzaa \
  --p-threads 8 \
  --output-dir taxa_silva_vsearch
```
