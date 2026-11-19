"""
Extract 2025 General Fund budget vs actual by department and line
from the City of Chicago 2025 ACFR (Schedule A-2), and save it as a CSV.

Usage:
    python extract_acfr_actuals.py data/acfr_2025.pdf data/actuals_2025.csv

Needs: pdfplumber  (pip install pdfplumber)
"""
import csv
import re
import sys

import pdfplumber

START = "SCHEDULE OF EXPENDITURES AND ENCUMBRANCES - BUDGET AND ACTUAL"
END = "TOTAL GENERAL FUND"

# "OFFICE OF THE MAYOR - 01 -"
DEPT_RE = re.compile(r"^\s*([A-Z][A-Z0-9&,'./()\- ]+?)\s+-\s+(\d{2,3})\s+-\s*$")
# " 2005.0000-Personnel Services ......"  (some codes have letters: 2005.929A)
ITEM_RE = re.compile(r"^\s*(\d{4}\.[0-9A-Z]{4})-(.*)$")   # codes can contain letters, e.g. 929A
# a number like 10,952,655 or $10,952,655, or a dash for zero
NUM = r"\$?\s*(?:\(?[\d,]+\)?|—)"
THREE_NUMS_RE = re.compile(rf"({NUM})\s+({NUM})\s+({NUM})\s*$")
TOTAL_RE = re.compile(r"^\s*Total\s*\.")


def to_number(token: str) -> int:
    token = token.replace("$", "").replace(",", "").strip()
    if token == "—":
        return 0
    if token.startswith("(") and token.endswith(")"):
        return -int(token[1:-1])
    return int(token)


def schedule_lines(pdf_path):
    """Yield the text lines of Schedule A-2 only."""
    inside = False
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            text = page.extract_text(layout=True) or ""
            if START in text and "GENERAL FUND" in text:
                inside = True
            if not inside:
                continue
            for line in text.splitlines():
                if END in line:
                    return
                yield line


def parse(pdf_path):
    rows, totals = [], {}
    dept_name = dept_no = None
    item_code, item_desc = None, []

    for line in schedule_lines(pdf_path):
        m = DEPT_RE.match(line)
        if m:
            dept_name, dept_no = m.group(1).strip(), int(m.group(2))
            item_code = None
            continue

        if TOTAL_RE.match(line):
            nums = THREE_NUMS_RE.search(line)
            if nums and dept_no is not None:
                # a department can have several sub-units, each with its own Total
                prev = totals.get((dept_no, dept_name), [0, 0, 0])
                totals[(dept_no, dept_name)] = [a + to_number(n) for a, n in zip(prev, nums.groups())]
            item_code = None
            continue

        m = ITEM_RE.match(line)
        if m:
            item_code, item_desc = m.group(1), [m.group(2)]
        elif item_code:
            item_desc.append(line)  # continuation of a long description
        else:
            continue

        nums = THREE_NUMS_RE.search(line)
        if nums:  # the line that ends the item carries the three amounts
            desc = " ".join(item_desc)
            desc = THREE_NUMS_RE.sub("", desc)
            desc = re.sub(r"\.{2,}.*$", "", desc)        # drop the dot leaders
            desc = re.sub(r"\s+", " ", desc).strip()
            original, final, actual = (to_number(n) for n in nums.groups())
            rows.append({
                "dept_number": dept_no,
                "dept_name_acfr": dept_name,
                "approp_code": item_code,                  # e.g. 2005.0000
                "account_code": item_code.split(".")[1],   # e.g. 0000
                "account_group": desc,
                "original_budget": original,
                "final_budget": final,
                "actual": actual,
            })
            item_code = None
    return rows, totals


def main(pdf_path, out_csv):
    rows, totals = parse(pdf_path)

    # CHECK 1: line items add up to each department's printed Total
    bad = []
    for (no, name), (_, _, actual_total) in totals.items():
        s = sum(r["actual"] for r in rows if r["dept_number"] == no and r["dept_name_acfr"] == name)
        if s != actual_total:
            bad.append((no, name, s, actual_total))

    with open(out_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys())
        w.writeheader()
        w.writerows(rows)

    print(f"Rows written: {len(rows)}  Departments: {len(totals)}")
    print(f"Total final budget: ${sum(r['final_budget'] for r in rows):,}")
    print(f"Total actual:       ${sum(r['actual'] for r in rows):,}")
    print("Expected (ACFR):    budget $5,889,083,936  actual $5,689,918,885")
    print("Department totals that don't match:", bad or "none")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
