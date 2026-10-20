/*
    Project: SIM Activation Analytics
    Purpose: Re-create the dbo schema for a fresh/empty SIMActivationDW database.

    IMPORTANT:
    - This script does NOT drop or truncate existing tables.
    - Run only against a fresh/empty database named SIMActivationDW.
    - It creates table structures, keys, unique constraints, and foreign keys.
    - It does not restore data, indexes beyond constraint-backed indexes, or ETL procedure logic.
*/
USE [SIMActivationDW];
GO
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

/* Dimension tables */
CREATE TABLE dbo.DimChannel
(
    ChannelKey  int IDENTITY(1,1) NOT NULL,
    ChannelType nvarchar(100) NOT NULL,
    CONSTRAINT PK_DimChannel PRIMARY KEY CLUSTERED (ChannelKey),
    CONSTRAINT UQ_DimChannel_ChannelType UNIQUE NONCLUSTERED (ChannelType)
);
GO

CREATE TABLE dbo.DimDate
(
    DateKey    int NOT NULL,
    ActiveDate char(10) NOT NULL,
    CONSTRAINT PK_DimDate PRIMARY KEY CLUSTERED (DateKey),
    CONSTRAINT UQ_DimDate_ActiveDate UNIQUE NONCLUSTERED (ActiveDate)
);
GO

CREATE TABLE dbo.DimRegion
(
    RegionKey  int IDENTITY(1,1) NOT NULL,
    RegionName nvarchar(100) NOT NULL,
    CONSTRAINT PK_DimRegion PRIMARY KEY CLUSTERED (RegionKey),
    CONSTRAINT UQ_DimRegion_RegionName UNIQUE NONCLUSTERED (RegionName)
);
GO

/* Fact table */
CREATE TABLE dbo.FactActivation
(
    ActivationKey  bigint IDENTITY(1,1) NOT NULL,
    DateKey        int NOT NULL,
    ChannelKey     int NOT NULL,
    RegionKey      int NOT NULL,
    ActivationCount bigint NOT NULL,
    CONSTRAINT PK_FactActivation PRIMARY KEY CLUSTERED (ActivationKey),
    CONSTRAINT FK_Fact_Date FOREIGN KEY (DateKey)
        REFERENCES dbo.DimDate (DateKey),
    CONSTRAINT FK_Fact_Channel FOREIGN KEY (ChannelKey)
        REFERENCES dbo.DimChannel (ChannelKey),
    CONSTRAINT FK_Fact_Region FOREIGN KEY (RegionKey)
        REFERENCES dbo.DimRegion (RegionKey)
);
GO

/* Source snapshot and staging tables */
CREATE TABLE dbo.ActivationDailySnapshot
(
    ACTIVE_DATE          nvarchar(max) NOT NULL,
    SUBSCRIBER_TYPE       nvarchar(max) NOT NULL,
    PRIMARY_OFFERING_NAME nvarchar(max) NOT NULL,
    REGION_ZONE           nvarchar(max) NOT NULL,
    ACTIVATION_TYPE       nvarchar(max) NOT NULL,
    NUMBER_OF_ACTIVATION  nvarchar(max) NOT NULL,
    OPERATOR_ID           nvarchar(max) NOT NULL,
    DEPARTMENT_NAME       nvarchar(max) NOT NULL,
    CODE                  nvarchar(max) NOT NULL,
    CHANNEL_TYPE          nvarchar(max) NOT NULL,
    NATIONALITY           nvarchar(max) NOT NULL,
    PPS_NAME              nvarchar(max) NULL,
    OFFERING_I             nvarchar(max) NOT NULL,
    SourceFile            nvarchar(260) NULL
);
GO

