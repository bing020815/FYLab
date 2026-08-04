#!/usr/bin/env Rscript

# FYLab KTU2 terminal backend
#
# Default input (standard):
#   <project>/phyloseq/otu_table.tsv
#   <project>/phyloseq/taxonomy.tsv
#   <project>/phyloseq/dna-sequences.fasta
#
# Dehost input (--dehost):
#   <project>/phyloseq/filtered_host/dehost_otu_table.tsv
#   <project>/phyloseq/filtered_host/dehost_taxonomy.tsv
#   <project>/phyloseq/filtered_host/dna-sequences.fasta
#
# Core KTU results are shared among reference DB annotations, but standard and
# dehost analyses maintain separate core directories.

usage <- function(status = 0L) {
  cat(
    "Usage:\n",
    "  Rscript run_ktu2.R --project-dir DIR --db-ver DB [options]\n\n",
    "Required:\n",
    "  --project-dir DIR          Project root containing phyloseq/\n",
    "  --db-ver DB                User-supplied reference DB label\n\n",
    "Options:\n",
    "  --cores N                  CPU cores (default: 2)\n",
    "  --method METHOD            ktusp or klustering (default: ktusp)\n",
    "  --dehost                   Use phyloseq/filtered_host inputs\n",
    "  --force-rebuild            Recalculate KTU core even if it exists\n",
    "  --pscore BOOL              TRUE/FALSE (default: FALSE)\n",
    "  --step A,B                 Search steps (default: 5,10)\n",
    "  --search-min N|auto        Default: auto\n",
    "  --search-max N|auto        Default: auto\n",
    "  --split-tree-init N        ktusp default: 5\n",
    "  --split-lwrlim N           ktusp default: 2000\n",
    "  --split-reassemble N       ktusp default: 500\n",
    "  --taxonomy-consensus X     Consensus threshold (default: 0.5)\n",
    "  --ktu-id-prefix PREFIX     Default: KTU_\n",
    "  --help                     Show this help\n",
    sep = ""
  )
  quit(save = "no", status = status)
}

parse_bool <- function(x, name) {
  value <- tolower(trimws(as.character(x)))
  if (value %in% c("true", "t", "1", "yes", "y")) return(TRUE)
  if (value %in% c("false", "f", "0", "no", "n")) return(FALSE)
  stop(name, " must be TRUE or FALSE.")
}

parse_args <- function(args) {
  cfg <- list(
    project_dir = NULL,
    db_ver = NULL,
    cores = 2L,
    method = "ktusp",
    dehost = FALSE,
    force_rebuild = FALSE,
    pscore = FALSE,
    step = c(5L, 10L),
    search_min = NULL,
    search_max = NULL,
    split_tree_init = 5L,
    split_lwrlim = 2000L,
    split_reassemble = 500L,
    taxonomy_consensus = 0.5,
    ktu_id_prefix = "KTU_"
  )

  value_options <- c(
    "--project-dir", "--db-ver", "--cores", "--method", "--pscore",
    "--step", "--search-min", "--search-max", "--split-tree-init",
    "--split-lwrlim", "--split-reassemble", "--taxonomy-consensus",
    "--ktu-id-prefix"
  )

  i <- 1L
  while (i <= length(args)) {
    token <- args[[i]]
    if (token == "--help") usage(0L)
    if (token == "--dehost") {
      cfg$dehost <- TRUE
      i <- i + 1L
      next
    }
    if (token == "--force-rebuild") {
      cfg$force_rebuild <- TRUE
      i <- i + 1L
      next
    }
    if (!token %in% value_options) stop("Unknown option: ", token)
    if (i == length(args)) stop("Missing value after ", token)
    value <- args[[i + 1L]]

    if (token == "--project-dir") cfg$project_dir <- value
    if (token == "--db-ver") cfg$db_ver <- value
    if (token == "--cores") cfg$cores <- as.integer(value)
    if (token == "--method") cfg$method <- tolower(value)
    if (token == "--pscore") cfg$pscore <- parse_bool(value, "--pscore")
    if (token == "--step") {
      pieces <- strsplit(value, ",", fixed = TRUE)[[1]]
      cfg$step <- as.integer(trimws(pieces))
    }
    if (token == "--search-min") {
      cfg$search_min <- if (tolower(value) == "auto") NULL else as.integer(value)
    }
    if (token == "--search-max") {
      cfg$search_max <- if (tolower(value) == "auto") NULL else as.integer(value)
    }
    if (token == "--split-tree-init") cfg$split_tree_init <- as.integer(value)
    if (token == "--split-lwrlim") cfg$split_lwrlim <- as.integer(value)
    if (token == "--split-reassemble") cfg$split_reassemble <- as.integer(value)
    if (token == "--taxonomy-consensus") cfg$taxonomy_consensus <- as.numeric(value)
    if (token == "--ktu-id-prefix") cfg$ktu_id_prefix <- value
    i <- i + 2L
  }

  if (is.null(cfg$project_dir) || !nzchar(cfg$project_dir)) {
    stop("--project-dir is required.")
  }
  if (is.null(cfg$db_ver) || !nzchar(cfg$db_ver)) stop("--db-ver is required.")
  if (is.na(cfg$cores) || cfg$cores < 1L) stop("--cores must be >= 1.")
  if (!cfg$method %in% c("ktusp", "klustering")) {
    stop("--method must be ktusp or klustering.")
  }
  if (length(cfg$step) != 2L || anyNA(cfg$step) || any(cfg$step < 1L)) {
    stop("--step must contain two positive integers, e.g. 5,10.")
  }
  if (is.na(cfg$taxonomy_consensus) || cfg$taxonomy_consensus < 0 ||
      cfg$taxonomy_consensus > 1) {
    stop("--taxonomy-consensus must be between 0 and 1.")
  }
  if (!nzchar(cfg$ktu_id_prefix)) stop("--ktu-id-prefix cannot be empty.")
  cfg
}

