import duckdb
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter

c = duckdb.connect()
c.sql("create table m as select * from read_csv('data/midyear_ytd_2025.csv', types={'fund_code':'VARCHAR'})")
c.sql("create table a as select * from read_csv('data/actuals_2025.csv', types={'account_code':'VARCHAR','approp_code':'VARCHAR'})")
c.sql("""create table b as select "DEPARTMENT NUMBER" d, "DEPARTMENT DESCRIPTION" n from read_csv('data/budget_2025.csv')""")
rows = c.sql("""
with mm as (select case dept_number when 70 then 67 when 62 then 60 else dept_number end d,
                   sum(budget) bud, sum(ytd_may) ytd
            from m where fund_code in ('0100','0B32') group by 1),
aa as (select dept_number d, sum(actual) act from a group by 1),
nn as (select d, any_value(n) n from b group by d)
select mm.d, nn.n, bud, ytd, act from mm join aa using(d) left join nn using(d)
order by bud desc""").fetchall()

wb = Workbook()
F = "Arial"
base = Font(name=F, size=10)
bold = Font(name=F, size=10, bold=True)
blue = Font(name=F, size=10, color="0000FF")
green = Font(name=F, size=10, color="008000")
title = Font(name=F, size=14, bold=True)
hdr_fill = PatternFill("solid", fgColor="D9E1F2")
yellow = PatternFill("solid", fgColor="FFFF00")
money = '$#,##0.0;($#,##0.0);-'
pct = '0.0%;(0.0%);-'
thin = Side(style="thin", color="999999")

# ---------------- Assumptions ----------------
s = wb.active
s.title = "Assumptions"
s["A1"] = "Year-End Forecast Assumptions"; s["A1"].font = title
s["A3"] = "Months of actuals available"; s["B3"] = 5
s["C3"] = "Mid-Year report data runs Jan 1 - May 31, 2025 (GL period 09)."
s["A4"] = "\"On pace\" threshold (% of budget spent by May)"; s["B4"] = 0.30
s["C4"] = "Method C: departments at or above this use run-rate; below it, assume spending is just late (timing) and use budget."
s["A5"] = "Finance General department number"; s["B5"] = 99
s["C5"] = "Citywide costs (pensions, debt, health claims) are paid in lumps, so Method C always uses budget for them."
s["B4"].number_format = '0%'
for r in (3, 4, 5):
    s[f"A{r}"].font = base; s[f"B{r}"].font = blue; s[f"B{r}"].fill = yellow; s[f"C{r}"].font = base
s["A7"] = "Edit the yellow cells to test other assumptions; the Forecast sheet recalculates."; s["A7"].font = Font(name=F, size=10, italic=True)
s["A9"] = "Methods"; s["A9"].font = bold
notes = [
    ("A. Run-rate", "Spending so far / months elapsed x 12. Assumes spending is spread evenly across the year."),
    ("B. Budget", "Assume every department spends exactly its budget."),
    ("C. Hybrid", "Run-rate for departments on pace; budget for departments behind pace and for Finance General."),
]
for i, (k, v) in enumerate(notes, start=10):
    s[f"A{i}"] = k; s[f"B{i}"] = v; s[f"A{i}"].font = bold; s[f"B{i}"].font = base
s["A14"] = "Sources"; s["A14"].font = bold
src = [
    "Budget and spending through May 31: City of Chicago, 2025 Mid-Year Budget Report, 'Year-to-Date Expenditure Performance', pp. 10-15 (Corporate Fund + Garbage Collection Fund).",
    "Actual full-year spending: City of Chicago, 2025 Annual Comprehensive Financial Report, Schedule A-2, General Fund (budgetary basis).",
    "Departments 70 (Business Affairs) and 62 (Community Commission) are combined with 67 (Buildings) and 60 (COPA) to match how the ACFR reports them.",
    "ACFR actuals also include about $0.4M from the Foreign Fire Insurance Tax Fund, which the Mid-Year report does not cover.",
]
for i, t in enumerate(src, start=15):
    s[f"A{i}"] = t; s[f"A{i}"].font = base
s.column_dimensions["A"].width = 46; s.column_dimensions["B"].width = 12; s.column_dimensions["C"].width = 100

# ---------------- Forecast ----------------
f = wb.create_sheet("Forecast")
f["A1"] = "Chicago 2025 Year-End Forecast vs Actual ($ millions)"; f["A1"].font = title
f["A2"] = "Forecast made from spending through May 31, 2025; compared with audited actuals."; f["A2"].font = Font(name=F, size=10, italic=True)