CREATE TABLE dbo.stg_Activations
(
    ACTIVE_DATE          nvarchar(max) NOT NULL,
    SUBSCRIBER_TYPE       nvarchar(max) NOT NULL,
    PRIMARY_OFFERING_NAME nvarchar(max) NOT NULL,
    REGION_ZONE           nvarchar(max) NOT NULL,
    ACTIVATION_TYPE       nvarchar(max) NOT NULL,
    NUMBER_OF_ACTIVATION  nvarchar(max) NOT NULL,
    OPERATOR_ID           nvarchar(max) NOT NULL,
    DEPARTMENT_NAME       nvarchar(max) NOT NULL,
    CODE                  nvarchar(max) NOT NULL,
    CHANNEL_TYPE          nvarchar(max) NOT NULL,
    NATIONALITY           nvarchar(max) NOT NULL,
    PPS_NAME              nvarchar(max) NULL,
    OFFERING_I             nvarchar(max) NOT NULL,
    SourceFile            nvarchar(260) NULL
);
GO

CREATE TABLE dbo.stg_Activations_Incoming
(
    ACTIVE_DATE          nvarchar(max) NOT NULL,
    SUBSCRIBER_TYPE       nvarchar(max) NOT NULL,
    PRIMARY_OFFERING_NAME nvarchar(max) NOT NULL,
    REGION_ZONE           nvarchar(max) NOT NULL,
    ACTIVATION_TYPE       nvarchar(max) NOT NULL,
    NUMBER_OF_ACTIVATION  nvarchar(max) NOT NULL,
    OPERATOR_ID           nvarchar(max) NOT NULL,
    DEPARTMENT_NAME       nvarchar(max) NOT NULL,
    CODE                  nvarchar(max) NOT NULL,
    CHANNEL_TYPE          nvarchar(max) NOT NULL,
    NATIONALITY           nvarchar(max) NOT NULL,
    PPS_NAME              nvarchar(max) NULL,
    OFFERING_I             nvarchar(max) NOT NULL
);
GO

/* ETL support tables */
CREATE TABLE dbo.ETL_AffectedDates
(
    ActiveDate nvarchar(10) NOT NULL,
    CONSTRAINT PK_ETL_AffectedDates PRIMARY KEY CLUSTERED (ActiveDate)
);
GO

CREATE TABLE dbo.ETL_FileLog
(
    FileLogID    int IDENTITY(1,1) NOT NULL,
    SourceFile   nvarchar(260) NOT NULL,
    ReportDate   date NOT NULL,
    RowsLoaded   bigint NOT NULL,
    LoadDateTime datetime2(7) NOT NULL
        CONSTRAINT DF_ETL_FileLog_LoadDateTime DEFAULT (sysdatetime()),
    LoadStatus   nvarchar(20) NOT NULL,
    Notes        nvarchar(500) NULL,
    CONSTRAINT PK_ETL_FileLog PRIMARY KEY CLUSTERED (FileLogID),
    CONSTRAINT UQ_ETL_FileLog_SourceFile UNIQUE NONCLUSTERED (SourceFile)
);
GO

CREATE TABLE dbo.ETL_RunLog
(
    RunID         bigint IDENTITY(1,1) NOT NULL,
    StartTime     datetime2(7) NOT NULL
        CONSTRAINT DF_ETL_RunLog_StartTime DEFAULT (sysdatetime()),
    EndTime       datetime2(7) NULL,
    RunStatus     nvarchar(20) NOT NULL,
    FilesProcessed int NOT NULL
        CONSTRAINT DF_ETL_RunLog_FilesProcessed DEFAULT ((0)),
    DatesRefreshed int NOT NULL
        CONSTRAINT DF_ETL_RunLog_DatesRefreshed DEFAULT ((0)),
    ErrorMessage  nvarchar(4000) NULL,
    CONSTRAINT PK_ETL_RunLog PRIMARY KEY CLUSTERED (RunID)
);
GO

/*
    Notes from metadata inspection:
    - No CHECK constraints or table triggers were found.
    - Staging and snapshot tables have no primary/unique constraints in the inspected schema.
    - Identity current values and table data are intentionally not reproduced by this schema script.
*/
