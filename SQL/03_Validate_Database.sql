/*
    Project: SIM Activation Analytics
    Purpose: Read-only validation checks for SIMActivationDW.

    Safe to run against the existing database: SELECT statements only.
    Review the results rather than expecting every count to remain fixed as data changes.
*/
USE [SIMActivationDW];
GO
SET NOCOUNT ON;
GO

PRINT '1. Row counts for core project tables';
SELECT 'ActivationDailySnapshot' AS TableName, COUNT_BIG(*) AS RowCount FROM dbo.ActivationDailySnapshot
UNION ALL SELECT 'DimChannel', COUNT_BIG(*) FROM dbo.DimChannel
UNION ALL SELECT 'DimDate', COUNT_BIG(*) FROM dbo.DimDate
UNION ALL SELECT 'DimRegion', COUNT_BIG(*) FROM dbo.DimRegion
UNION ALL SELECT 'ETL_AffectedDates', COUNT_BIG(*) FROM dbo.ETL_AffectedDates
UNION ALL SELECT 'ETL_FileLog', COUNT_BIG(*) FROM dbo.ETL_FileLog
UNION ALL SELECT 'ETL_RunLog', COUNT_BIG(*) FROM dbo.ETL_RunLog
UNION ALL SELECT 'FactActivation', COUNT_BIG(*) FROM dbo.FactActivation
UNION ALL SELECT 'stg_Activations', COUNT_BIG(*) FROM dbo.stg_Activations
UNION ALL SELECT 'stg_Activations_Incoming', COUNT_BIG(*) FROM dbo.stg_Activations_Incoming
ORDER BY TableName;
GO

PRINT '2. Fact table total activation count';
SELECT SUM(ActivationCount) AS TotalActivationCount
FROM dbo.FactActivation;
GO

PRINT '3. Duplicate fact grain check: DateKey + ChannelKey + RegionKey';
SELECT DateKey, ChannelKey, RegionKey, COUNT_BIG(*) AS DuplicateRows
FROM dbo.FactActivation
GROUP BY DateKey, ChannelKey, RegionKey
HAVING COUNT_BIG(*) > 1;
GO

PRINT '4. Foreign-key orphan checks (each result should be empty)';
SELECT f.ActivationKey, f.DateKey
FROM dbo.FactActivation AS f
LEFT JOIN dbo.DimDate AS d ON d.DateKey = f.DateKey
WHERE d.DateKey IS NULL;

SELECT f.ActivationKey, f.ChannelKey
FROM dbo.FactActivation AS f
LEFT JOIN dbo.DimChannel AS c ON c.ChannelKey = f.ChannelKey
WHERE c.ChannelKey IS NULL;

SELECT f.ActivationKey, f.RegionKey
FROM dbo.FactActivation AS f
LEFT JOIN dbo.DimRegion AS r ON r.RegionKey = f.RegionKey
WHERE r.RegionKey IS NULL;
GO

PRINT '5. Snapshot activation total using safe numeric conversion';
SELECT
    COUNT_BIG(*) AS SnapshotRows,
    SUM(TRY_CONVERT(bigint, NUMBER_OF_ACTIVATION)) AS SnapshotActivationTotal,
    SUM(CASE WHEN TRY_CONVERT(bigint, NUMBER_OF_ACTIVATION) IS NULL THEN 1 ELSE 0 END) AS NonNumericActivationValues
FROM dbo.ActivationDailySnapshot;
GO

PRINT '6. Recent ETL run history';
SELECT TOP (20)
    RunID, StartTime, EndTime, RunStatus,
    FilesProcessed, DatesRefreshed, ErrorMessage
FROM dbo.ETL_RunLog
ORDER BY RunID DESC;
GO

PRINT '7. Recent file load history';
SELECT TOP (20)
    FileLogID, SourceFile, ReportDate, RowsLoaded,
    LoadDateTime, LoadStatus, Notes
FROM dbo.ETL_FileLog
ORDER BY FileLogID DESC;
GO
