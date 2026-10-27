from datetime import datetime
from pathlib import Path
import re
import pandas as pd
import xlrd

SECTION_TITLE = "Vagter - Dækkede vagter - afholdt"

def get_period(path, df):
    """Return (fra, til, from_file_name) for the export, read from the file name or else from the shift dates."""
    match = re.search(r"Fra (\d{2}\.\d{2}\.\d{4}) til (\d{2}\.\d{2}\.\d{4})", Path(path).name)
    if match:
        fra, til = (datetime.strptime(d, "%d.%m.%Y").date() for d in match.groups())
        return fra, til, True
    return df["Vagt_dato"].min(), df["Vagt_dato"].max(), False

def read_section(path, title):
    """Return the rows under a section title as a DataFrame, stopping at the first empty row."""
    sheet = xlrd.open_workbook(path).sheet_by_index(0)

    title_row = None
    for r in range(sheet.nrows):
        if str(sheet.cell_value(r, 0)).strip() == title:
            title_row = r
            break
    if title_row is None:
        raise ValueError(f"Section not found: {title}")

    # Headers are in the row after the title, e.g. "Kunde:" -> "Kunde"
    headers = [str(h).strip().rstrip(":") for h in sheet.row_values(title_row + 1) if str(h).strip()]

    rows = []
    r = title_row + 2
    while r < sheet.nrows and str(sheet.cell_value(r, 0)).strip():
        rows.append(sheet.row_values(r)[:len(headers)])
        r += 1

    return pd.DataFrame(rows, columns=headers)

def extract_afholdte_vagter(path):
    raw = read_section(path, SECTION_TITLE)

    # "12106 Bispehuset" -> Kundenr 12106, Kunde "Bispehuset"
    kunde = raw["Kunde"].str.split(" ", n=1, expand=True)

    # "27/03-26 12:15" -> Best_dato 2026-03-27, Best_tid "12:15"
    best = pd.to_datetime(raw["Best.tidspunkt"], format="%d/%m-%y %H:%M")

    return pd.DataFrame({
        "Kundenr": kunde[0].astype(int),
        "Kunde": kunde[1].str.strip(),
        "Vagt_dato": pd.to_datetime(raw["Vagt dato"], format="%Y-%m-%d").dt.date,
        "Lev_periode": raw["Lev. periode"].str.strip(),
        "Best_dato": best.dt.date,
        "Best_tid": best.dt.time,
        "Type": raw["Type"].str.strip(),
        # Antal_timer is NVARCHAR in VikarData: 9.5 -> "9.5", 8.0 -> "8"
        "Antal_timer": raw["Antal timer"].astype(float).map(lambda t: f"{t:g}"),
    })
