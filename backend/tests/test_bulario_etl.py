import asyncio
from argparse import Namespace
import json
import sqlite3

import pytest

from scripts.etl_bulario import parse, run, write_catalogue

PRODUCT = '1;"Ácido teste";"012345678";8;"25351000000202600";"00123456000100";"Empresa";42;"001";"09/25/2026 00:00:00";"2";"09/25/2026 00:00:00"\n'
DOCUMENT = '"25351000000202600";42;"001";43;"Aditado ao processo";"09/25/2026 00:00:00";"2";"09/25/2026 00:00:00";"09/25/2026 00:00:00";"09/25/2026 00:00:00"\n'


def test_headerless_first_record_and_leading_zeros_preserved():
    rows = parse((PRODUCT * 2).encode("latin1"), "product")
    assert len(rows) == 2
    assert rows[0]["registration_number"] == "012345678"
    assert rows[0]["company_cnpj"] == "00123456000100"
    assert rows[0]["product_name"] == "Ácido teste"
    assert rows[0]["raw_columns"][8] == "001"


@pytest.mark.parametrize("content", [b"", b"<html>blocked</html>", b"a;b;c", PRODUCT.replace("012345678", "unexpected").encode()])
def test_invalid_response_fails_closed(content):
    with pytest.raises(ValueError):
        parse(content, "product")


def test_document_match_requires_process_and_id(tmp_path):
    products = parse(PRODUCT.encode(), "product")
    wrong = parse(DOCUMENT.replace("25351000000202600", "25351999999202600").encode(), "document")
    result = write_catalogue(tmp_path / "db.sqlite", {"product": products, "document": wrong}, {})
    assert result["products_with_exact_document_match"] == 0
    assert result["full_texts_available"] == 0


def test_missing_registration_is_retained_as_source_quality_issue():
    rows = parse(PRODUCT.replace('"012345678"', '""').encode(), "product")
    assert rows[0]["registration_number"] == ""


def test_repeat_run_and_invalid_update_keep_last_catalogue(tmp_path):
    p, d = tmp_path / "p.csv", tmp_path / "d.csv"
    p.write_bytes(PRODUCT.encode("latin1"))
    d.write_text(DOCUMENT)
    args = Namespace(output=str(tmp_path / "out"), product_csv=str(p), document_csv=str(d), database_url=None)
    for _ in range(2):
        result = asyncio.run(run(args))
        assert result["products_with_exact_document_match"] == 1
    target = tmp_path / "out" / "bulario.sqlite"
    before = target.read_bytes()
    d.write_text("<html>service unavailable</html>")
    with pytest.raises(ValueError):
        asyncio.run(run(args))
    assert target.read_bytes() == before
    with sqlite3.connect(target) as conn:
        assert conn.execute("SELECT count(*) FROM catalogue").fetchone()[0] == 2
        row = json.loads(conn.execute("SELECT payload FROM catalogue WHERE kind='product'").fetchone()[0])
        assert row["content_status"] == "metadata_only"
