USE [SIMActivationDW];
GO

CREATE OR ALTER PROCEDURE dbo.usp_ProcessIncomingActivationFile
    @SourceFile NVARCHAR(260)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RunID BIGINT;
    DECLARE @RowsLoaded BIGINT;
    DECLARE @ReportDate DATE;
    DECLARE @DatesRefreshed INT = 0;
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @ReportTimestamp DATETIME2;

    INSERT INTO dbo.ETL_RunLog (RunStatus)
    VALUES (N'Running');

    SET @RunID = SCOPE_IDENTITY();

    BEGIN TRY
        IF NULLIF(LTRIM(RTRIM(@SourceFile)), N'') IS NULL
            THROW 50001, 'Source filename is required.', 1;

        -- Current input filenames contain a timestamp such as _20220418100735.
        -- This parser currently expects the timestamp year to begin with _2022.
        IF CHARINDEX('_2022', @SourceFile) = 0
            THROW 50002, 'Filename does not contain the expected report timestamp.', 1;

        SET @ReportDate = TRY_CONVERT(
            DATE,
            SUBSTRING(
                @SourceFile,
                CHARINDEX('_2022', @SourceFile) + 1,
                8
            ),
            112
        );

        SET @ReportTimestamp = TRY_CONVERT(
            DATETIME2,
            LEFT(
                SUBSTRING(
                    @SourceFile,
                    CHARINDEX('_2022', @SourceFile) + 1,
                    14
                ),
                8
            ) + ' ' +
            STUFF(
                STUFF(
                    RIGHT(
                        SUBSTRING(
                            @SourceFile,
                            CHARINDEX('_2022', @SourceFile) + 1,
                            14
                        ),
                        6
                    ),
                    3, 0, ':'
                ),
                6, 0, ':'
            )
        );

        IF @ReportDate IS NULL OR @ReportTimestamp IS NULL
            THROW 50003, 'Could not parse report date and timestamp.', 1;

        BEGIN TRANSACTION;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.ETL_FileLog WITH (UPDLOCK, HOLDLOCK)
            WHERE SourceFile = @SourceFile
        )
            THROW 50004, 'This source file has already been registered.', 1;

        SELECT @RowsLoaded = COUNT_BIG(*)
        FROM dbo.stg_Activations_Incoming;

        IF @RowsLoaded = 0
            THROW 50005, 'Incoming staging table is empty.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.stg_Activations_Incoming
            WHERE TRY_CONVERT(BIGINT, NUMBER_OF_ACTIVATION) IS NULL
               OR LEN(ACTIVE_DATE) <> 10
               OR SUBSTRING(ACTIVE_DATE, 5, 1) <> '/'
               OR SUBSTRING(ACTIVE_DATE, 8, 1) <> '/'
               OR TRY_CONVERT(INT, REPLACE(ACTIVE_DATE, '/', '')) IS NULL
        )
            THROW 50006, 'Incoming file contains invalid dates or activation counts.', 1;

        IF EXISTS
        (
            SELECT 1
            FROM dbo.stg_Activations_Incoming
            WHERE NULLIF(LTRIM(RTRIM(CHANNEL_TYPE)), N'') IS NULL
               OR NULLIF(LTRIM(RTRIM(REGION_ZONE)), N'') IS NULL
        )
            THROW 50007, 'Incoming file contains blank channel or region values.', 1;

        CREATE TABLE #AffectedDates
        (
            ActiveDate NVARCHAR(10) NOT NULL PRIMARY KEY
        );

        INSERT INTO #AffectedDates (ActiveDate)
        SELECT DISTINCT ACTIVE_DATE
        FROM dbo.stg_Activations_Incoming;

        INSERT INTO dbo.stg_Activations
        (
            ACTIVE_DATE, SUBSCRIBER_TYPE, PRIMARY_OFFERING_NAME,
            REGION_ZONE, ACTIVATION_TYPE, NUMBER_OF_ACTIVATION,
            OPERATOR_ID, DEPARTMENT_NAME, CODE, CHANNEL_TYPE,
            NATIONALITY, PPS_NAME, OFFERING_I, SourceFile
        )
        SELECT
            ACTIVE_DATE, SUBSCRIBER_TYPE, PRIMARY_OFFERING_NAME,
            REGION_ZONE, ACTIVATION_TYPE, NUMBER_OF_ACTIVATION,
            OPERATOR_ID, DEPARTMENT_NAME, CODE, CHANNEL_TYPE,
            NATIONALITY, PPS_NAME, OFFERING_I, @SourceFile
        FROM dbo.stg_Activations_Incoming;

        DELETE snap
        FROM dbo.ActivationDailySnapshot AS snap
        INNER JOIN #AffectedDates AS a
            ON a.ActiveDate = snap.ACTIVE_DATE;

        ;WITH LatestFile AS
        (
            SELECT
                s.ACTIVE_DATE,
                s.SourceFile,
                ROW_NUMBER() OVER
                (
                    PARTITION BY s.ACTIVE_DATE
                    ORDER BY
                        TRY_CONVERT(
                            DATETIME2,
                            LEFT(
                                SUBSTRING(
                                    s.SourceFile,
                                    CHARINDEX('_2022', s.SourceFile) + 1,
                                    14
                                ),
                                8
                            ) + ' ' +
                            STUFF(
                                STUFF(
                                    RIGHT(
                                        SUBSTRING(
                                            s.SourceFile,
                                            CHARINDEX('_2022', s.SourceFile) + 1,
                                            14
                                        ),
                                        6
                                    ),
                                    3, 0, ':'
                                ),
                                6, 0, ':'
                            )
                        ) DESC,
                        s.SourceFile DESC
                ) AS rn
            FROM dbo.stg_Activations AS s
            INNER JOIN #AffectedDates AS a
                ON a.ActiveDate = s.ACTIVE_DATE
            GROUP BY s.ACTIVE_DATE, s.SourceFile
        )
        INSERT INTO dbo.ActivationDailySnapshot
        (
            ACTIVE_DATE, SUBSCRIBER_TYPE, PRIMARY_OFFERING_NAME,
            REGION_ZONE, ACTIVATION_TYPE, NUMBER_OF_ACTIVATION,
            OPERATOR_ID, DEPARTMENT_NAME, CODE, CHANNEL_TYPE,
            NATIONALITY, PPS_NAME, OFFERING_I, SourceFile
        )
        SELECT
            s.ACTIVE_DATE, s.SUBSCRIBER_TYPE, s.PRIMARY_OFFERING_NAME,
            s.REGION_ZONE, s.ACTIVATION_TYPE, s.NUMBER_OF_ACTIVATION,
            s.OPERATOR_ID, s.DEPARTMENT_NAME, s.CODE, s.CHANNEL_TYPE,
            s.NATIONALITY, s.PPS_NAME, s.OFFERING_I, s.SourceFile
        FROM dbo.stg_Activations AS s
        INNER JOIN LatestFile AS lf
            ON lf.ACTIVE_DATE = s.ACTIVE_DATE
           AND lf.SourceFile = s.SourceFile
           AND lf.rn = 1
        INNER JOIN #AffectedDates AS a
            ON a.ActiveDate = s.ACTIVE_DATE;

        INSERT INTO dbo.DimDate (DateKey, ActiveDate)
        SELECT DISTINCT
            TRY_CONVERT(INT, REPLACE(s.ACTIVE_DATE, '/', '')),
            s.ACTIVE_DATE
        FROM dbo.ActivationDailySnapshot AS s
        INNER JOIN #AffectedDates AS a
            ON a.ActiveDate = s.ACTIVE_DATE
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.DimDate AS d
            WHERE d.ActiveDate = s.ACTIVE_DATE
        );

        INSERT INTO dbo.DimChannel (ChannelType)
        SELECT DISTINCT s.CHANNEL_TYPE
        FROM dbo.ActivationDailySnapshot AS s
        INNER JOIN #AffectedDates AS a
            ON a.ActiveDate = s.ACTIVE_DATE
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.DimChannel AS d
            WHERE d.ChannelType = s.CHANNEL_TYPE
        );

        INSERT INTO dbo.DimRegion (RegionName)
        SELECT DISTINCT s.REGION_ZONE
        FROM dbo.ActivationDailySnapshot AS s
        INNER JOIN #AffectedDates AS a
            ON a.ActiveDate = s.ACTIVE_DATE
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dbo.DimRegion AS d
            WHERE d.RegionName = s.REGION_ZONE
        );

        DELETE f
        FROM dbo.FactActivation AS f
        INNER JOIN dbo.DimDate AS d
            ON d.DateKey = f.DateKey
        INNER JOIN #AffectedDates AS a
            ON a.ActiveDate = d.ActiveDate;

        -- Aggregate to one row per date, channel, and region.
        INSERT INTO dbo.FactActivation
        (
            DateKey, ChannelKey, RegionKey, ActivationCount
        )
        SELECT
            d.DateKey,
            c.ChannelKey,
            r.RegionKey,
            SUM(TRY_CONVERT(BIGINT, s.NUMBER_OF_ACTIVATION))
        FROM dbo.ActivationDailySnapshot AS s
        INNER JOIN #AffectedDates AS a
            ON a.ActiveDate = s.ACTIVE_DATE
        INNER JOIN dbo.DimDate AS d
            ON d.ActiveDate = s.ACTIVE_DATE
        INNER JOIN dbo.DimChannel AS c
            ON c.ChannelType = s.CHANNEL_TYPE
        INNER JOIN dbo.DimRegion AS r
            ON r.RegionName = s.REGION_ZONE
        GROUP BY
            d.DateKey, c.ChannelKey, r.RegionKey;

        -- Verify activation totals for each affected date.
        IF EXISTS
        (
            SELECT 1
            FROM #AffectedDates AS a
            WHERE COALESCE(
                (
                    SELECT SUM(TRY_CONVERT(BIGINT, s.NUMBER_OF_ACTIVATION))
                    FROM dbo.ActivationDailySnapshot AS s
                    WHERE s.ACTIVE_DATE = a.ActiveDate
                ), 0
            ) <>
            COALESCE(
                (
                    SELECT SUM(f.ActivationCount)
                    FROM dbo.FactActivation AS f
                    INNER JOIN dbo.DimDate AS d
                        ON d.DateKey = f.DateKey
                    WHERE d.ActiveDate = a.ActiveDate
                ), 0
            )
        )
            THROW 50008, 'Snapshot and fact activation totals do not match.', 1;

        -- Verify uniqueness of the fact grain.
        IF EXISTS
        (
            SELECT f.DateKey, f.ChannelKey, f.RegionKey
            FROM dbo.FactActivation AS f
            INNER JOIN dbo.DimDate AS d
                ON d.DateKey = f.DateKey
            INNER JOIN #AffectedDates AS a
                ON a.ActiveDate = d.ActiveDate
            GROUP BY f.DateKey, f.ChannelKey, f.RegionKey
            HAVING COUNT_BIG(*) > 1
        )
            THROW 50009, 'Duplicate date-channel-region combinations found.', 1;

        SELECT @DatesRefreshed = COUNT(*)
        FROM #AffectedDates;

        INSERT INTO dbo.ETL_FileLog
        (
            SourceFile, ReportDate, RowsLoaded, LoadStatus, Notes
        )
        VALUES
        (
            @SourceFile,
            @ReportDate,
            @RowsLoaded,
            N'Completed',
            N'Loaded successfully; affected dates rebuilt using the latest report timestamp. Fact rows aggregated by date, channel, and region.'
        );

        TRUNCATE TABLE dbo.stg_Activations_Incoming;

        UPDATE dbo.ETL_RunLog
        SET
            EndTime = SYSDATETIME(),
            RunStatus = N'Succeeded',
            FilesProcessed = 1,
            DatesRefreshed = @DatesRefreshed
        WHERE RunID = @RunID;

        COMMIT TRANSACTION;

        SELECT
            @RunID AS RunID,
            @RowsLoaded AS RowsLoaded,
            @DatesRefreshed AS DatesRefreshed,
            N'Succeeded' AS RunStatus;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0
            ROLLBACK TRANSACTION;

        SET @ErrorMessage = ERROR_MESSAGE();

        UPDATE dbo.ETL_RunLog
        SET
            EndTime = SYSDATETIME(),
            RunStatus = N'Failed',
            ErrorMessage = @ErrorMessage
        WHERE RunID = @RunID;

        THROW;
    END CATCH
END;
GO
