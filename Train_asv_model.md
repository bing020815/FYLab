Train model for ASV prediction

# Naïve Bayesian: greengene1

## step 1. 匯入 99% OTU 的參考序列 fasta 為 .qza; 用於訓練nb模型參考使用
```
qiime tools import \
  --type 'FeatureData[Sequence]' \
  --input-path 99_otus.fasta \
  --output-path gg_13_8_99_RefSeq.qza
```

## step 1-1.（可選）裁切參考序列為 V3–V4 區段（341F–805R）
```
qiime feature-classifier extract-reads \
  --i-sequences gg_13_8_99_RefSeq.qza \
  --p-f-primer CCTACGGGNGGCWGCAG \
  --p-r-primer GACTACHVGGGTATCTAATCC \
  --o-reads gg_13_8_99_RefSeq_341-805.qza
```

## step 2. 匯入 taxonomy 為 .qza; 用於訓練nb模型參考使用
```
qiime tools import \
  --type 'FeatureData[Taxonomy]' \
  --input-path 99_otu_taxonomy.txt \
  --input-format HeaderlessTSVTaxonomyFormat \
  --output-path gg_13_8_99_Taxonomy.qza
```


## step 3.訓練nb模型，並且參考使用reads序列[可用已裁切參考序列]、taxanomy
```
qiime feature-classifier fit-classifier-naive-bayes \
  --i-reference-reads gg_13_8_99_RefSeq_341-805.qza \
  --i-reference-taxonomy gg_13_8_99_Taxonomy.qza \
  --o-classifier gg_13_8_99_NB_classifier_V3V4.qza
```


# vsearch Method: greengene1
## step 1. 使用classify-consensus-vsearch方法，並且參考指定使用reads序列[不需要裁切]、taxanomy
```
qiime feature-classifier classify-consensus-vsearch \
  --i-query dada2_output/representative_sequences.qza \
  --i-reference-reads gg_13_8_99_RefSeq.qza \
  --i-reference-taxonomy gg_13_8_99_Taxonomy.qza \
  --p-threads 8 \
  --verbose \
  --output-dir taxa
```


# Naïve Bayesian: SILVA

## step 1. 匯入 99% OTU 的參考序列 fasta 為 .qza; 用於訓練nb模型參考使用
```
qiime tools import \
  --type 'FeatureData[Sequence]' \
  --input-path dna-sequences.fasta \
  --output-path silva_RefSeq.qza
```

## step 1-1.（可選）裁切參考序列為 V3–V4 區段（341F–805R）
--p-trunc-len 可選，加上可避免過長尾端造成模型過擬合
```
qiime feature-classifier extract-reads \
  --i-sequences silva_RefSeq.qza \
  --p-f-primer CCTACGGGNGGCWGCAG \
  --p-r-primer GACTACHVGGGTATCTAATCC \
  --o-reads silva_RefSeq_341-805.qza
```

## step 2. 匯入 taxonomy 為 .qza
```
qiime tools import \
  --type 'FeatureData[Taxonomy]' \
  --input-path taxonomy.tsv \
  --input-format HeaderlessTSVTaxonomyFormat \
  --output-path silva_Taxonomy.qza
```


## step 3.訓練 Naive Bayes 模型
```
qiime feature-classifier fit-classifier-naive-bayes \
  --i-reference-reads silva_RefSeq_341-805.qza \
  --i-reference-taxonomy silva_Taxonomy.qza \
  --o-classifier silva_classifier_V3V4.qza
```


# vsearch Method: SILVA
## VSEARCH 比對方法（不需裁切）
```
qiime feature-classifier classify-consensus-vsearch \
  --i-query dada2_output/representative_sequences.qza \
  --i-reference-reads silva_RefSeq.qza \
  --i-reference-taxonomy silva_Taxonomy.qza \
  --p-threads 8 \
  --output-dir taxa_silva_vsearch
```





46+90+16+70+42+90+42+52+34+18=250