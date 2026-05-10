#!/usr/bin/env python3
"""
JSR Beleg-Server — lokaler Ordner als Dropbox-Ersatz
Laeuft auf Port 4001, wird von belege.html angesprochen

Verwendung:
  python3 beleg_server.py --folder ~/Desktop/JSR-Belege

Ordnerstruktur wird automatisch angelegt:
  [folder]/
    Parklane GmbH/
      Eingang/        <- Belege hier reinlegen
      Verarbeitet/
        2026-01/
          JSR-2026-0001_Allianz.pdf
"""

import os, sys, json, shutil, hashlib, argparse
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse
import mimetypes

COMPANIES = ['Parklane GmbH', 'Parklane Zwei GmbH', 'Parklane Drei GmbH', 'Parklane Vier GmbH']
SUPPORTED = {'.pdf', '.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'}
processed_db_file = None
root_folder = None

def get_processed_db():
    db_path = Path(root_folder) / '.processed.json'
    if db_path.exists():
        try:
            return json.loads(db_path.read_text())
        except:
            return {}
    return {}

def save_processed_db(db):
    db_path = Path(root_folder) / '.processed.json'
    db_path.write_text(json.dumps(db, indent=2, ensure_ascii=False))

def ensure_structure():
    for co in COMPANIES:
        (Path(root_folder) / co / 'Eingang').mkdir(parents=True, exist_ok=True)
        (Path(root_folder) / co / 'Verarbeitet').mkdir(parents=True, exist_ok=True)

def file_hash(path):
    h = hashlib.md5()
    h.update(Path(path).read_bytes())
    return h.hexdigest()

def scan_new_files(company):
    eingang = Path(root_folder) / company / 'Eingang'
    if not eingang.exists():
        return []
    db = get_processed_db()
    new_files = []
    for f in sorted(eingang.iterdir()):
        if f.suffix.lower() not in SUPPORTED:
            continue
        if f.name.startswith('.'):
            continue
        fhash = file_hash(f)
        key = company + '/' + f.name
        if db.get(key) == fhash:
            continue  # already processed
        new_files.append({
            'name': f.name,
            'path': str(f),
            'size': f.stat().st_size,
            'hash': fhash,
            'key': key,
        })
    return new_files

