"""Extract the supplied, fixed-layout Mardi Gras PDF without inventing nutrients.

Usage: python3 tools/extract_carnival_pdf.py SOURCE.pdf OUTPUT.json
Requires pypdf. Source PDF is read only; its SHA-256 and page numbers are retained.
"""

import collections
import hashlib
import json
import re
import sys
from pathlib import Path

from pypdf import PdfReader


def extract(source):
    raw = source.read_bytes()
    reader = PdfReader(source)
    assert len(reader.pages) == 153, "Unexpected source layout; recheck the extractor."
    coverage = reader.pages[3].extract_text().splitlines()[3:]
    venues = {}
    for index in range(0, len(coverage), 2):
        if index + 1 < len(coverage):
            venues[coverage[index].strip()] = int(coverage[index + 1])
    assert len(venues) == 30 and sum(venues.values()) == 1085
    sources = {}
    for page in reader.pages[4:]:
        for line in (page.extract_text() or "").splitlines()[2:]:
            match = re.match(r"^(\d{2})\.\s+(https?://\S+)", line)
            if match:
                current_source = match[1]
                sources[current_source] = match[2]
            elif sources and not re.match(r"^\w.*\s", line) and not re.search(r"\s", line) and line:
                # Source URLs can wrap in the reference appendix.
                sources[current_source] += line.strip()
    foods = []
    venue = None
    heading = []
    entry = None
    for page_index, page in enumerate(reader.pages[4:], 5):
        chunks = []

        def visit(text, cm, tm, font, size):
            if text.strip() and size > 7:
                chunks.append((size, "Bold" in str(font), text.strip()))

        page.extract_text(visitor_text=visit)
        for size, bold, text in chunks:
            if size == 17:
                heading.append(text)
                continue
            if heading:
                venue = " ".join(heading)
                heading = []
                if venue not in venues:
                    venue = None
            if venue is None:
                continue
            if size == 11 and bold:
                if entry is None:
                    entry = {"venue": venue, "name": [], "portion": [], "macro": [], "metadata": [], "sourcePage": page_index}
                assert not entry["macro"], f"Unfinished food on page {page_index}"
                entry["name"].append(text)
            elif entry is not None:
                if size == 10:
                    entry["macro"].append(text)
                elif not entry["macro"]:
                    entry["portion"].append(text)
                else:
                    entry["metadata"].append(text)
                metadata = " ".join(entry["metadata"])
                identifier = re.search(r"\bID (MG[0-9A-F]{7})\.", metadata)
                if identifier:
                    macro = " ".join(entry["macro"])
                    parts = re.fullmatch(r"Total carbs (\S+) g Net (\S+) g Fibre (\S+) g Protein (\S+) g Fat (\S+) g Energy (\S+) kcal", macro)
                    assert parts, (identifier[1], macro)
                    values = [None if x == "n.a." else float(x) for x in parts.groups()]
                    assert all(v is None or v >= 0 for v in values)
                    estimated = metadata.startswith("Estimate.")
                    assert estimated or metadata.startswith("Nutrition unavailable.")
                    assert estimated == all(v is not None for v in values)
                    bounds = re.search(r"Carb planning range ([\d.]+)-([\d.]+) g\.", metadata)
                    low, high = (float(bounds[1]), float(bounds[2])) if bounds else (None, None)
                    if estimated:
                        assert low is not None and low <= values[0] <= high
                    source_id = re.search(r"\bSource (\d{2})\.", metadata)
                    assert source_id and source_id[1] in sources
                    foods.append(dict(id=identifier[1], venue=venue, name=" ".join(entry["name"]), portion=" ".join(entry["portion"]),
                                      carbs=values[0], netCarbs=values[1], fibre=values[2], protein=values[3], fat=values[4], calories=values[5],
                                      low=low, high=high, nutrition="estimate" if estimated else "unavailable", notes=metadata,
                                      sourcePage=entry["sourcePage"], sourceNumber=source_id[1], sourceURL=sources[source_id[1]]))
                    entry = None
    assert entry is None, "An entry was not terminated."
    assert len(foods) == len({f["id"] for f in foods}) == 1085
    assert collections.Counter(f["venue"] for f in foods) == collections.Counter(venues)
    assert sum(f["nutrition"] == "estimate" for f in foods) == 1031
    assert sum(f["nutrition"] == "unavailable" for f in foods) == 54
    assert len(sources) == 79
    return dict(schemaVersion=1, sourceFilename=source.name, sourceSHA256=hashlib.sha256(raw).hexdigest(), sailingDate="2026-10-24",
                notice="Nutrition and portions are estimates from the supplied guide, not verified Carnival macros. Planning ranges are assumptions, not guaranteed bounds.", foods=foods)


if __name__ == "__main__":
    source, destination = map(Path, sys.argv[1:])
    catalog = extract(source)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
    print(f"Extracted {len(catalog['foods'])} foods; 1,031 estimates, 54 unavailable; source SHA-256 {catalog['sourceSHA256']}.")
