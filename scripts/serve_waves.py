#!/usr/bin/env python3
"""Local server used to view the VCDs in the Surfer web app (genuine screenshots).
   /        -> repository root (so /results/waveforms/x.vcd is reachable)
   /surfer/ -> a local copy of the Surfer WebAssembly build (see scripts/fetch_surfer_web.sh)
   Usage: python3 -I scripts/serve_waves.py <repo_root> <surfer_web_dir>      (port 8767)
   Then open: http://127.0.0.1:8767/surfer/index.html?load_url=http://127.0.0.1:8767/results/waveforms/<file>.vcd
"""
import http.server, sys, os
REPO=sys.argv[1]; WEB=sys.argv[2]
class H(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        p = path.split('?')[0]
        if p.startswith('/surfer/'):
            return os.path.join(WEB, p[len('/surfer/'):] or 'index.html')
        return os.path.join(REPO, p.lstrip('/'))
    def end_headers(self):
        self.send_header("Cache-Control","no-store")
        super().end_headers()
    def log_message(self,*a): pass
http.server.ThreadingHTTPServer(("127.0.0.1",8767),H).serve_forever()
