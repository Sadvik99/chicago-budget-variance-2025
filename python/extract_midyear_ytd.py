"""
Extract year-to-date spending (through May 31, 2025) by department and fund
from the City of Chicago 2025 Mid-Year Budget Report
("Year-to-Date Expenditure Performance" table), and save it as a CSV.

Usage:
    python extract_midyear_ytd.py data/midyear_2025.pdf data/midyear_ytd_2025.csv

Needs: pdfplumber  (pip install pdfplumber)
"""
import csv
import re
import sys

import pdfplumber

START = "Year-to-Date Expenditure Performance"
END = "Grand Total"

DEPT_RE = re.compile(r"^\s*D(\d{2,3})\s+-\s+(.*?)(?:\s{2,}\$|$)")
FUND_RE = re.compile(r"^\s*F([0-9A-Z]{4})\s+[-–]\s+(.*?)(?:\s{2,}\$|$)")
AMOUNTS_RE = re.compile(r"\$([\d,]+)\s+\$([\d,]+)(?:\s+(\d+)%)?")


def lines(pdf_path):
    started = False
    with pdfplumber.open(pdf_path) as pdf:
        for page in pdf.pages:
            text = page.extract_text(layout=True) or ""
            if not started and START in text and "May 31, 2025" in text:
                started = True
            if not started:
                continue
            for line in text.splitlines():
                yield line
                if END in line:
                    return


def parse(pdf_path):
    rows, grand_total = [], None
    dept_no = dept_name = fund_code = fund_name = None
    for line in lines(pdf_path):
        if END in line:
            m = AMOUNTS_RE.search(line)
            if m:
                grand_total = (int(m.group(1).replace(",", "")), int(m.group(2).replace(",", "")))
            break
        d = DEPT_RE.match(line)
        if d:
            dept_no, dept_name, fund_code = int(d.group(1)), d.group(2).strip(), None
            continue  # department subtotal line: skip, we keep fund rows
        f = FUND_RE.match(line)
        if f:
            fund_code, fund_name = f.group(1), f.group(2).strip()
        amounts = AMOUNTS_RE.search(line)
        if amounts and fund_code and dept_no is not None:
            rows.append({
                "dept_number": dept_no,
                "dept_name": dept_name,
                "fund_code": fund_code,
                "fund_name": fund_name,
                "budget": int(amounts.group(1).replace(",", "")),
                "ytd_may": int(amounts.group(2).replace(",", "")),
            })
            fund_code = None
    return rows, grand_total


def main(pdf_path, out_csv):
    rows, grand_total = parse(pdf_path)
    with open(out_csv, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=rows[0].keys())
        w.writeheader()
        w.writerows(rows)
    print(f"Rows written: {len(rows)}")
    print(f"Sum budget: ${sum(r['budget'] for r in rows):,}   Sum YTD: ${sum(r['ytd_may'] for r in rows):,}")
    if grand_total:
        print(f"Report Grand Total: ${grand_total[0]:,}   ${grand_total[1]:,}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
