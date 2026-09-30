"""Fetch publicly linked professional leaflets; keep source bytes and extraction audit.
Never calls ANVISA's blocked portal. Text is verbatim, no generated clinical prose.
Requires curl, pdftotext, beautifulsoup4. Restart reuses cached source files.
"""
import concurrent.futures
import hashlib
import json
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from bs4 import BeautifulSoup

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / 'backend/data/raw/manufacturer'
OUT = ROOT / 'mobile/assets/leaflets/professional.json'
RAW.mkdir(parents=True, exist_ok=True)


def fetch(url, suffix):
    path = RAW / (hashlib.sha256(url.encode()).hexdigest() + suffix)
    if not path.exists():
        temp = path.with_suffix('.tmp')
        result = subprocess.run(['curl', '-fLsS', '--connect-timeout', '10', '--max-time', '60', url, '-o', str(temp)], capture_output=True)
        if result.returncode:
            temp.unlink(missing_ok=True)
            raise RuntimeError(result.stderr.decode()[-160:])
        temp.rename(path)
        time.sleep(.2)
    return path


def links(page):
    url = f'https://www.cristalia.com.br/produtos?page={page}'
    soup = BeautifulSoup(fetch(url, '.html').read_text(), 'html.parser')
    return sorted({a['href'] for a in soup.select('a[href]') if '/produto/' in a['href']})


def parse_product(url):
    soup = BeautifulSoup(fetch(url, '.html').read_text(), 'html.parser')
    title = soup.select_one('.news-title')
    name = title.get_text(' ', strip=True) if title else ''
    anchor = soup.select_one('a[href$="/bula-profissional"]')
    if not anchor:
        return {'skipped': url, 'reason': 'No professional leaflet linked'}
    source = anchor['href']
    pdf = fetch(source, '.pdf')
    if not pdf.read_bytes().startswith(b'%PDF'):
        raise ValueError('Non-PDF source: ' + source)
    textpath = pdf.with_suffix('.txt')
    subprocess.run(['pdftotext', '-layout', '-enc', 'UTF-8', str(pdf), str(textpath)], check=True, capture_output=True)
    raw = textpath.read_text()
    pages = [p.strip() for p in raw.split('\f') if p.strip()]
    if len(raw) < 1500 or not re.search(r'POSOLOGIA|COMO DEVO USAR', raw, re.I):
        return {'skipped': url, 'reason': 'Extraction requires manual review'}
    # Preserve every character from the page text; section navigation is only an index.
    headings = []
    pattern = re.compile(r'^\s*(?:[1-9]|10)\s*[.\-–)]\s*(?:INDICA|RESULTADOS|CARACTER|CONTRAINDICA|CONTRA-INDICA|ADVERT|INTERA|CUIDADOS|POSOLOGIA|REA|SUPERDO)', re.I)
    for page_no, page in enumerate(pages):
        for line in page.splitlines():
            if pattern.search(line) and len(line.strip()) < 130:
                label = line.strip()
                if label not in [h['title'] for h in headings]:
                    headings.append({'title': label, 'page': page_no})
    intro = ' '.join(pages[0].split())
    return {'id': re.search(r'/produto/(\d+)/', source).group(1), 'name': name,
            'manufacturer': 'Cristália', 'sourceUrl': source, 'productUrl': url,
            'sha256': hashlib.sha256(pdf.read_bytes()).hexdigest(),
            'collectedAt': datetime.now(timezone.utc).isoformat(),
            'intro': intro[:1000], 'pages': pages, 'headings': headings,
            'characters': len(raw), 'extraction': 'pdftotext -layout; original page order'}


def safe_product(url):
    try:
        return parse_product(url)
    except Exception as error:
        return {'skipped': url, 'reason': str(error)}


def main():
    urls = set()
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for items in pool.map(links, range(1, 23)):
            urls.update(items)
    print('Linked products:', len(urls), flush=True)
    results = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for i, row in enumerate(pool.map(safe_product, sorted(urls))):
            results.append(row)
            if i % 10 == 0:
                print('Processed:', i+1, 'texts:', sum('pages' in r for r in results), flush=True)
            (RAW/'checkpoint.json').write_text(json.dumps(results, ensure_ascii=False))
    unique = {r['id']: r for r in results if 'pages' in r}
    data = {'schema': 1, 'source': 'Public professional leaflets linked by Cristália',
            'collectedAt': datetime.now(timezone.utc).isoformat(),
            'scope': 'Manufacturer portfolio; not the complete ANVISA collection',
            'leaflets': sorted(unique.values(), key=lambda r: r['name'])}
    OUT.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')))
    report = {'linkedProducts':len(urls), 'included':len(unique), 'pages':sum(len(r['pages']) for r in unique.values()), 'excluded':[r for r in results if 'skipped' in r]}
    (RAW/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps(report, ensure_ascii=False),flush=True)

if __name__ == '__main__':
    main()
