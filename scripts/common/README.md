# Common Scripts

此資料夾放置 FYLab 的共用長任務管理工具。

目前包含：

- `run_in_tmux.sh`：以 tmux 執行長時間任務，並自動建立 log / status
- `check_tmux_jobs.sh`：查詢目前任務、最新任務與歷史任務

---

## 1. run_in_tmux.sh

### 用途

用於執行長時間任務，並自動完成：

- 建立 tmux session
- 建立 stdout / stderr log
- 建立 status 檔
- 記錄開始時間、結束時間與任務狀態
- 記錄當次使用的 `PRE_CMD`、`CMD` 或 `CMD_FILE`

### 主要參數

| 變數 | 說明 |
|---|---|
| `JOB_TYPE` | 任務類型，例如 `taxonomy`、`picrust2` |
| `PROJECT_DIR` | 專案根目錄，預設為目前目錄 |
| `JOB_NAME` | 任務名稱，用於區分此次用途 |
| `PRE_CMD` | 前置命令，可省略 |
| `CMD` | 主命令字串，與 `CMD_FILE` 擇一使用 |
| `CMD_FILE` | 主命令腳本檔案，與 `CMD` 擇一使用 |
| `RUN_IN_TMUX` | 是否以 tmux 執行，預設 `true` |
| `TIMEZONE` | 預設 `Asia/Taipei` |
| `LOG_DIR` | log 輸出資料夾，預設 `${PROJECT_DIR}/logs` |

### 使用規則

- `CMD` 與 `CMD_FILE` 只能二選一
- 若有設定 `PRE_CMD`，會先執行 `PRE_CMD`，再執行主任務
- 每次執行都會建立唯一 `JOB_ID`
- log 不會覆蓋舊紀錄

### 範例：使用 `CMD`

```bash
JOB_TYPE=taxonomy \
PROJECT_DIR=. \
JOB_NAME=gg2_nb \
PRE_CMD='mkdir -p taxonomy_results' \
CMD='qiime feature-classifier classify-sklearn \
  --i-reads rep-seqs.qza \
  --i-classifier gg2_classifier.qza \
  --o-classification taxonomy_results/taxonomy.qza \
  --p-n-jobs 8' \
./run_in_tmux.sh
```

### 範例：使用 CMD_FILE
```bash
JOB_TYPE=picrust2 \
PROJECT_DIR=. \
JOB_NAME=picrust2_run \
PRE_CMD='mkdir -p picrust2_results' \
CMD_FILE=./run_picrust2.sh \
./run_in_tmux.sh
```

### 執行後會建立的檔案
假設本次 JOB_ID 為：
```
taxonomy_20260417_103000
```
則會建立：
* logs/taxonomy_20260417_103000.stdout.log
* logs/taxonomy_20260417_103000.stderr.log
* logs/taxonomy_20260417_103000.status
* logs/taxonomy_20260417_103000.runner.sh

另外也會更新：
* logs/latest_taxonomy.stdout.log
* logs/latest_taxonomy.stderr.log
* logs/latest_taxonomy.status


## 2. run_in_tmux.sh
### 用途 
用於查詢由 run_in_tmux.sh 建立的任務。

支援：

* 查全部摘要
* 查全部歷史
* 查最新任務
* 查指定 session
* 回朔當次 PRE_CMD 與 CMD

### 主要參數

| 變數 | 說明 |
|---|---|
|`MODE`|`summary` / `all` / `latest` / `session`|
| `JOB_TYPE` | 篩選特定任務類型，例如 `taxonomy`、`picrust2` |
| `SESSION_NAME` | 查指定 session 時使用 |
| `SHOW_CMD` | 是否顯示完整 PRE_CMD 與 CMD_FULL，預設 false |
| `TAIL_STDOUT_LINES` | 顯示 stdout 最後幾行，預設 5 |
| `TAIL_STDERR_LINES` | 顯示 stderr 最後幾行，預設 5 |
| `SEARCH_ROOT` | 搜尋 status 檔的根目錄，預設 `.` |

### 使用範例

查全部摘要
```bash
./check_tmux_jobs.sh
```

查全部歷史詳細資訊
```bash
MODE=all ./check_tmux_jobs.sh
```

查最新任務
```bash
MODE=latest ./check_tmux_jobs.sh
```

查某類型最新任務
```bash
MODE=latest JOB_TYPE=taxonomy ./check_tmux_jobs.sh
```

查指定 session
```bash
MODE=session SESSION_NAME=taxonomy_20260417_103000 ./check_tmux_jobs.sh
```

顯示完整 PRE_CMD 與 CMD_FULL
```bash
MODE=session SESSION_NAME=taxonomy_20260417_103000 SHOW_CMD=true ./check_tmux_jobs.sh
```

## 3. 適合使用的情境

建議用於需要背景執行與查詢歷史紀錄的長任務，例如：

* qiime feature-classifier classify-sklearn
* qiime feature-classifier classify-consensus-vsearch
* PICRUSt2
* dehost
* 大型轉檔 / 匯出

不建議用於非常短的小工具腳本，例如：

* manifest 建立
* 檔名整理
* 小型資料檢查
