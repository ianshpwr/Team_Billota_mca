#!/bin/sh
# Download a local copy of the Surfer waveform viewer's WebAssembly build so that
# the page and the VCD files are served from the same origin (no CORS / private
# network restrictions). Surfer: https://surfer-project.org (EUPL-1.2 licence).
# The copy is NOT committed to the repository (see .gitignore: build/).
# Usage (repo root): sh scripts/fetch_surfer_web.sh   -> build/surfer_web/
set -e
D=build/surfer_web; mkdir -p $D; cd $D
for f in index.html manifest.json favicon.ico surfer.js surfer_bg.wasm integration.js sw.js; do
  curl -sf -O https://app.surfer-project.org/$f || echo "could not fetch $f"
done
# drop the analytics script tag so the local copy makes no third-party requests
sed -i.bak 's#<script src="//gc.zgo.at/count.js"[^>]*></script>##' index.html && rm -f index.html.bak
ls -la