def save_processed_file(company, month, doc_name, source_path, source_hash, source_key):
    """Copy file to Verarbeitet/YYYY-MM/ with new name"""
    src = Path(source_path)
    ext = src.suffix.lower()
    dest_dir = Path(root_folder) / company / 'Verarbeitet' / month
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / (doc_name + ext)
    # Keep original, copy to new location
    shutil.copy2(src, dest)
    # Mark as processed
    db = get_processed_db()
    db[source_key] = source_hash
    save_processed_db(db)
    return str(dest)

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress default logging

    def send_json(self, data, status=200):
        body = json.dumps(data, ensure_ascii=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', len(body))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(body)

    def send_file(self, path):
        p = Path(path)
        if not p.exists():
            self.send_json({'error': 'not found'}, 404)
            return
        data = p.read_bytes()
        mime = mimetypes.guess_type(str(p))[0] or 'application/octet-stream'
        self.send_response(200)
        self.send_header('Content-Type', mime)
        self.send_header('Content-Length', len(data))
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(data)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_GET(self):
        parsed = urlparse(self.path)
        qs = parse_qs(parsed.query)
        path = parsed.path

        # Health check
        if path == '/health':
            self.send_json({'ok': True, 'folder': str(root_folder)})

        # List new files for a company
        elif path == '/scan':
            company = qs.get('company', [''])[0]
            if company not in COMPANIES:
                self.send_json({'error': 'invalid company'}, 400)
                return
            files = scan_new_files(company)
            self.send_json({'files': files, 'count': len(files)})

        # Serve a file as base64 for API processing
        elif path == '/file':
            file_path = qs.get('path', [''])[0]
            p = Path(file_path)
            if not p.exists() or not str(p).startswith(str(root_folder)):
                self.send_json({'error': 'not found'}, 404)
                return
            import base64
            data = p.read_bytes()
            ext = p.suffix.lower()
            mime = 'application/pdf' if ext == '.pdf' else 'image/jpeg'
            b64 = base64.b64encode(data).decode()
            self.send_json({'base64': b64, 'mime': mime, 'name': p.name})

        # List processed files for a company+month
        elif path == '/processed':
            company = qs.get('company', [''])[0]
            month = qs.get('month', [''])[0]
            if company not in COMPANIES:
                self.send_json({'error': 'invalid company'}, 400)
                return
            dest_dir = Path(root_folder) / company / 'Verarbeitet' / month
            files = []
            if dest_dir.exists():
                files = [f.name for f in sorted(dest_dir.iterdir()) if not f.name.startswith('.')]
            self.send_json({'files': files, 'month': month, 'company': company})

        # Folder structure overview
        elif path == '/overview':
            result = {}
            for co in COMPANIES:
                eingang = Path(root_folder) / co / 'Eingang'
                verarbeitet = Path(root_folder) / co / 'Verarbeitet'
                new_count = len(scan_new_files(co))
                proc_count = sum(
                    len(list(d.iterdir()))
                    for d in verarbeitet.iterdir()
                    if d.is_dir()
                ) if verarbeitet.exists() else 0
                result[co] = {'new': new_count, 'processed': proc_count}
            self.send_json(result)

        else:
            self.send_json({'error': 'not found'}, 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        length = int(self.headers.get('Content-Length', 0))
        body = json.loads(self.rfile.read(length)) if length else {}

        # Reset processed history (all or per company)
        if path == '/reset':
            company = body.get('company', '')
            db = get_processed_db()
            if company:
                # Remove only entries for this company
                keys_to_delete = [k for k in db if k.startswith(company+'/')]
                for k in keys_to_delete:
                    del db[k]
                save_processed_db(db)
                self.send_json({'ok': True, 'removed': len(keys_to_delete), 'company': company})
            else:
                save_processed_db({})
                self.send_json({'ok': True, 'removed': len(db)})
            return

        # Save processed file
        if path == '/save':
            company = body.get('company', '')
            month = body.get('month', '')
            doc_name = body.get('doc_name', '')
            source_path = body.get('source_path', '')
            source_hash = body.get('source_hash', '')
            source_key = body.get('source_key', '')
            if not all([company, month, doc_name, source_path]):
                self.send_json({'error': 'missing params'}, 400)
                return
            if company not in COMPANIES:
                self.send_json({'error': 'invalid company'}, 400)
                return
            dest = save_processed_file(company, month, doc_name, source_path, source_hash, source_key)
            self.send_json({'ok': True, 'dest': dest})
        else:
            self.send_json({'error': 'not found'}, 404)


def main():
    global root_folder
    parser = argparse.ArgumentParser(description='JSR Beleg-Server')
    parser.add_argument('--folder', default=os.path.expanduser('~/Downloads/JSR-Belege'),
                        help='Wurzelordner fuer Belege')
    parser.add_argument('--port', type=int, default=4001)
    parser.add_argument('--reset', action='store_true', help='Verarbeitungs-History loeschen (alle Dateien erneut scannen)')
    args = parser.parse_args()
    root_folder = os.path.expanduser(args.folder)
    Path(root_folder).mkdir(parents=True, exist_ok=True)
    ensure_structure()
    if args.reset:
        db_path = Path(root_folder) / '.processed.json'
        if db_path.exists():
            db_path.unlink()
            print('History geloescht — alle Dateien werden neu verarbeitet.')
    print('JSR Beleg-Server gestartet')
    print('Ordner:', root_folder)
    print('URL:    http://localhost:'+str(args.port))
    print()
    print('Ordnerstruktur angelegt:')
    for co in COMPANIES:
        print('  '+root_folder+'/'+co+'/Eingang/')
    print()
    print('Ctrl+C zum Beenden')
    server = HTTPServer(('localhost', args.port), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print('\nServer gestoppt.')

if __name__ == '__main__':
    main()
