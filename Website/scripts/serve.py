from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import argparse

parser=argparse.ArgumentParser(description='Serve a local website preview without stale browser caches.')
parser.add_argument('--directory',type=Path,default=Path(__file__).resolve().parents[1]/'.local/dist')
parser.add_argument('--port',type=int,default=8767)
args=parser.parse_args()
if not (args.directory/'index.html').is_file():parser.error('Build the website before starting its preview.')

class PreviewHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control','no-store, no-cache, must-revalidate, max-age=0')
        self.send_header('Pragma','no-cache')
        self.send_header('Expires','0')
        self.send_header('X-Robots-Tag','noindex, nofollow')
        super().end_headers()
    def send_head(self):
        if 'If-Modified-Since' in self.headers:del self.headers['If-Modified-Since']
        return super().send_head()
    def list_directory(self,path):
        self.send_error(404)
        return None
    def log_message(self,format,*values):pass

handler=partial(PreviewHandler,directory=str(args.directory.resolve()))
with ThreadingHTTPServer(('127.0.0.1',args.port),handler) as server:
    print(f'Preview: http://127.0.0.1:{args.port} (caching disabled)',flush=True)
    server.serve_forever()
