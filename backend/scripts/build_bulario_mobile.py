"""Build the complete offline mobile asset from a validated ETL catalogue."""
import argparse
import gzip
import json
from pathlib import Path
import sqlite3
import unicodedata


def normalized(text):
    return ''.join(c for c in unicodedata.normalize('NFD', text.casefold())
                   if not unicodedata.combining(c))


def build(source, target):
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix('.sqlite.tmp')
    temporary.unlink(missing_ok=True)
    with sqlite3.connect(source) as incoming, sqlite3.connect(temporary) as db:
        db.executescript('''
          CREATE TABLE products(id TEXT PRIMARY KEY, name TEXT NOT NULL,
            registration TEXT NOT NULL, process TEXT NOT NULL, company TEXT NOT NULL,
            search TEXT NOT NULL, payload TEXT NOT NULL);
          CREATE INDEX product_registration ON products(registration);
          CREATE INDEX product_process ON products(process);
          CREATE TABLE documents(ordinal INTEGER PRIMARY KEY, id TEXT NOT NULL,
            process TEXT NOT NULL, status TEXT NOT NULL, payload TEXT NOT NULL);
          CREATE INDEX document_process ON documents(process);
          CREATE INDEX document_id ON documents(id);
          CREATE TABLE metadata(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        ''')
        counts = {'product': 0, 'document': 0}
        for kind, payload in incoming.execute('SELECT kind,payload FROM catalogue ORDER BY row_number'):
            r = json.loads(payload)
            counts[kind] += 1
            if kind == 'product':
                # Stable identity; duplicate identities fail instead of dropping source rows.
                db.execute('INSERT INTO products VALUES(?,?,?,?,?,?,?)', (
                    ':'.join([r['product_id'], r['process_number'], r['registration_number']]), r['product_name'], r['registration_number'],
                    r['process_number'], r['company_name'],
                    normalized(' '.join([r['product_name'], r['registration_number'],
                                         r['process_number'], r['company_name']])), payload))
            else:
                db.execute('INSERT INTO documents VALUES(?,?,?,?,?)', (
                    r['record_number'],r['document_id'],r['process_number'],r['document_status'],payload))
        metadata = json.loads(incoming.execute("SELECT value FROM metadata WHERE key='summary'").fetchone()[0])
        assert counts == {'product': metadata['products'], 'document': metadata['document_records']}
        db.execute('INSERT INTO metadata VALUES(?,?)', ('summary',json.dumps(metadata)))
        db.commit()
        assert db.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
    with temporary.open('rb') as src, target.open('wb') as dst:
        with gzip.GzipFile(fileobj=dst,mode='wb',mtime=0,filename='') as compressed:
            while block := src.read(1024 * 1024):
                compressed.write(block)
    compressed = target.read_bytes()
    split = 6 * 1024 * 1024
    for index, data in enumerate((compressed[:split], compressed[split:]), 1):
        target.with_name(target.name + '.part' + str(index)).write_bytes(data)
    target.unlink()
    temporary.unlink()
    print(json.dumps(counts))


if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--source',default='data/raw/bulario/bulario.sqlite')
    p.add_argument('--target',default='../mobile/assets/bulario/catalogue-v1.sqlite.gz')
    a=p.parse_args()
    build(a.source,a.target)
