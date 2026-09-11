# PICRUSt2 vs PICRUSt2-SC 差異整理

> 建立日期：2026-09-11  
> 用途：記錄目前實測確認之 PICRUSt2 與 PICRUSt2-SC 輸出差異，作為後續流程拆分、腳本封裝與格式統一依據。

## 1. 整體原則

- 目前 `picrust2/` 與 `picrust2sc/` 是分析完成後的結果歸檔目錄，並非原始執行流程固定輸出路徑。
- 目標為：PICRUSt2 與 PICRUSt2-SC 對下游分析提供一致的檔名、欄位名稱與主要 ID 格式。
- PICRUSt2-SC 若有額外欄位可保留，但兩套流程共同存在的欄位應維持一致。
- 原生計算結果盡量不修改；只有工具相容性需要時進行暫時轉換，最終再統一成 canonical format。

## 2. KO metagenome output

### 2.1 `pred_metagenome_unstrat.tsv.gz`

PICRUSt2 與 PICRUSt2-SC 實測結果一致。

共同格式：

```text
function    Sample1    Sample2    ...
K00001      ...
K00002      ...
```

實測確認：

- 第一欄皆為 `function`
- KO ID 皆為 `Kxxxxx`
- 目前專案中兩者欄位數皆為 845
- 前幾個 KO abundance 數值一致

結論：

**不需要 normalization。**

Canonical KO ID：

```text
K00001
```

### 2.2 `pred_metagenome_contrib.tsv.gz`

PICRUSt2 與 PICRUSt2-SC 實測 schema 一致。

共同欄位：

```text
sample
function
taxon
taxon_abun
taxon_rel_abun
genome_function_count
taxon_function_abun
taxon_rel_function_abun
norm_taxon_function_contrib
```

實測確認：

- 兩者皆為 9 欄
- `function` 皆為 `Kxxxxx`
- 主要數值一致，僅見正常 floating-point 表示差異

例如：

```text
1.4604308788411422
1.46043087884114237
```

結論：

**目前 KO contribution 不需要 normalization。**

## 3. KO description output

### 3.1 共同 schema

兩者 `pred_metagenome_unstrat_descrip.tsv.gz` 皆為：

```text
function    description    Sample1    Sample2    ...
```

實測欄位數：

- PICRUSt2：846
- PICRUSt2-SC：846

因此 description 加入後的表格結構一致。

### 3.2 已確認差異

PICRUSt2：

```text
K00001    E1.1.1.1, adh; alcohol dehydrogenase [EC:1.1.1.1]
```

PICRUSt2-SC：

```text
ko:K00001    alcohol dehydrogenase [EC:1.1.1.1]
```

差異有兩個：

1. PICRUSt2-SC description output 的 `function` 會帶 `ko:` prefix。
2. description 文字內容不同：PICRUSt2 較完整，PICRUSt2-SC 較精簡。

建議：

- 最終 canonical KO ID 統一為 `Kxxxxx`
- `ko:` 只視為 annotation resource / annotation output 的格式差異
- description 內容不強制完全一致，只需保留各自 reference 提供的註解

因此最終若做 normalization：

```text
ko:K00001 -> K00001
```

但不要修改原始 `pred_metagenome_unstrat.tsv.gz`，因為原始 KO abundance output 本身已經一致。

## 4. PICRUSt2-SC KO description resource 特性

PICRUSt2-SC 環境中的：

```text
default_files/description_mapfiles/ko_name.txt.gz
```

使用：

```text
ko:K00001
ko:K00002
```

但 PICRUSt2-SC `pred_metagenome_unstrat.tsv.gz` 本身使用：

```text
K00001
K00002
```

因此進行 `add_descriptions.py -m KO` 時，需要處理 input ID 與 description map ID 的相容性。

這屬於 **annotation 階段的 compatibility issue**，不是 PICRUSt2-SC metagenome output schema 本身的問題。

## 5. EC 目前已知差異

目前已實測 PICRUSt2-SC EC 原始 function ID 為：

```text
EC:1.1.1.1
EC:1.1.1.100
...
```

但 PICRUSt2-SC 的：

```text
default_files/description_mapfiles/ec_name.txt.gz
```

使用：

```text
1.1.1.1
1.1.1.10
...
```

因此 PICRUSt2-SC 做 EC description 時，需要去除 `EC:` prefix 才能與 description map 配對。

建議 canonical EC ID：

```text
1.1.1.1
```

但 PICRUSt2 與 PICRUSt2-SC 的 EC unstrat / contrib / description 完整 schema 尚待正式比對後再定案。

## 6. KEGG pathway

目前只完成部分流程與工具相容性確認，尚未完成 PICRUSt2 vs PICRUSt2-SC 最終輸出 schema 的完整比對。

待確認項目：

- `path_abun_unstrat.tsv.gz`
- `path_abun_contrib.tsv.gz`
- `path_abun_unstrat_descrip.tsv.gz`
- pathway ID 格式
- header 與欄位數
- PICRUSt2-SC 是否存在額外欄位

注意：

KO description 所需的 `ko:` prefix 規則，不可直接套用到 KEGG pathway mapping。兩者使用不同 reference map，應分開確認。

## 7. QC

目前 QC script 已可依 Conda environment 自動判斷：

```text
picrust2   -> <project>/picrust2/qc/
picrust2sc -> <project>/picrust2sc/qc/
```

此版本區分可以保留，不需要強制合併成同一個實體目錄。

## 8. 目前 compatibility summary

| 模組 | PICRUSt2 | PICRUSt2-SC | 結論 |
|---|---|---|---|
| KO unstrat header | `function + samples` | 相同 | 相容 |
| KO unstrat ID | `Kxxxxx` | `Kxxxxx` | 相容 |
| KO unstrat 欄位數 | 845 | 845 | 相容 |
| KO contrib schema | 9 欄 | 9 欄 | 相容 |
| KO contrib ID | `Kxxxxx` | `Kxxxxx` | 相容 |
| KO description header | `function, description, samples...` | 相同 | 相容 |
| KO description ID | `Kxxxxx` | `ko:Kxxxxx` | 需最終統一 |
| KO description 文字 | 較完整 | 較精簡 | 可保留差異 |
| EC unstrat ID | 待完整確認 | `EC:x.x.x.x` | 待確認 |
| EC description map | bare EC | bare EC | SC description 需去 `EC:` |
| KEGG pathway | 待確認 | 待確認 | 尚未定案 |
| QC | version-specific output | version-specific output | 可保留 |

## 9. 後續規劃原則

後續正式拆 script 前，依序完成：

1. EC：unstrat / contrib / description 比對
2. KEGG：unstrat / contrib / description 比對
3. QC schema / 檔名確認
4. 建立完整 compatibility specification
5. 再決定哪些差異在 annotation 階段處理、哪些在 finalization 階段處理
6. 最後才拆成分步驟 script 並由總 wrapper 串接

目前建議的設計原則：

> 原生計算結果盡量不修改；工具相容性所需的 prefix 轉換只在必要階段暫時處理，最終輸出再統一 ID、欄位與檔名。

