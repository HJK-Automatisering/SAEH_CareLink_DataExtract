-- Merges the rows the CareLink script uploaded to #TempExtractedData into dbo.VikarData for one period.
--
-- Rows are matched on all 8 columns. Identical rows (several temps on the same shift) are numbered,
-- so 3 identical rows in the file match 3 identical rows in the table one by one.
--   New rows      in the file, not in the table   -> inserted
--   Unchanged     in both                         -> skipped
--   Missing rows  in the table, not in the file   -> kept, or deleted when @DeleteMissing = 1
-- Rows outside the period are never touched.
--
-- Called by the script on the same connection:
--   @Preview = 1  only counts, changes nothing (shown to the user before they choose)
--   @Preview = 0  inserts the new rows and, if @DeleteMissing = 1, deletes the missing rows
-- The script commits only after this succeeds, so a failure leaves VikarData unchanged.
-- In test mode the script runs this same procedure as a temporary copy against dbo.VikarData_Test.

USE Carelink_Data;
GO

CREATE OR ALTER PROCEDURE dbo.ProcessExtractedData
    @Fra           DATE,
    @Til           DATE,
    @Preview       BIT = 1,
    @DeleteMissing BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;  -- any error rolls back everything

    IF OBJECT_ID('tempdb..#TempExtractedData') IS NULL
        THROW 50001, '#TempExtractedData does not exist. Run this procedure from the CareLink script. Nothing was changed.', 1;

    IF @Fra IS NULL OR @Til IS NULL OR @Fra > @Til
        THROW 50002, 'Invalid period. Nothing was changed.', 1;

    IF NOT EXISTS (SELECT 1 FROM #TempExtractedData)
        THROW 50003, 'No rows to load. Nothing was changed.', 1;

    IF EXISTS (SELECT 1 FROM #TempExtractedData WHERE Vagt_dato IS NULL OR Vagt_dato NOT BETWEEN @Fra AND @Til)
        THROW 50004, 'Some rows have a Vagt_dato outside the period. Nothing was changed.', 1;

    IF @Preview = 1
    BEGIN
        WITH f AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY Kundenr, Kunde, Vagt_dato, Lev_periode, Best_dato, Best_tid, Type, Antal_timer ORDER BY (SELECT NULL)) AS Nr
            FROM #TempExtractedData
        ), d AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY Kundenr, Kunde, Vagt_dato, Lev_periode, Best_dato, Best_tid, Type, Antal_timer ORDER BY (SELECT NULL)) AS Nr
            FROM dbo.VikarData
            WHERE Vagt_dato BETWEEN @Fra AND @Til
        )
        SELECT COUNT(f.Nr)                                          AS FileRows,
               COUNT(d.Nr)                                          AS ExistingRows,
               COUNT(CASE WHEN d.Nr IS NULL THEN 1 END)             AS NewRows,
               COUNT(CASE WHEN f.Nr IS NOT NULL AND d.Nr IS NOT NULL THEN 1 END) AS UnchangedRows,
               COUNT(CASE WHEN f.Nr IS NULL THEN 1 END)             AS MissingRows,
               (SELECT MAX(Vagt_dato) FROM dbo.VikarData)           AS LatestVagtDato
        FROM f
        FULL OUTER JOIN d
            ON  f.Kundenr = d.Kundenr AND f.Kunde = d.Kunde AND f.Vagt_dato = d.Vagt_dato AND f.Lev_periode = d.Lev_periode
            AND f.Best_dato = d.Best_dato AND f.Best_tid = d.Best_tid AND f.Type = d.Type AND f.Antal_timer = d.Antal_timer
            AND f.Nr = d.Nr;
        RETURN;
    END

    DECLARE @DeletedRows INT = 0, @InsertedRows INT, @UnchangedRows INT;

    BEGIN TRANSACTION;

        -- A group of identical rows is either short in the file (missing) or short in the table (new), never both,
        -- so deleting before inserting gives the same result as the preview.
        IF @DeleteMissing = 1
        BEGIN
            WITH d AS (
                SELECT *, ROW_NUMBER() OVER (PARTITION BY Kundenr, Kunde, Vagt_dato, Lev_periode, Best_dato, Best_tid, Type, Antal_timer ORDER BY (SELECT NULL)) AS Nr
                FROM dbo.VikarData
                WHERE Vagt_dato BETWEEN @Fra AND @Til
            ), f AS (
                SELECT *, ROW_NUMBER() OVER (PARTITION BY Kundenr, Kunde, Vagt_dato, Lev_periode, Best_dato, Best_tid, Type, Antal_timer ORDER BY (SELECT NULL)) AS Nr
                FROM #TempExtractedData
            )
            DELETE d
            WHERE NOT EXISTS (
                SELECT 1 FROM f
                WHERE f.Kundenr = d.Kundenr AND f.Kunde = d.Kunde AND f.Vagt_dato = d.Vagt_dato AND f.Lev_periode = d.Lev_periode
                  AND f.Best_dato = d.Best_dato AND f.Best_tid = d.Best_tid AND f.Type = d.Type AND f.Antal_timer = d.Antal_timer
                  AND f.Nr = d.Nr
            );
            SET @DeletedRows = @@ROWCOUNT;
        END;

        WITH f AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY Kundenr, Kunde, Vagt_dato, Lev_periode, Best_dato, Best_tid, Type, Antal_timer ORDER BY (SELECT NULL)) AS Nr
            FROM #TempExtractedData
        ), d AS (
            SELECT *, ROW_NUMBER() OVER (PARTITION BY Kundenr, Kunde, Vagt_dato, Lev_periode, Best_dato, Best_tid, Type, Antal_timer ORDER BY (SELECT NULL)) AS Nr
            FROM dbo.VikarData
            WHERE Vagt_dato BETWEEN @Fra AND @Til
        )
        INSERT INTO dbo.VikarData (Kundenr, Kunde, Vagt_dato, Lev_periode, Best_dato, Best_tid, Type, Antal_timer)
        SELECT f.Kundenr, f.Kunde, f.Vagt_dato, f.Lev_periode, f.Best_dato, f.Best_tid, f.Type, f.Antal_timer
        FROM f
        WHERE NOT EXISTS (
            SELECT 1 FROM d
            WHERE f.Kundenr = d.Kundenr AND f.Kunde = d.Kunde AND f.Vagt_dato = d.Vagt_dato AND f.Lev_periode = d.Lev_periode
              AND f.Best_dato = d.Best_dato AND f.Best_tid = d.Best_tid AND f.Type = d.Type AND f.Antal_timer = d.Antal_timer
              AND f.Nr = d.Nr
        );
        SET @InsertedRows = @@ROWCOUNT;

    COMMIT TRANSACTION;

    SET @UnchangedRows = (SELECT COUNT(*) FROM #TempExtractedData) - @InsertedRows;
    SELECT @DeletedRows AS DeletedRows, @InsertedRows AS InsertedRows, @UnchangedRows AS UnchangedRows;
END
GO

-- The script's login only needs to run the procedure; it gets no direct access to VikarData.
GRANT EXECUTE ON dbo.ProcessExtractedData TO [IOD-POWER-READWRITE];
GO
