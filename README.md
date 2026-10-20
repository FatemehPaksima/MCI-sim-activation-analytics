# MCI SIM Activation Analytics

**An end-to-end analytics workflow for daily SIM activation reporting using SQL Server, PowerShell, and Power BI.**

This project demonstrates how recurring CSV reports can be ingested, validated, organized in a relational warehouse, and presented through an interactive management dashboard. It combines data warehousing, ETL orchestration, file-level audit controls, and business intelligence in one portfolio project.

> **Environment note:** This is a local SQL Server Express implementation developed for a scholarship skills assessment. It is not a live telecom production deployment.

## Project Overview

Daily SIM activation reports arrive as CSV files and need to be made consistent and accessible for analysis. This project implements a workflow that:

- Loads report files into SQL Server staging tables.
- Maintains source-level history and a daily snapshot.
- Builds an aggregated fact table connected to date, channel, and region dimensions.
- Uses PowerShell to coordinate file discovery, loading, stored-procedure execution, logging, and file routing.
- Uses Windows Task Scheduler to run the ETL workflow on a daily schedule.
- Presents activation trends and channel/region comparisons in Power BI.

## Architecture

```text
Daily CSV Reports
       |
       v
PowerShell ETL Orchestrator
       |
       +----> File discovery and duplicate-file check
       |
       v
SQL Server Incoming Staging
       |
       v
Stored Procedure: usp_ProcessIncomingActivationFile
       |
       +----> Source Staging History
       +----> Activation Daily Snapshot
       +----> Dimension Tables
       +----> FactActivation
       +----> ETL Run and File Logs
       |
       v
Power BI Management Dashboard
```

## Technology Stack

- **Microsoft SQL Server Express** — relational warehouse and SQL-based transformations
- **T-SQL** — schema objects, stored procedure processing, validation queries, and audit logging
- **PowerShell** — ETL orchestration and file handling
- **Windows Task Scheduler** — scheduled execution
- **Microsoft Power BI** — interactive dashboard and KPI reporting
- **Git / GitHub** — version control and project documentation

## Data Model

The reporting model follows a star-schema approach:

- **FactActivation** — aggregated activation measure and foreign keys to descriptive dimensions.
- **DimDate** — date context for time-based reporting.
- **DimChannel** — channel categories.
- **DimRegion** — regional categories.

The documented fact grain is one row per unique combination of `DateKey`, `ChannelKey`, and `RegionKey`. The source snapshot retains report-level attributes, while the fact table supports aggregated reporting.

In the source snapshot, `NUMBER_OF_ACTIVATION` is stored as text; numeric summaries therefore use safe conversion such as `TRY_CONVERT` where appropriate.

## ETL Workflow

The PowerShell orchestration script (`Run_ETL.ps1`) coordinates the following steps:

1. Discover eligible CSV report files in the source folder.
2. Check file history and skip files already registered as completed.
3. Load the current file into `dbo.stg_Activations_Incoming`.
4. Invoke `dbo.usp_ProcessIncomingActivationFile` to process incoming data and refresh affected reporting data.
5. Record processing details and status in ETL logs.
6. Route processed files to the appropriate processed or failed folder according to the script.
7. Record scan completion in the ETL log output.

The workflow is configured for daily execution through Windows Task Scheduler. File-level history and duplicate checks are intended to prevent completed files from being loaded again.

## Power BI Dashboard

The dashboard provides interactive analysis through date, channel, and region filters. Its documented components include:

- **Peak Daily Activations** — highest daily activation count in the current filter context.
- **Average Daily Activations** — average daily activation volume.
- **Total Activations** — total activation volume under the selected filters.
- **Total Channels** — number of channel categories represented by the KPI.
- **Active Days** — number of reporting days represented in the selected context.
- **Daily Activations Trend** — activation values over time.
- **Regional Performance Analysis** — scatter-chart comparison of regions.
- **Activation Share by Channel** — channel share shown as a donut chart.
- **ActivationCount by Region** — regional comparison shown as a treemap.

KPI values and visuals respond to the active slicer selections.

## Validation and Testing

The project documentation records the following results:

### Main warehouse

- `dbo.FactActivation`: **1,444 rows**, with `SUM(ActivationCount) = 531,040`.
- `dbo.ActivationDailySnapshot`: **186,156 rows**, with safely converted activation totals of **531,040**.
- `dbo.ETL_FileLog`: **12 records** at the time of inspection.
- The recorded fact-grain check found no duplicate `DateKey × ChannelKey × RegionKey` combinations.
- The post-edit scheduled run completed its scan and skipped the 12 previously registered files.

### Isolated new-file test

A controlled end-to-end test was performed in the separate validation database `SIMActivationDW_ETLValidation`, not in the main warehouse:

- **88,884** source rows processed successfully.
- The procedure reported `RunID = 6`, `RowsLoaded = 88,884`, `DatesRefreshed = 10`, and `Status = Succeeded`.
- Fact and snapshot activation totals both equaled **528,043** in that validation database.
- Incoming staging was empty after successful processing.
- The same file was skipped on rerun because it had already been registered.

These are recorded validation results for the project state at the time of documentation; main-warehouse and isolated-test totals describe separate database states.

## Repository Structure

The intended repository organization is:

```text
.
├── SQL_Scripts/
│   ├── 01_Create_Database_Schema.sql
│   ├── 02_Create_usp_ProcessIncomingActivationFile.sql
│   └── 03_Validate_Database.sql
├── Data/
│   └── Run_ETL.ps1
├── Documentation/
│   └── MCI_SIM_Activation_Technical_Documentation_Final.docx
├── PowerBI/
│   └── MCI_SIM_Activation_Dashboard.pbix
├── .gitignore
└── README.md
```

Folder and file names may differ in the working copy. Keep actual raw reports, database files, logs, and local machine-specific configuration out of the public repository. The diagram above describes the intended organization, not a guarantee that every listed file is already tracked.

## Getting Started

This project is designed for a local Windows environment. To review or reproduce it:

1. Install or configure SQL Server Express and SQL Server Management Studio.
2. Review the SQL scripts before running them.
3. Run the schema script **only against a fresh/empty database** named `SIMActivationDW`. It creates schema objects; it does not restore project data.
4. Review the stored procedure script and create the procedure in the intended database.
5. Configure `Run_ETL.ps1` for the local SQL Server instance and project paths before running it.
6. Place an appropriate input CSV in the configured source folder and verify the expected filename format.
7. Run the ETL script in a controlled environment and inspect its logs and database validation results.
8. Open the Power BI `.pbix` file and configure the data source connection for the local environment.

**Important:** Do not run setup scripts against a populated database without reviewing their effects first. Do not publish real source CSVs, database files, credentials, connection strings containing private details, or unreviewed logs.

## Known Scope and Limitations

- The implementation is a local SQL Server Express portfolio project, not a production deployment.
- Dashboard values are filter-dependent.
- Source activation counts are stored as text in the snapshot and require safe numeric conversion for aggregation.
- Main-warehouse checks and isolated new-file testing were performed against separate databases; their totals must not be conflated.
- Before reproducing the project on another machine, verify local paths, SQL Server connection settings, source-file naming conventions, and Task Scheduler configuration.

## Project Deliverables

- SQL schema and validation scripts
- Stored procedure for incoming activation processing
- PowerShell ETL orchestration script
- Power BI management dashboard
- Technical documentation covering the architecture, ETL workflow, dashboard, and recorded validation results

## Author / Portfolio

Prepared as a technical portfolio project for scholarship skills assessment.

If you use this repository as a reference, review the scripts and environment assumptions before running them.
