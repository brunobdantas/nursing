from __future__ import annotations

from scripts.seed_structured_leaflets import parse_spl


def test_parse_spl_extracts_structured_text_sections() -> None:
    xml = b"""<?xml version="1.0" encoding="UTF-8"?>
    <document xmlns="urn:hl7-org:v3">
      <versionNumber value="7"/>
      <effectiveTime value="20260901"/>
      <component>
        <structuredBody>
          <component>
            <section>
              <title>INDICATIONS AND USAGE</title>
              <text><paragraph>Indications section.</paragraph></text>
            </section>
          </component>
          <component>
            <section>
              <title>DOSAGE AND ADMINISTRATION</title>
              <text><paragraph>Administration section.</paragraph></text>
            </section>
          </component>
          <component>
            <section>
              <title>CONTRAINDICATIONS</title>
              <text><paragraph>Contraindications section.</paragraph></text>
            </section>
          </component>
          <component>
            <section>
              <title>WARNINGS AND PRECAUTIONS</title>
              <text>
                <paragraph>Warnings section.</paragraph>
                <list><item>First item.</item><item>Second item.</item></list>
              </text>
            </section>
          </component>
        </structuredBody>
      </component>
    </document>
    """

    parsed = parse_spl(xml)

    assert parsed.source_version == "7"
    assert parsed.source_effective_date == "20260901"
    assert parsed.sections["indications_text"] == "Indications section."
    assert parsed.sections["dosage_administration_text"] == (
        "Administration section."
    )
    assert parsed.sections["contraindications_text"] == (
        "Contraindications section."
    )
    assert "Warnings section." in (parsed.sections["warnings_precautions_text"] or "")
    assert "First item." in (parsed.sections["warnings_precautions_text"] or "")
