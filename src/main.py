import sys
import time
from src.dialogs import choose_xls_file, ask_ja_nej, ask_behold_slet, show_console, show_info
from src.excel import extract_afholdte_vagter, get_period
from src.database import SendExtractedData

EXIT_CANCELLED = 2

# Show an extra warning if more than this share of the table's rows for the period is missing from the file
MANY_MISSING_SHARE = 0.2

def dk(n):
    """9362 -> '9.362'"""
    return f"{n:,}".replace(",", ".")

def make_decide(fra, til, from_file_name):
    """Return the function SendExtractedData uses to ask the user before anything is changed."""
    def decide(table, s):
        latest = s.LatestVagtDato

        # The file starts after the newest data in the table: nothing can have been uploaded before, so just go ahead
        if latest is None or fra > latest:
            print(f"  Latest Vagt_dato in {table}: {latest or 'none'}. No overlap, loading without asking.", flush=True)
            return "keep"

        if s.NewRows == 0 and s.MissingRows == 0:
            print("  Every row in the file is already in the database. Nothing to do.", flush=True)
            show_info("Allerede indlæst", f"Alle {dk(s.FileRows)} rækker i filen findes allerede i {table}.\n\nDer er intet at indlæse.")
            return None

        # Like copying files in Windows: rows that already exist are skipped, new rows are added
        source = "fra filnavnet" if from_file_name else "første og sidste vagtdato, ingen periode i filnavnet"
        warning = (
            f"Databasen har allerede vagter til og med {latest:%d.%m.%Y}, og filens periode starter før.\n"
            "Filen kan allerede være uploadet af en anden."
        )
        message = (
            f"Periode:  {fra:%d.%m.%Y} - {til:%d.%m.%Y}  ({source})\n"
            "\n"
            f"Rækker i filen:  {dk(s.FileRows)}\n"
            f"      Findes allerede:  {dk(s.UnchangedRows)}  (springes over)\n"
            f"      Nye:  {dk(s.NewRows)}  (bliver indsat)\n"
            f"Rækker i {table} for perioden, som ikke er i filen:  {dk(s.MissingRows)}\n"
            "\n"
            "Vagter uden for perioden bliver ikke rørt.\n"
            "\n"
            "Vil du fortsætte?"
        )
        print(f"  Overlaps existing data (latest Vagt_dato: {latest:%d.%m.%Y}). Waiting for answer in the popup window...", flush=True)
        if not ask_ja_nej("Bekræft indlæsning", message, warning=warning):
            print("  Answer: Nej", flush=True)
            return None
        print("  Answer: Ja", flush=True)

        if s.MissingRows == 0:
            return "keep"

        # Rows in the database that the file doesn't have: the user decides, keeping them is the default
        many = s.MissingRows > s.ExistingRows * MANY_MISSING_SHARE
        message = (
            f"{dk(s.MissingRows)} rækker i {table} for perioden {fra:%d.%m.%Y} - {til:%d.%m.%Y} findes ikke i filen.\n"
            "De kan være slettet eller rettet i CareLink siden sidste indlæsning, eller filen kan være ufuldstændig.\n"
            "\n"
            "Behold:  rækkerne bliver i databasen\n"
            "Slet:  rækkerne bliver slettet\n"
            "\n"
            f"Kun vagter fra {fra:%d.%m.%Y} - {til:%d.%m.%Y} kan blive slettet. Vagter uden for perioden bliver ikke rørt."
        )
        warning = "ADVARSEL: Det er mange rækker. Filen kan være et filtreret eller ufuldstændigt udtræk." if many else None
        choice = "delete" if ask_behold_slet("Rækker der ikke er i filen", message, warning=warning) else "keep"
        print(f"  Rows not in the file: {'Slet' if choice == 'delete' else 'Behold'}", flush=True)
        return choice
    return decide

def main():
    # Use the file given on the command line (e.g. dragged onto the .bat), otherwise ask the user
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        print("Choose the Excel file in the window that opened...", flush=True)
        path = choose_xls_file()
        if path is None:
            print("No file selected.", flush=True)
            sys.exit(EXIT_CANCELLED)

    started = time.perf_counter()

    print(f"[1/2] Reading Excel file: {path}", flush=True)
    df = extract_afholdte_vagter(path)
    fra, til, from_file_name = get_period(path, df)
    print(f"  Found {len(df)} rows", flush=True)

    print("[2/2] Sending data to the database", flush=True)
    result = SendExtractedData(df, fra, til, make_decide(fra, til, from_file_name))
    if result is None:
        print("Cancelled.", flush=True)
        sys.exit(EXIT_CANCELLED)

    print(f"Finished in {time.perf_counter() - started:.1f} seconds", flush=True)

    # The .bat closes the window after a success, so tell the user here
    table, r = result
    show_info("Færdig", (
        f"Data er indlæst i {table}.\n"
        "\n"
        f"Periode:  {fra:%d.%m.%Y} - {til:%d.%m.%Y}\n"
        f"Indsat:  {dk(r.InsertedRows)} rækker\n"
        f"Sprunget over (fandtes allerede):  {dk(r.UnchangedRows)} rækker\n"
        f"Slettet:  {dk(r.DeletedRows)} rækker"
    ))

if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise  # cancelled: the window closes quietly
    except BaseException:
        show_console()  # error: bring the window up so the error can be read
        raise