# summary block (rows 4-8), table header row 10
first, n = 11, len(rows)
last = first + n - 1
tot = last + 1
f["A4"] = "Accuracy summary"; f["A4"].font = bold
heads = ["", "A. Run-rate", "B. Budget", "C. Hybrid"]
for j, h in enumerate(heads):
    cell = f.cell(row=4, column=3 + j - 1 if j else 1)
for j, h in enumerate(["Method", "Total forecast", "Actual", "Error ($M)", "Error (%)", "Sum of dept errors (abs)"]):
    cl = f.cell(row=5, column=1 + j, value=h); cl.font = bold; cl.fill = hdr_fill
summary = [("A. Run-rate", "G", "L", "O"), ("B. Budget", "H", "M", "P"), ("C. Hybrid", "I", "N", "Q")]
for i, (name, fc, ec, ac) in enumerate(summary, start=6):
    f[f"A{i}"] = name; f[f"A{i}"].font = base
    f[f"B{i}"] = f"={fc}{tot}"
    f[f"C{i}"] = f"=J{tot}"
    f[f"D{i}"] = f"=B{i}-C{i}"
    f[f"E{i}"] = f"=IF(C{i}=0,0,D{i}/C{i})"
    f[f"F{i}"] = f"={ac}{tot}"
    for col in "BCDF":
        f[f"{col}{i}"].number_format = money; f[f"{col}{i}"].font = base
    f[f"E{i}"].number_format = pct; f[f"E{i}"].font = base

cols = ["Dept #", "Department", "Budget", "Spent by May 31", "% spent by May", "", "A. Run-rate", "B. Budget", "C. Hybrid",
        "Actual (ACFR)", "", "Error A", "Error B", "Error C", "Abs error A", "Abs error B", "Abs error C"]
for j, h in enumerate(cols, start=1):
    cl = f.cell(row=10, column=j, value=h or None)
    if h:
        cl.font = bold; cl.fill = hdr_fill; cl.alignment = Alignment(wrap_text=True, vertical="center")
for i, (d, name, bud, ytd, act) in enumerate(rows, start=first):
    f[f"A{i}"] = d; f[f"B{i}"] = name
    f[f"C{i}"] = round(bud / 1e6, 3); f[f"D{i}"] = round(ytd / 1e6, 3); f[f"J{i}"] = round(act / 1e6, 3)
    f[f"E{i}"] = f"=IF(C{i}=0,0,D{i}/C{i})"
    f[f"G{i}"] = f"=D{i}/Assumptions!$B$3*12"
    f[f"H{i}"] = f"=C{i}"
    f[f"I{i}"] = f"=IF(A{i}=Assumptions!$B$5,C{i},IF(E{i}>=Assumptions!$B$4,G{i},C{i}))"
    for k, fc in zip("LMN", "GHI"):
        f[f"{k}{i}"] = f"={fc}{i}-J{i}"
    for k, ec in zip("OPQ", "LMN"):
        f[f"{k}{i}"] = f"=ABS({ec}{i})"
    for col in "ABCDJ":
        f[f"{col}{i}"].font = blue if col in "CDJ" else base
    f[f"B{i}"].font = base
    for col in "CDGHIJLMNOPQ":
        f[f"{col}{i}"].number_format = money
    for col in "GHILMNOPQ":
        f[f"{col}{i}"].font = base
    f[f"E{i}"].number_format = pct; f[f"E{i}"].font = base
f[f"B{tot}"] = "Total"; f[f"B{tot}"].font = bold
for col in "CDGHIJLMNOPQ":
    f[f"{col}{tot}"] = f"=SUM({col}{first}:{col}{last})"
    f[f"{col}{tot}"].number_format = money; f[f"{col}{tot}"].font = bold
    f[f"{col}{tot}"].border = Border(top=thin)
f[f"E{tot}"] = f"=IF(C{tot}=0,0,D{tot}/C{tot})"; f[f"E{tot}"].number_format = pct; f[f"E{tot}"].font = bold
f[f"A{tot+2}"] = "Error = forecast - actual. Negative = the forecast was too low (the department spent more than forecast). Blue = data from the source reports; black = formulas."
f[f"A{tot+2}"].font = Font(name=F, size=9, italic=True)
widths = {"A": 8, "B": 44, "C": 11, "D": 13, "E": 10, "F": 2, "G": 12, "H": 11, "I": 11, "J": 12, "K": 2,
          "L": 11, "M": 11, "N": 11, "O": 12, "P": 12, "Q": 12}
for k, v in widths.items():
    f.column_dimensions[k].width = v
f.row_dimensions[10].height = 30
f.freeze_panes = "C11"
wb.move_sheet("Forecast", offset=-1)
wb.active = 0
wb.save("excel/06_year_end_forecast.xlsx")
print(n, "departments")
