#!/usr/bin/env Rscript
# Project the Risk Filtering sheet to a normalized JSON payload for the
# dashboard. Reads the cached snapshot from the sibling wc-threat-assessment
# repo so we don't re-hit the Google Sheet at mockup time. The real build
# will refresh on demand.

suppressPackageStartupMessages({
  library(jsonlite)
  library(data.table)
})

# Look for the cached sheet snapshot. Env var wins; otherwise try a few
# common sibling locations. Override:
#   WC_RISK_FILTERING_RDS=/path/to/risk_filtering.rds Rscript scripts/extract_pathogens.R
candidates <- c(
  Sys.getenv("WC_RISK_FILTERING_RDS"),
  "../wc-threat-assessment/narratives/_cache/risk_filtering.rds",
  "/mnt/c/Users/jlessler/Dropbox/EpiModelingWorking/wc-threat-assessment/narratives/_cache/risk_filtering.rds"
)
src <- Find(function(p) nzchar(p) && file.exists(p), candidates)
if (is.null(src)) stop(
  "Couldn't find risk_filtering.rds. Set WC_RISK_FILTERING_RDS or run from a ",
  "sibling of wc-threat-assessment.")
src <- normalizePath(src, mustWork = TRUE)
dt  <- readRDS(src)
message("Loaded snapshot: ", src)

yn  <- function(x) tolower(trimws(as.character(x))) %in% "yes"
yn3 <- function(x) {
  v <- tolower(trimws(as.character(x)))
  fifelse(v == "yes", "yes",
    fifelse(v == "no", "no", NA_character_))
}
one <- function(x) {
  v <- suppressWarnings(as.numeric(x))
  !is.na(v) & v == 1
}
# googlesheets4 returns list-cols for mixed/empty cells; flatten before coerce.
num <- function(x) {
  if (is.list(x)) x <- vapply(x, function(v) if (length(v) == 0) NA_real_
                              else suppressWarnings(as.numeric(v[[1]])),
                              numeric(1))
  suppressWarnings(as.numeric(x))
}

out <- data.table(
  name                    = dt$Pathogen,
  endemic                 = yn(dt$Endemicity),
  priority_label          = dt$`Priority Pathogen?`,
  inputer                 = dt$Inputer,
  reviewer                = dt$Reviewer,

  # Screening flags (tri-state)
  can_establish           = yn3(dt$`[1] Establish local transmission?`),
  wc_elev_transmit        = yn3(dt$`[2] Increased WC transmission?`),
  imports_gt_5pct         = yn3(dt$`[3] Import significant vs. prevalence`),
  dead_end_host           = yn3(dt$`[4] Humans dead end hosts`),
  vector_absent           = yn3(dt$`[5] Lack competent vector`),
  healthcare_only         = yn3(dt$`[6] Healthcare associated`),

  # Parameters
  R0                      = num(dt$R0),
  WC_R0                   = num(dt$`WC R0`),
  k                       = num(dt$k),
  g                       = num(dt$g),
  S                       = num(dt$S),
  susceptibility          = num(dt$`[11] Susceptibility`),
  parameters_complete     = yn(dt$`Parameters complete?`),

  # Computed
  excess_importation      = num(dt$`Excess importation`),
  presence_at_wc          = num(dt$`Presence at WC events`),
  wc_outbreak_size        = num(dt$`WC Per case outbreak size`),
  wc_outbreak_size_sd     = num(dt$`WC Per case outbreak size (SD)`),
  nonwc_outbreak_size     = num(dt$`Non-WC Per case outbreak size`),
  nonwc_outbreak_size_sd  = num(dt$`Non-WC Per case outbreak size (SD)`),
  excess_outbreak_cases   = num(dt$`Expected excess cases`),
  excess_outbreak_sd      = num(dt$`Excess outbreak size (SD)`),
  impact                  = num(dt$Impact),
  risk_value              = num(dt$`Risk value`),

  # Costs / burden
  total_cost_per_case     = num(dt$`Total cost per case (USD)`),
  total_cost_per_infection= num(dt$`Total cost per infection (USD)`),
  dalys_per_case          = num(dt$`[8] DALY Lost per case`),
  symp_proportion         = num(dt$`Symp proportion`),
  incidence_per_100k      = num(dt$`Incidence per 100,000`),

  # Decision rollup flags (one-hot)
  excl_endemic_no_wc_transmit   = one(dt$`EXCLUDE: No excess WC transmission, imports not significant vs local prevalence`),
  excl_endemic_no_acute         = one(dt$`EXCLUDE: No acute sequelae of infection`),
  excl_endemic_risk_below       = one(dt[[grep("^EXCLUDE: Risk < threshold", names(dt))[1]]]),
  incl_endemic_risk_above       = one(dt[[grep("^INCLUDE: Risk > th",       names(dt))[1]]]),
  not_excluded_endemic          = one(dt[[grep("^NOT YET EXCLUDED",         names(dt))[1]]]),
  excl_nonendemic_no_imports    = one(dt$`EXCLUDE: Expected imports = 0`),
  excl_nonendemic_risk_below    = one(dt[[grep("^EXCLUDE: Risk < threshold", names(dt))[2]]]),
  incl_nonendemic_can_establish = one(dt$`INCLUDE: Can establish local transmission and import > 0`),
  incl_nonendemic_risk_above    = one(dt[[grep("^INCLUDE: Risk > th",       names(dt))[2]]]),
  not_excluded_nonendemic       = one(dt[[grep("^NOT YET EXCLUDED",         names(dt))[2]]])
)

