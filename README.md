# wc-risk-assessment-dashboard

Interactive screening dashboard for the World Cup 2026 threat-assessment
protocol. A frozen-snapshot companion to:

- the [narrative walkthrough](../wc-threat-assessment/narratives/) — explains *the method*
- [EPISTORM's importation-risk dashboard](https://epistorm.github.io/IDWC26-importation/) — explains *the import side*

This dashboard explains *the values* and lets users explore alternative
screening decisions and add pathogens of their own.

## Current state — mockup of the overview view

`index.html` is a single self-contained file (data inlined). Open it with
double-click or:

```
xdg-open index.html        # linux
explorer.exe index.html    # WSL → Windows
```

Three of the planned three views are scaffolded but only **Overview** is
populated. Subsequent rounds will add the pathogen-detail and add-your-own
views, and the interactive-override / WCR-recompute layer.

## Rebuilding

```
Rscript scripts/extract_pathogens.R   # cached sheet → data/pathogens.json
scripts/build.sh                      # template + json → index.html
```

`extract_pathogens.R` reads the cached Risk Filtering RDS from the sibling
`wc-threat-assessment` repo. Override the path with
`WC_RISK_FILTERING_RDS=/path/to/risk_filtering.rds`.

## Repo layout

```
index.template.html      page chrome + render JS; data goes in __PATHOGEN_DATA__
data/pathogens.json      generated from the Risk Filtering sheet snapshot
scripts/extract_pathogens.R   sheet RDS → normalized JSON
scripts/build.sh         template + json → index.html
assets/                  branding (ACCIDDA / Insight Net logos — TBA)
```

## Design

Visual chassis lifts the EPISTORM importation dashboard's editorial
typography (Spectral / IBM Plex Sans / IBM Plex Mono) and paper-toned
palette, with ACCIDDA branding in place of EPISTORM.
