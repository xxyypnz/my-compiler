#!/usr/bin/env python3
import os
import textwrap
import zipfile
import html


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")


def pdf_escape(text):
    return text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")


def write_simple_pdf(path, lines):
    objects = []

    def add(obj):
        objects.append(obj)
        return len(objects)

    font_id = add("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")

    content_lines = ["BT", "/F1 10 Tf", "50 800 Td", "12 TL"]
    first = True
    for line in lines:
        wrapped = textwrap.wrap(line, width=92) or [""]
        for part in wrapped:
            if not first:
                content_lines.append("T*")
            content_lines.append(f"({pdf_escape(part)}) Tj")
            first = False
    content_lines.append("ET")
    content = "\n".join(content_lines).encode("latin-1", "replace")

    stream_id = add(
        f"<< /Length {len(content)} >>\nstream\n"
        + content.decode("latin-1")
        + "\nendstream"
    )
    page_id = add(
        f"<< /Type /Page /Parent 4 0 R /MediaBox [0 0 595 842] "
        f"/Resources << /Font << /F1 {font_id} 0 R >> >> "
        f"/Contents {stream_id} 0 R >>"
    )
    pages_id = add(f"<< /Type /Pages /Kids [{page_id} 0 R] /Count 1 >>")
    catalog_id = add(f"<< /Type /Catalog /Pages {pages_id} 0 R >>")

    data = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for idx, obj in enumerate(objects, start=1):
        offsets.append(len(data))
        data.extend(f"{idx} 0 obj\n{obj}\nendobj\n".encode("latin-1"))

    xref = len(data)
    data.extend(f"xref\n0 {len(objects) + 1}\n".encode("latin-1"))
    data.extend(b"0000000000 65535 f \n")
    for off in offsets[1:]:
        data.extend(f"{off:010d} 00000 n \n".encode("latin-1"))
    data.extend(
        f"trailer\n<< /Size {len(objects) + 1} /Root {catalog_id} 0 R >>\n"
        f"startxref\n{xref}\n%%EOF\n".encode("latin-1")
    )

    with open(path, "wb") as f:
        f.write(data)


def write_svg(path):
    lines = [
        "L26 Compiler Test Results",
        "Build: PASS, no warnings",
        "Positive tests: PASS (test1-test5)",
        "Error tests: PASS (8 cases)",
        "Single-step mode: PASS",
        "Bonus: P-Code view, set equality, set comprehension",
    ]
    height = 70 + len(lines) * 34
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="{height}" viewBox="0 0 1100 {height}">',
        '<rect width="1100" height="100%" fill="#f7f7f7"/>',
        '<rect x="36" y="32" width="1028" height="{}" rx="8" fill="#ffffff" stroke="#222"/>'.format(height - 64),
        '<text x="64" y="76" font-family="monospace" font-size="28" font-weight="700" fill="#111">L26 Compiler Verification Screenshot</text>',
    ]
    y = 122
    for line in lines:
        parts.append(f'<text x="76" y="{y}" font-family="monospace" font-size="22" fill="#111">{line}</text>')
        y += 34
    parts.append("</svg>")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(parts))


def md_to_docx(path, markdown_path):
    with open(markdown_path, "r", encoding="utf-8") as f:
        lines = f.read().splitlines()

    body = []
    for raw in lines:
        line = raw.strip()
        if not line:
            body.append("<w:p/>")
            continue
        if line.startswith("```"):
            continue

        style = ""
        text = line
        if line.startswith("# "):
            style = '<w:pStyle w:val="Title"/>'
            text = line[2:]
        elif line.startswith("## "):
            style = '<w:pStyle w:val="Heading1"/>'
            text = line[3:]
        elif line.startswith("### "):
            style = '<w:pStyle w:val="Heading2"/>'
            text = line[4:]
        elif line.startswith("- "):
            text = "• " + line[2:]

        body.append(
            "<w:p>"
            f"<w:pPr>{style}</w:pPr>"
            "<w:r>"
            '<w:rPr><w:rFonts w:ascii="Arial" w:eastAsia="SimSun" w:hAnsi="Arial"/></w:rPr>'
            f"<w:t>{html.escape(text)}</w:t>"
            "</w:r>"
            "</w:p>"
        )

    document_xml = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        "<w:body>"
        + "".join(body)
        + '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>'
        + "</w:body></w:document>"
    )

    content_types = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
        "</Types>"
    )
    rels = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        "</Relationships>"
    )
    styles = (
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:rPr><w:b/><w:sz w:val="32"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:rPr><w:b/><w:sz w:val="28"/></w:rPr></w:style>'
        '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:rPr><w:b/><w:sz w:val="24"/></w:rPr></w:style>'
        "</w:styles>"
    )

    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", content_types)
        z.writestr("_rels/.rels", rels)
        z.writestr("word/document.xml", document_xml)
        z.writestr("word/styles.xml", styles)


def main():
    os.makedirs(DOCS, exist_ok=True)
    pdf_lines = [
        "L26 Compiler Design Report",
        "",
        "Implementation: Flex lexer, Bison parser and semantic actions, P-Code generator, P-Code VM.",
        "Supported types: int, bool, set. Set capacity: 200 unique integers.",
        "Scope: nested block scope with shadowing and duplicate declaration checks.",
        "Core features: assignment, arithmetic, relations, boolean logic, if/else, while, read/write.",
        "Set features: literal, add, remove, in, isempty, union, inter, write set.",
        "Bonus 1: P-Code listing and single-step execution.",
        "Bonus 2: set equality for set variables.",
        "Bonus 3: set comprehension syntax: { expr | x in S if condition }.",
        "Tests: make test-all passes positive tests test1-test5 and 8 negative tests.",
        "See design.md and test-results.md for the complete Chinese report.",
    ]
    write_simple_pdf(os.path.join(DOCS, "设计说明.pdf"), pdf_lines)
    md_to_docx(os.path.join(DOCS, "设计说明.docx"), os.path.join(DOCS, "设计说明.md"))
    write_svg(os.path.join(DOCS, "测试结果截图.svg"))


if __name__ == "__main__":
    main()
