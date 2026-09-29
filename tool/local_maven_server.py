import http.server
import socketserver
import os
import urllib.request

PORT = 8899
TEMP_DIR = r"E:\.temp"

class MavenProxyHandler(http.server.SimpleHTTPRequestHandler):
    def do_HEAD(self):
        filename = os.path.basename(self.path)
        local_path = os.path.join(TEMP_DIR, filename)
        if os.path.exists(local_path) and os.path.isfile(local_path):
            self.send_response(200)
            self.send_header('Content-Type', 'application/java-archive')
            self.send_header('Content-Length', str(os.path.getsize(local_path)))
            self.end_headers()
            return

        clean_path = self.path
        if clean_path.startswith('/download.flutter.io/'):
            remote_url = 'https://storage.flutter-io.cn' + clean_path
        else:
            remote_url = 'https://storage.flutter-io.cn/download.flutter.io' + clean_path
        try:
            req = urllib.request.Request(remote_url, method='HEAD', headers={'User-Agent': 'curl/8.0'})
            with urllib.request.urlopen(req, timeout=10) as resp:
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() in ['content-type', 'content-length']:
                        self.send_header(k, v)
                self.end_headers()
        except Exception:
            self.send_response(404)
            self.end_headers()

    def do_GET(self):
        filename = os.path.basename(self.path)
        local_path = os.path.join(TEMP_DIR, filename)
        
        if os.path.exists(local_path) and os.path.isfile(local_path):
            print(f"[LOCAL HIT 1000MB/s] Serving {filename} ({os.path.getsize(local_path)/(1024*1024):.2f} MB)")
            self.send_response(200)
            self.send_header('Content-Type', 'application/java-archive')
            self.send_header('Content-Length', str(os.path.getsize(local_path)))
            self.end_headers()
            with open(local_path, 'rb') as f:
                while chunk := f.read(1024 * 1024):
                    self.wfile.write(chunk)
            return

        clean_path = self.path
        if clean_path.startswith('/download.flutter.io/'):
            remote_url = 'https://storage.flutter-io.cn' + clean_path
        else:
            remote_url = 'https://storage.flutter-io.cn/download.flutter.io' + clean_path

        try:
            req = urllib.request.Request(remote_url, headers={'User-Agent': 'curl/8.0'})
            with urllib.request.urlopen(req, timeout=15) as resp:
                data = resp.read()
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() in ['content-type', 'content-length']:
                        self.send_header(k, v)
                self.end_headers()
                self.wfile.write(data)
                print(f"[PROXIED] {self.path} ({len(data)} bytes)")
        except Exception as e:
            self.send_response(404)
            self.end_headers()

if __name__ == '__main__':
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(('127.0.0.1', PORT), MavenProxyHandler) as httpd:
        print(f"Maven Local Proxy running on http://127.0.0.1:{PORT}")
        httpd.serve_forever()
