import pyodbc
import os
import re
import time
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

BATCH_SIZE = 1000
TARGET_TABLE = "dbo.VikarData"
TEST_TABLE = "dbo.VikarData_Test"
LIVE_PROCEDURE = "dbo.ProcessExtractedData"
TEST_PROCEDURE = "#ProcessExtractedData"
PROCEDURE_FILE = Path(__file__).resolve().parent.parent / "sql" / "ProcessExtractedData.sql"
COLUMNS = "Kundenr, Kunde, Vagt_dato, Lev_periode, Best_dato, Best_tid, Type, Antal_timer"

def is_debug() -> bool:
    """Test mode is on unless debug=false is set in .env, so live mode is never used by accident."""
    return os.getenv('debug', 'true').strip().lower() != 'false'

def get_connection() -> pyodbc.Connection:
    """Establish a connection to the database."""
    connection_string: str = (
        "Driver={ODBC Driver 18 for SQL Server};"
        f"Server={os.getenv('Server')};"
        f"Database={os.getenv('Database')};"
        f"UID={os.getenv('DB_USERNAME')};"
        f"PWD={os.getenv('DB_PASSWORD')};"
        "Encrypt=yes;"
        "TrustServerCertificate=yes;"
    )
    return pyodbc.connect(connection_string)

def check_rows(df, fra, til):
    """Stop before touching the database if the data can't be right."""
    if len(df) == 0:
        raise RuntimeError("The file has no rows in the section. Nothing was changed.")
    outside = df[(df["Vagt_dato"] < fra) | (df["Vagt_dato"] > til)]
    if len(outside) > 0:
        raise RuntimeError(f"{len(outside)} rows have a Vagt_dato outside the period {fra} - {til}. Nothing was changed.")

def load_temp_table(cursor, df):
    """Load the extracted data into a temporary table, which disappears when the connection closes."""
    cursor.execute("""
        CREATE TABLE #TempExtractedData (
            Kundenr SMALLINT,
            Kunde NVARCHAR(50),
            Vagt_dato DATE,
            Lev_periode NVARCHAR(50),
            Best_dato DATE,
            Best_tid TIME,
            Type NVARCHAR(50),
            Antal_timer NVARCHAR(50)
        )
    """)

    rows = list(df.itertuples(index=False, name=None))
    total = len(rows)
    print(f"Uploading {total} rows...", flush=True)
    for start in range(0, total, BATCH_SIZE):
        batch = rows[start:start + BATCH_SIZE]
        cursor.executemany(f"INSERT INTO #TempExtractedData ({COLUMNS}) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", batch)
        print(f"  {start + len(batch)}/{total} rows uploaded", flush=True)

def create_test_procedure(cursor):
    """Create a temporary copy of ProcessExtractedData that works on the test table.

    It is built from sql/ProcessExtractedData.sql, so test mode runs exactly the same logic as live mode.
    Like #TempExtractedData it only exists while the connection is open.
    """
    sql = PROCEDURE_FILE.read_text(encoding="utf-8")
    body = sql[sql.index("CREATE OR ALTER PROCEDURE"):]
    body = body[:re.search(r"^\s*GO\s*$", body, flags=re.M).start()]
    body = body.replace("CREATE OR ALTER PROCEDURE dbo.ProcessExtractedData", f"CREATE PROCEDURE {TEST_PROCEDURE}")
    body = re.sub(r"\bdbo\.VikarData\b", TEST_TABLE, body)
    cursor.execute(body)

def preview(cursor, procedure, fra, til):
    """Counts for the user to decide on; changes nothing."""
    return cursor.execute(f"EXEC {procedure} @Fra = ?, @Til = ?, @Preview = 1", fra, til).fetchone()

def apply(cursor, procedure, fra, til, delete_missing):
    """Insert the new rows and, if chosen, delete the missing rows. Returns the procedure's counts."""
    return cursor.execute(f"EXEC {procedure} @Fra = ?, @Til = ?, @Preview = 0, @DeleteMissing = ?",
                          fra, til, 1 if delete_missing else 0).fetchone()

def SendExtractedData(df, fra, til, decide):
    """Merge the extracted data into the table for the period fra-til.

    decide(table, status) is called before anything is changed, with the preview counts
    (FileRows, ExistingRows, NewRows, UnchangedRows, MissingRows, LatestVagtDato).
    It returns "keep" or "delete" for the missing rows, or None to cancel.
    Returns (table, result) with DeletedRows, InsertedRows, UnchangedRows, or None if cancelled.
    """
    table = TEST_TABLE if is_debug() else TARGET_TABLE
    procedure = TEST_PROCEDURE if is_debug() else LIVE_PROCEDURE
    if is_debug():
        print(f"TEST MODE (debug=true): writing to {TEST_TABLE}. {TARGET_TABLE} and {LIVE_PROCEDURE} are not touched.", flush=True)
    else:
        print(f"LIVE MODE (debug=false): data goes to {TARGET_TABLE} via {LIVE_PROCEDURE}.", flush=True)

    check_rows(df, fra, til)

    print("Connecting to the database...", flush=True)
    conn = get_connection()
    try:
        cursor = conn.cursor()
        cursor.fast_executemany = True

        # The test table must be created manually in SQL Server; the script never creates tables
        if is_debug():
            if cursor.execute(f"SELECT OBJECT_ID('{TEST_TABLE}', 'U')").fetchval() is None:
                raise RuntimeError(f"{TEST_TABLE} does not exist. Create it in SQL Server before running in test mode.")
            create_test_procedure(cursor)

        load_temp_table(cursor, df)

        print("Comparing with the rows already in the database...", flush=True)
        status = preview(cursor, procedure, fra, til)
        print(f"  {status.NewRows} new, {status.UnchangedRows} already there, "
              f"{status.MissingRows} in {table} but not in the file", flush=True)

        choice = decide(table, status)
        if choice is None:
            return None  # closing without commit discards everything

        print(f"Saving to {table}...", flush=True)
        started = time.perf_counter()
        result = apply(cursor, procedure, fra, til, delete_missing=(choice == "delete"))

        # Nothing is saved unless everything above succeeded
        conn.commit()
        print(f"  Inserted {result.InsertedRows}, skipped {result.UnchangedRows} existing, "
              f"deleted {result.DeletedRows} in {time.perf_counter() - started:.1f} seconds", flush=True)
        cursor.close()
        return table, result
    finally:
        conn.close()
