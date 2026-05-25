#!/usr/bin/env bash
# Inline data/pathogens.json and the assets/*.png logos into
# index.template.html so the result is a single self-contained file
# that opens with double-click (no server, no fetch).
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
tpl="$here/index.template.html"
data="$here/data/pathogens.json"
out="$here/index.html"
accidda="$here/assets/ACCIDDAWhite.png"
insight="$here/assets/insight-net.png"

[[ -f "$tpl"     ]] || { echo "missing template: $tpl"  >&2; exit 1; }
[[ -f "$data"    ]] || { echo "missing data: $data — run scripts/extract_pathogens.R first" >&2; exit 1; }
[[ -f "$accidda" ]] || { echo "missing logo: $accidda" >&2; exit 1; }
[[ -f "$insight" ]] || { echo "missing logo: $insight" >&2; exit 1; }

python3 - "$tpl" "$data" "$accidda" "$insight" "$out" <<'PY'
import sys, pathlib, base64, mimetypes
tpl_p, data_p, accidda_p, insight_p, out_p = map(pathlib.Path, sys.argv[1:6])
tpl  = tpl_p.read_text(encoding='utf-8')
data = data_p.read_text(encoding='utf-8')

def data_uri(p: pathlib.Path) -> str:
    mime = mimetypes.guess_type(p.name)[0] or 'image/png'
    return f"data:{mime};base64,{base64.b64encode(p.read_bytes()).decode('ascii')}"

subs = {
    '__PATHOGEN_DATA__':    data,
    '__LOGO_ACCIDDA__':     data_uri(accidda_p),
    '__LOGO_INSIGHTNET__':  data_uri(insight_p),
}

missing = [k for k in subs if k not in tpl]
if missing:
    sys.exit(f"template missing markers: {', '.join(missing)}")

result = tpl
for marker, value in subs.items():
    result = result.replace(marker, value)
out_p.write_text(result, encoding='utf-8')
print(f"wrote {out_p} ({out_p.stat().st_size:,} bytes)")
PY