safe_token <- function(x) {
  x <- gsub("[^A-Za-z0-9._-]+", "_", trimws(as.character(x)))
  x <- gsub("^[._-]+|[._-]+$", "", x)
  if (!nzchar(x)) stop("db_ver cannot be converted to a safe path token.")
  x
}

format_duration <- function(seconds) {
  seconds <- max(0, as.numeric(seconds))
  sprintf(
    "%02d:%02d:%05.2f",
    floor(seconds / 3600),
    floor((seconds %% 3600) / 60),
    seconds %% 60
  )
}

started_at <- Sys.time()
log_message <- function(text) {
  elapsed <- as.numeric(difftime(Sys.time(), started_at, units = "secs"))
  message(sprintf("[%s] %s", format_duration(elapsed), text))
}

read_feature_table <- function(path) {
  lines <- readLines(path, warn = FALSE)
  if (length(lines) == 0L) stop("Feature table is empty: ", path)

  header_candidates <- which(grepl("\\t", lines) & grepl(
    "^(#OTU ID|Feature ID|FeatureID|OTU ID)\\t",
    lines
  ))
  if (length(header_candidates) == 0L) {
    # Fallback: first non-comment tab-delimited line.
    header_candidates <- which(grepl("\\t", lines) & !grepl("^#", lines))
  }
  if (length(header_candidates) == 0L) {
    stop("Cannot locate the feature-table header in: ", path)
  }

  header_line <- header_candidates[[1]]
  df <- read.delim(
    path,
    header = TRUE,
    sep = "\t",
    skip = header_line - 1L,
    quote = "",
    comment.char = "",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  if (ncol(df) < 2L) stop("Feature table requires an ID column and samples.")
  colnames(df)[[1]] <- "FeatureID"
  df$FeatureID <- as.character(df$FeatureID)
  if (anyNA(df$FeatureID) || any(!nzchar(df$FeatureID))) {
    stop("Feature table contains empty Feature IDs.")
  }
  if (anyDuplicated(df$FeatureID)) stop("Feature table contains duplicated IDs.")

  sample_columns <- setdiff(colnames(df), "FeatureID")
  for (column in sample_columns) {
    original <- df[[column]]
    numeric_values <- suppressWarnings(as.numeric(original))
    invalid <- is.na(numeric_values) & !is.na(original) & nzchar(trimws(as.character(original)))
    if (any(invalid)) stop("Non-numeric abundance values in sample column: ", column)
    numeric_values[is.na(numeric_values)] <- 0
    df[[column]] <- numeric_values
  }
  list(data = df, sample_columns = sample_columns)
}

read_taxonomy <- function(path) {
  df <- read.delim(
    path,
    header = TRUE,
    sep = "\t",
    quote = "",
    comment.char = "",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  id_candidates <- c("Feature ID", "FeatureID", "#OTU ID", "OTU ID")
  id_col <- id_candidates[id_candidates %in% colnames(df)][1]
  if (is.na(id_col)) stop("taxonomy.tsv has no recognised Feature ID column.")
  if (!"Taxon" %in% colnames(df)) stop("taxonomy.tsv must contain a Taxon column.")
  colnames(df)[colnames(df) == id_col] <- "FeatureID"
  df$FeatureID <- as.character(df$FeatureID)
  if (anyDuplicated(df$FeatureID)) stop("taxonomy.tsv contains duplicated Feature IDs.")
  df
}

parse_taxonomy_ranks <- function(taxon_vector) {
  ranks <- c(
    Kingdom = "k__", Domain = "d__", Phylum = "p__", Class = "c__",
    Order = "o__", Family = "f__", Genus = "g__", Species = "s__"
  )
  # Domain supersedes Kingdom when d__ is present. Keep output hierarchy stable.
  output_ranks <- c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  out <- matrix(NA_character_, nrow = length(taxon_vector), ncol = length(output_ranks))
  colnames(out) <- output_ranks

  for (i in seq_along(taxon_vector)) {
    taxon <- as.character(taxon_vector[[i]])
    if (is.na(taxon) || !nzchar(trimws(taxon))) next
    tokens <- trimws(strsplit(taxon, ";", fixed = TRUE)[[1]])
    for (token in tokens) {
      prefix <- sub("^([a-zA-Z]__).*$", "\\1", token)
      if (identical(prefix, "d__") || identical(prefix, "k__")) {
        out[i, "Kingdom"] <- token
      } else if (identical(prefix, "p__")) out[i, "Phylum"] <- token
      else if (identical(prefix, "c__")) out[i, "Class"] <- token
      else if (identical(prefix, "o__")) out[i, "Order"] <- token
      else if (identical(prefix, "f__")) out[i, "Family"] <- token
      else if (identical(prefix, "g__")) out[i, "Genus"] <- token
      else if (identical(prefix, "s__")) out[i, "Species"] <- token
    }
  }
  as.data.frame(out, stringsAsFactors = FALSE, check.names = FALSE)
}

normalise_taxon <- function(x) {
  x <- trimws(as.character(x))
  x[is.na(x)] <- ""
  suffix <- sub("^[a-zA-Z]__", "", x)
  invalid <- tolower(suffix) %in% c(
    "", "na", "nan", "none", "null", "unassigned", "unclassified", "unknown"
  )
  x[invalid] <- NA_character_
  x
}

consensus_taxon <- function(values, threshold) {
  values <- normalise_taxon(values)
  values <- values[!is.na(values)]
  if (length(values) == 0L) {
    return(list(label = "Unassigned", support = NA_real_, assigned_n = 0L))
  }
  counts <- sort(table(values), decreasing = TRUE)
  support <- as.numeric(counts[[1]]) / length(values)
  label <- if (support >= threshold) names(counts)[[1]] else "Unassigned"
  list(label = label, support = support, assigned_n = length(values))
}

write_fasta <- function(sequences, path) {
  con <- file(path, open = "wt")
  on.exit(close(con), add = TRUE)
  for (i in seq_along(sequences)) {
    writeLines(c(paste0(">", names(sequences)[[i]]), as.character(sequences[[i]])), con)
  }
}

read_fasta_ids <- function(path) {
  seqs <- Biostrings::readDNAStringSet(path, use.names = TRUE)
  ids <- sub("[[:space:]].*$", "", names(seqs))
  names(seqs) <- ids
  if (anyDuplicated(ids)) stop("FASTA contains duplicated sequence IDs.")
  seqs
}

write_manifest <- function(values, path) {
  df <- data.frame(
    parameter = names(values),
    value = vapply(values, as.character, character(1)),
    stringsAsFactors = FALSE
  )
  write.table(df, path, sep = "\t", quote = FALSE, row.names = FALSE)
}

read_manifest <- function(path) {
  df <- read.delim(path, sep = "\t", check.names = FALSE, stringsAsFactors = FALSE)
  stats::setNames(df$value, df$parameter)
}

cfg <- tryCatch(parse_args(commandArgs(trailingOnly = TRUE)), error = function(e) {
  message("ERROR: ", conditionMessage(e))
  usage(1L)
})

required_packages <- c("KTU2", "Biostrings")
missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]
if (length(missing_packages) > 0L) {
  stop("Missing required R packages: ", paste(missing_packages, collapse = ", "))
}

project_dir <- normalizePath(cfg$project_dir, mustWork = TRUE)
safe_db_ver <- safe_token(cfg$db_ver)
variant <- if (cfg$dehost) "dehost" else "standard"

if (cfg$dehost) {
  input_dir <- file.path(project_dir, "phyloseq", "filtered_host")
  table_path <- file.path(input_dir, "dehost_otu_table.tsv")
  taxonomy_path <- file.path(input_dir, "dehost_taxonomy.tsv")
  fasta_path <- file.path(input_dir, "dna-sequences.fasta")
} else {
  input_dir <- file.path(project_dir, "phyloseq")
  table_path <- file.path(input_dir, "otu_table.tsv")
  taxonomy_path <- file.path(input_dir, "taxonomy.tsv")
  fasta_path <- file.path(input_dir, "dna-sequences.fasta")
}

for (path in c(table_path, taxonomy_path, fasta_path)) {
  if (!file.exists(path)) stop("Required input file does not exist: ", path)
}

variant_dir <- file.path(project_dir, "ktu", variant)
core_dir <- file.path(variant_dir, "core")
annotation_dir <- file.path(variant_dir, "annotation", safe_db_ver)
dir.create(core_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(annotation_dir, recursive = TRUE, showWarnings = FALSE)

core_paths <- list(
  counts = file.path(core_dir, "ktu_counts.tsv"),
  mapping = file.path(core_dir, "asv_to_ktu.tsv"),
  id_mapping = file.path(core_dir, "ktu_id_mapping.tsv"),
  sequences = file.path(core_dir, "ktu_representative_sequences.fasta"),
  kmer = file.path(core_dir, "kmer_table.tsv"),
  manifest = file.path(core_dir, "core_manifest.tsv")
)

input_table_md5 <- unname(tools::md5sum(table_path))
input_fasta_md5 <- unname(tools::md5sum(fasta_path))
expected_manifest <- c(
  variant = variant,
  input_table_md5 = input_table_md5,
  input_fasta_md5 = input_fasta_md5,
  method = cfg$method,
  pscore = as.character(cfg$pscore),
  step = paste(cfg$step, collapse = ","),
  search_min = if (is.null(cfg$search_min)) "auto" else as.character(cfg$search_min),
  search_max = if (is.null(cfg$search_max)) "auto" else as.character(cfg$search_max),
  split_tree_init = as.character(cfg$split_tree_init),
  split_lwrlim = as.character(cfg$split_lwrlim),
  split_reassemble = as.character(cfg$split_reassemble),
  ktu_id_prefix = cfg$ktu_id_prefix
)

core_required <- unlist(core_paths[c("counts", "mapping", "id_mapping", "sequences", "manifest")])
core_exists <- all(file.exists(core_required))
reuse_core <- core_exists && !cfg$force_rebuild

if (reuse_core) {
  existing_manifest <- read_manifest(core_paths$manifest)
  comparable_names <- intersect(names(expected_manifest), names(existing_manifest))
  mismatch <- comparable_names[
    expected_manifest[comparable_names] != existing_manifest[comparable_names]
  ]
  missing_manifest_fields <- setdiff(names(expected_manifest), names(existing_manifest))
  if (length(mismatch) > 0L || length(missing_manifest_fields) > 0L) {
    stop(
      "Existing KTU core does not match current input/settings. ",
      "Use --force-rebuild after confirming the change. Mismatch: ",
      paste(c(mismatch, missing_manifest_fields), collapse = ", ")
    )
  }
}

message(strrep("=", 72))
message("FYLab KTU2 analysis")
message("Project       : ", project_dir)
message("Variant       : ", variant)
message("Reference DB  : ", cfg$db_ver)
message("Feature table : ", table_path)
message("Taxonomy      : ", taxonomy_path)
message("FASTA         : ", fasta_path)
message("Core action   : ", if (reuse_core) "reuse" else "build")
message(strrep("=", 72))

feature_input <- read_feature_table(table_path)
feature_table <- feature_input$data
sample_columns <- feature_input$sample_columns
fasta <- read_fasta_ids(fasta_path)

if (!setequal(feature_table$FeatureID, names(fasta))) {
  only_table <- setdiff(feature_table$FeatureID, names(fasta))
  only_fasta <- setdiff(names(fasta), feature_table$FeatureID)
  stop(
    "Feature table and FASTA IDs differ. Only in table: ", length(only_table),
    "; only in FASTA: ", length(only_fasta),
    ". Examples table-only: ", paste(head(only_table, 5L), collapse = ", "),
    "; FASTA-only: ", paste(head(only_fasta, 5L), collapse = ", ")
  )
}

# Deterministic order follows FASTA.
feature_table <- feature_table[match(names(fasta), feature_table$FeatureID), , drop = FALSE]
feature_ids <- feature_table$FeatureID

if (!reuse_core) {
  log_message(sprintf(
    "Running KTU2 on %d ASVs and %d samples...",
    length(feature_ids), length(sample_columns)
  ))

  common_args <- list(
    repseq = fasta_path,
    feature.table = feature_table,
    write.fasta = FALSE,
    cores = cfg$cores,
    pscore = cfg$pscore,
    step = cfg$step,
    search.min = cfg$search_min,
    search.max = cfg$search_max
  )

  if (cfg$method == "ktusp") {
    common_args <- c(common_args, list(
      split_tree_init = cfg$split_tree_init,
      split_lwrlim = cfg$split_lwrlim,
      split_reassemble = cfg$split_reassemble
    ))
    ktu_result <- do.call(KTU2::ktusp, common_args)
  } else {
    ktu_result <- do.call(KTU2::klustering, common_args)
  }

  required_names <- c("KTU.table", "ReqSeq", "clusters")
  if (!all(required_names %in% names(ktu_result))) {
    stop("Unexpected KTU2 result. Missing: ",
         paste(setdiff(required_names, names(ktu_result)), collapse = ", "))
  }

  ktu_counts <- as.data.frame(ktu_result$KTU.table, check.names = FALSE)
  original_ktu_ids <- rownames(ktu_counts)
  if (is.null(original_ktu_ids) || any(!nzchar(original_ktu_ids))) {
    stop("KTU2 output lacks valid KTU row names.")
  }
  ktu_counts <- ktu_counts[, sample_columns, drop = FALSE]

  id_width <- max(4L, nchar(as.character(nrow(ktu_counts))))
  ktu_ids <- sprintf(
    paste0(cfg$ktu_id_prefix, "%0", id_width, "d"),
    seq_len(nrow(ktu_counts))
  )
  rownames(ktu_counts) <- ktu_ids

  ktu_id_mapping <- data.frame(
    KTU_ID = ktu_ids,
    KTU_Hash = original_ktu_ids,
    stringsAsFactors = FALSE
  )

  raw_clusters <- ktu_result$clusters
  cluster_feature_ids <- if (is.null(names(raw_clusters))) feature_ids else names(raw_clusters)
  if (!setequal(cluster_feature_ids, feature_ids)) {
    stop("KTU cluster names differ from input Feature IDs.")
  }
  clusters <- as.integer(raw_clusters)
  cluster_levels <- sort(unique(clusters))
  if (length(cluster_levels) != length(ktu_ids)) {
    stop("Cluster-label count differs from KTU-table row count.")
  }
  cluster_to_ktu <- stats::setNames(ktu_ids, cluster_levels)
  mapping_df <- data.frame(
    ASV_ID = cluster_feature_ids,
    cluster_number = clusters,
    KTU_ID = unname(cluster_to_ktu[as.character(clusters)]),
    stringsAsFactors = FALSE
  )
  mapping_df <- mapping_df[match(feature_ids, mapping_df$ASV_ID), , drop = FALSE]

  ktu_sequences <- ktu_result$ReqSeq
  sequence_names <- names(ktu_sequences)
  if (!is.null(sequence_names) && setequal(sequence_names, original_ktu_ids)) {
    names(ktu_sequences) <- ktu_ids[match(sequence_names, original_ktu_ids)]
    ktu_sequences <- ktu_sequences[match(ktu_ids, names(ktu_sequences))]
  } else if (length(ktu_sequences) == length(ktu_ids)) {
    names(ktu_sequences) <- ktu_ids
  } else {
    stop("Cannot align representative KTU sequences to KTU IDs.")
  }

  input_totals <- colSums(feature_table[, sample_columns, drop = FALSE])
  output_totals <- colSums(ktu_counts[, sample_columns, drop = FALSE])
  if (!isTRUE(all.equal(
    as.numeric(input_totals), as.numeric(output_totals),
    tolerance = 0, check.attributes = FALSE
  ))) stop("Read-count conservation failed after KTU aggregation.")

  write.table(
    data.frame(FeatureID = rownames(ktu_counts), ktu_counts, check.names = FALSE),
    core_paths$counts, sep = "\t", quote = FALSE, row.names = FALSE
  )
  write.table(
    mapping_df, core_paths$mapping,
    sep = "\t", quote = FALSE, row.names = FALSE
  )
  write.table(
    ktu_id_mapping, core_paths$id_mapping,
    sep = "\t", quote = FALSE, row.names = FALSE
  )
  write_fasta(ktu_sequences, core_paths$sequences)

  if ("kmer.table" %in% names(ktu_result)) {
    kmer_df <- data.frame(kmer = rownames(ktu_result$kmer.table),
                          ktu_result$kmer.table, check.names = FALSE)
    write.table(
      kmer_df, core_paths$kmer,
      sep = "\t", quote = FALSE, row.names = FALSE
    )
  }

  manifest <- c(
    expected_manifest,
    KTU2_version = as.character(utils::packageVersion("KTU2")),
    R_version = R.version.string,
    input_feature_count = length(feature_ids),
    input_sample_count = length(sample_columns),
    output_ktu_count = nrow(ktu_counts),
    built_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %z")
  )
  write_manifest(manifest, core_paths$manifest)
  log_message("KTU core written successfully.")
} else {
  log_message("Reusing existing KTU core.")
}

# Load shared core for reference-DB-specific annotation.
ktu_counts_df <- read.delim(
  core_paths$counts, sep = "\t", check.names = FALSE, stringsAsFactors = FALSE
)
colnames(ktu_counts_df)[[1]] <- "KTU_ID"
mapping_df <- read.delim(
  core_paths$mapping, sep = "\t", check.names = FALSE, stringsAsFactors = FALSE
)
ktu_id_mapping <- read.delim(
  core_paths$id_mapping, sep = "\t", check.names = FALSE, stringsAsFactors = FALSE
)

taxonomy_df <- read_taxonomy(taxonomy_path)
rank_df <- parse_taxonomy_ranks(taxonomy_df$Taxon)
taxonomy_ranked <- cbind(
  taxonomy_df[, c("FeatureID", "Taxon"), drop = FALSE],
  rank_df
)
if ("Confidence" %in% colnames(taxonomy_df)) {
  taxonomy_ranked$Confidence <- suppressWarnings(as.numeric(taxonomy_df$Confidence))
}

missing_taxonomy_ids <- setdiff(mapping_df$ASV_ID, taxonomy_ranked$FeatureID)
extra_taxonomy_ids <- setdiff(taxonomy_ranked$FeatureID, mapping_df$ASV_ID)
if (length(missing_taxonomy_ids) > 0L) {
  warning(
    length(missing_taxonomy_ids),
    " core ASVs are absent from taxonomy.tsv and will be treated as Unassigned."
  )
}
if (length(extra_taxonomy_ids) > 0L) {
  log_message(sprintf(
    "%d taxonomy rows are not present in this KTU core and will be ignored.",
    length(extra_taxonomy_ids)
  ))
}

taxonomy_aligned <- taxonomy_ranked[
  match(mapping_df$ASV_ID, taxonomy_ranked$FeatureID),
  , drop = FALSE
]
taxonomy_aligned$FeatureID <- mapping_df$ASV_ID
rank_columns <- c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
ktu_ids <- ktu_counts_df$KTU_ID

log_message("Building reference-DB-specific KTU taxonomy consensus...")
taxonomy_rows <- vector("list", length(ktu_ids))
for (i in seq_along(ktu_ids)) {
  ktu_id <- ktu_ids[[i]]
  member_idx <- which(mapping_df$KTU_ID == ktu_id)
  row <- list(
    KTU_ID = ktu_id,
    KTU_Hash = ktu_id_mapping$KTU_Hash[match(ktu_id, ktu_id_mapping$KTU_ID)],
    member_asv_count = length(member_idx)
  )
  hierarchy_failed <- FALSE
  for (rank in rank_columns) {
    consensus <- consensus_taxon(
      taxonomy_aligned[[rank]][member_idx],
      cfg$taxonomy_consensus
    )
    label <- consensus$label
    if (hierarchy_failed || identical(label, "Unassigned")) {
      label <- "Unassigned"
      hierarchy_failed <- TRUE
    }
    row[[rank]] <- label
    row[[paste0(rank, "_support")]] <- consensus$support
    row[[paste0(rank, "_assigned_asv_n")]] <- consensus$assigned_n
  }
  taxonomy_rows[[i]] <- row
}

taxonomy_summary <- do.call(rbind, lapply(taxonomy_rows, function(row) {
  as.data.frame(row, stringsAsFactors = FALSE, check.names = FALSE)
}))

annotation_basic <- taxonomy_summary[, c("KTU_ID", "KTU_Hash", rank_columns), drop = FALSE]
ktu_abundance_taxonomy <- merge(
  annotation_basic,
  ktu_counts_df,
  by = "KTU_ID",
  sort = FALSE,
  all.x = TRUE
)
ktu_abundance_taxonomy <- ktu_abundance_taxonomy[
  match(ktu_ids, ktu_abundance_taxonomy$KTU_ID),
  , drop = FALSE
]

annotation_paths <- list(
  taxonomy = file.path(annotation_dir, "ktu_taxonomy.tsv"),
  combined = file.path(
    annotation_dir,
    paste0("ktu_abundance_taxonomy_", safe_db_ver, ".tsv")
  ),
  summary = file.path(annotation_dir, "annotation_summary.tsv")
)

write.table(
  taxonomy_summary,
  annotation_paths$taxonomy,
  sep = "\t", quote = FALSE, row.names = FALSE, na = ""
)
write.table(
  ktu_abundance_taxonomy,
  annotation_paths$combined,
  sep = "\t", quote = FALSE, row.names = FALSE, na = ""
)

annotation_summary <- c(
  reference_db = cfg$db_ver,
  variant = variant,
  taxonomy_file = taxonomy_path,
  taxonomy_file_md5 = unname(tools::md5sum(taxonomy_path)),
  taxonomy_consensus = cfg$taxonomy_consensus,
  core_manifest = core_paths$manifest,
  core_reused = reuse_core,
  core_asv_count = nrow(mapping_df),
  taxonomy_asv_count = nrow(taxonomy_df),
  missing_core_asv_taxonomy_count = length(missing_taxonomy_ids),
  ignored_extra_taxonomy_count = length(extra_taxonomy_ids),
  output_ktu_count = nrow(taxonomy_summary),
  annotated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %z")
)
write_manifest(annotation_summary, annotation_paths$summary)

elapsed <- as.numeric(difftime(Sys.time(), started_at, units = "secs"))
message("")
message(strrep("=", 72))
message("KTU2 workflow completed successfully")
message("Variant          : ", variant)
message("Reference DB     : ", cfg$db_ver)
message("KTU count        : ", nrow(ktu_counts_df))
message("Core directory   : ", core_dir)
message("Annotation dir   : ", annotation_dir)
message("Elapsed          : ", format_duration(elapsed))
message(strrep("=", 72))
