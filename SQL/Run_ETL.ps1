$ErrorActionPreference = "Stop"

# Production ETL - connects to SIMActivationDW.
$connectionString = "Server=DESKTOP-LDNBD3P\SQLEXPRESS;Database=SIMActivationDW;Integrated Security=True;TrustServerCertificate=True"
$sourceFolder = "E:\Projects\SIM_Activation_Project\Data\Source"
$processedFolder = "E:\Projects\SIM_Activation_Project\Data\Processed"
$failedFolder = "E:\Projects\SIM_Activation_Project\Data\Failed"
$logFolder = "E:\Projects\SIM_Activation_Project\Data\Logs"

$columns = @(
    "ACTIVE_DATE",
    "SUBSCRIBER_TYPE",
    "PRIMARY_OFFERING_NAME",
    "REGION_ZONE",
    "ACTIVATION_TYPE",
    "NUMBER_OF_ACTIVATION",
    "OPERATOR_ID",
    "DEPARTMENT_NAME",
    "CODE",
    "CHANNEL_TYPE",
    "NATIONALITY",
    "PPS_NAME",
    "OFFERING_I"
)

# Create folders if missing.
foreach ($folder in @(
    $sourceFolder,
    $processedFolder,
    $failedFolder,
    $logFolder
)) {
    if (!(Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force |
            Out-Null
    }
}

$logFile = Join-Path $logFolder (
    "ETL_" + (Get-Date -Format "yyyyMMdd") + ".log"
)

function Write-ETLLog {
    param([string]$Message)

    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | $Message"

    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    Write-Host $line
}

$connection = New-Object System.Data.SqlClient.SqlConnection(
    $connectionString
)

try {
    $connection.Open()
    Write-ETLLog "Connected to SIMActivationDW."

    $files = @(
        Get-ChildItem -LiteralPath $sourceFolder -Filter "*.csv" -File |
            Sort-Object Name
    )

    if ($files.Count -eq 0) {
        Write-ETLLog "No CSV files found."
    }

    foreach ($file in $files) {
        Write-ETLLog "Checking file: $($file.Name)"

        # 1. Skip files already registered in SQL.
        $check = $connection.CreateCommand()

        try {
            $check.CommandText = @"
SELECT COUNT(*)
FROM dbo.ETL_FileLog
WHERE SourceFile = @FileName
"@

            [void]$check.Parameters.Add(
                "@FileName",
                [System.Data.SqlDbType]::NVarChar,
                260
            )

            $check.Parameters["@FileName"].Value = $file.Name

            $exists = [int]$check.ExecuteScalar()
        }
        finally {
            $check.Dispose()
        }

        if ($exists -gt 0) {
            Write-ETLLog "Already registered; skipped."
            continue
        }

        # 2. Validate the filename.
        # Expected suffix: _YYYYMMDDHHMMSS.csv
        if ($file.Name -notmatch '_2022\d{10}\.csv$') {
            Write-ETLLog "ERROR: Invalid filename; file left in Source."
            throw "Unexpected filename format: $($file.Name)"
        }

        $data = $null
        $bulkCopy = $null

        # True only after confirming the incoming table was empty
        # before this file started loading.
        $incomingWasEmpty = $false

        try {
            # 3. Read the CSV.
            $rows = @(
                Import-Csv -LiteralPath $file.FullName -Encoding UTF8
            )

            if ($rows.Count -eq 0) {
                throw "CSV contains no data rows."
            }

            # 4. Validate required columns.
            $actualColumns = @(
                $rows[0].PSObject.Properties.Name
            )

            foreach ($column in $columns) {
                if ($column -notin $actualColumns) {
                    throw "Missing CSV column: $column"
                }
            }

            # 5. Build an in-memory table.
            $data = New-Object System.Data.DataTable

            foreach ($column in $columns) {
                [void]$data.Columns.Add($column, [string])
            }

            foreach ($row in $rows) {
                $newRow = $data.NewRow()

                foreach ($column in $columns) {
                    $value = $row.$column

                    if ($null -eq $value) {
                        if ($column -eq "PPS_NAME") {
                            $newRow[$column] = [DBNull]::Value
                        }
                        else {
                            throw "Missing value in required column: $column"
                        }
                    }
                    else {
                        $newRow[$column] = [string]$value
                    }
                }

                [void]$data.Rows.Add($newRow)
            }

            Write-ETLLog "Rows read: $($data.Rows.Count)"

            # 6. Never overwrite existing incoming data.
            $check = $connection.CreateCommand()

            try {
                $check.CommandText = @"
SELECT COUNT_BIG(*)
FROM dbo.stg_Activations_Incoming
"@

                $incomingCount = [long]$check.ExecuteScalar()
            }
            finally {
                $check.Dispose()
            }

            if ($incomingCount -ne 0) {
                throw "Incoming table is not empty. Manual inspection required."
            }

            # It is now safe to clear this table if our own load fails,
            # because it was confirmed empty before loading began.
            $incomingWasEmpty = $true

            # 7. Bulk load into incoming staging.
            $bulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy(
                $connection
            )

            $bulkCopy.DestinationTableName = "dbo.stg_Activations_Incoming"
            $bulkCopy.BatchSize = 5000
            $bulkCopy.BulkCopyTimeout = 0

            foreach ($column in $columns) {
                [void]$bulkCopy.ColumnMappings.Add(
                    $column,
                    $column
                )
            }

            $bulkCopy.WriteToServer($data)
            $bulkCopy.Dispose()
            $bulkCopy = $null

            Write-ETLLog "Incoming staging loaded."

            # 8. Run the SQL ETL procedure.
            $command = $connection.CreateCommand()
            $command.CommandTimeout = 0

            try {
                $command.CommandText = @"
EXEC dbo.usp_ProcessIncomingActivationFile @SourceFile
"@

                [void]$command.Parameters.Add(
                    "@SourceFile",
                    [System.Data.SqlDbType]::NVarChar,
                    260
                )

                $command.Parameters["@SourceFile"].Value = $file.Name

                $reader = $command.ExecuteReader()

                try {
                    do {
                        while ($reader.Read()) {
                            Write-ETLLog (
                                "ETL result: RunID={0}; RowsLoaded={1}; DatesRefreshed={2}; Status={3}" -f
                                $reader["RunID"],
                                $reader["RowsLoaded"],
                                $reader["DatesRefreshed"],
                                $reader["RunStatus"]
                            )
                        }
                    } while ($reader.NextResult())
                }
                finally {
                    $reader.Dispose()
                }
            }
            finally {
                $command.Dispose()
            }

            Write-ETLLog "ETL procedure completed successfully."
        }
        catch {
            $errorMessage = $_.Exception.Message

            Write-ETLLog (
                "ERROR processing {0}: {1}" -f
                $file.Name,
                $errorMessage
            )

            # Clear incoming only if this run confirmed it was empty
            # before starting its own load.
            if ($incomingWasEmpty) {
                $cleanup = $null

                try {
                    $cleanup = $connection.CreateCommand()
                    $cleanup.CommandText = @"
TRUNCATE TABLE dbo.stg_Activations_Incoming
"@

                    [void]$cleanup.ExecuteNonQuery()

                    Write-ETLLog "Incoming staging cleared after error."
                }
                catch {
                    Write-ETLLog (
                        "CRITICAL: Could not clear incoming staging. " +
                        "Inspect the database before another run."
                    )
                }
                finally {
                    if ($null -ne $cleanup) {
                        $cleanup.Dispose()
                    }
                }
            }
            else {
                Write-ETLLog (
                    "Incoming staging was not confirmed empty; " +
                    "no automatic cleanup performed."
                )
            }

            # Keep the failed file in Source for investigation.
            # Stop processing so the error cannot go unnoticed.
            throw
        }
        finally {
            if ($null -ne $bulkCopy) {
                $bulkCopy.Dispose()
            }

            if ($null -ne $data) {
                $data.Dispose()
            }
        }

        # 9. Move the file only after successful procedure execution.
        $processedPath = Join-Path $processedFolder $file.Name

        try {
            Move-Item `
                -LiteralPath $file.FullName `
                -Destination $processedPath `
                -ErrorAction Stop

            Write-ETLLog "Moved to Processed: $processedPath"
        }
        catch {
            Write-ETLLog (
                "WARNING: ETL succeeded but file movement failed. " +
                "SQL registration will prevent duplicate loading."
            )
        }
    }
}
catch {
    Write-ETLLog "ETL scan stopped: $($_.Exception.Message)"
    throw
}
finally {
    if ($connection.State -ne [System.Data.ConnectionState]::Closed) {
        $connection.Close()
    }

    $connection.Dispose()
}

Write-ETLLog "ETL scan finished."