out <- out[!is.na(name) & nzchar(name)]
setorder(out, name)

# Decision tag: trust the curator-set rollup column `Priority Pathogen?`
# rather than re-deriving from the EXCLUDE/INCLUDE flag columns. The flags
# are often incomplete even when the rollup is decisive (e.g. Legionella's
# rollup is "Excluded" but no specific EXCLUDE: flag is set). The flags
# still drive the *reason* text in the UI; this just decides the bucket.
lbl <- tolower(trimws(as.character(out$priority_label)))
decision <- fifelse(lbl == "included",     "priority",
            fifelse(lbl == "excluded",     "excluded",
            fifelse(lbl == "not excluded", "under_eval", "unassessed")))
out[, decision := decision]

# Pull the risk threshold Q from the sheet (cell U1:V1 = "Threshold: 25000")
# directly via googlesheets4, since the cached RDS was loaded with skip=1
# and dropped that header row. Falls back to 25000 if the sheet isn't
# reachable (e.g. running offline / no cached auth).
threshold_q <- tryCatch({
  suppressPackageStartupMessages(library(googlesheets4))
  googlesheets4::gs4_auth(email = "justin.lessler@gmail.com", cache = TRUE)
  hdr <- googlesheets4::read_sheet(
    "1yOX57P2DUxP-Td83W3zSq2MgF2keOftd3_Ejk8cGvYo",
    sheet = "Risk Filtering", range = "U1:V1", col_names = FALSE)
  as.numeric(hdr[[2]][[1]])
}, error = function(e) { message("Couldn't fetch threshold; using 25000."); 25000 })

# Snapshot metadata; surfaces in the masthead "data as of" line.
meta <- list(
  source       = "Risk Filtering sheet, ID 1yOX57P2DUxP-Td83W3zSq2MgF2keOftd3_Ejk8cGvYo",
  snapshot_at  = format(file.info(src)$mtime, "%Y-%m-%d"),
  n_pathogens  = nrow(out),
  threshold_q  = threshold_q,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z")
)

payload <- list(meta = meta, pathogens = out)

dir.create("data", showWarnings = FALSE)
writeLines(toJSON(payload, na = "null", auto_unbox = TRUE, pretty = TRUE),
           "data/pathogens.json")

cat(sprintf("Wrote data/pathogens.json (%d pathogens, snapshot %s)\n",
            nrow(out), meta$snapshot_at))
cat(sprintf("Decision tags: %s\n",
            paste(sprintf("%s=%d", names(table(decision)), table(decision)),
                  collapse = "  ")))
