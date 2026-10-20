
$ErrorActionPreference = "Stop"

# TEST MODE: all database changes will be rolled back.
$DryRun = $false

$sourceFolder = "E:\Projects\SIM_Activation_Project\Data\Source"
$connectionString = "Server=DESKTOP-LDNBD3P\SQLEXPRESS;Database=SIMActivationDW_Test;Integrated Security=True;TrustServerCertificate=True"

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

if (!(Test-Path $sourceFolder)) {
    throw "Source folder not found: $sourceFolder"
}

$connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
$connection.Open()

try {
    $files = Get-ChildItem -Path $sourceFolder -Filter "*.csv" -File |
        Sort-Object Name

    foreach ($file in $files) {
        $transaction = $null
        $bulkCopy = $null
        $data = $null

        Write-Host "`nChecking: $($file.Name)"

        $check = $connection.CreateCommand()
        $check.CommandText = @"
SELECT COUNT(*)
FROM dbo.ETL_FileLog
WHERE SourceFile = @FileName;
"@
        [void]$check.Parameters.Add(
            "@FileName",
            [System.Data.SqlDbType]::NVarChar,
            260
        )
        $check.Parameters["@FileName"].Value = $file.Name

        try {
            $exists = [int]$check.ExecuteScalar()
        }
        finally {
            $check.Dispose()
        }

        if ($exists -gt 0) {
            Write-Host "Already registered - skipped."
            continue
        }

        if ($file.Name -notmatch '_2022\d{10}\.csv$') {
            Write-Warning "Unexpected filename format - skipped."
            continue
        }

        Write-Host "New file detected: $($file.Name)"

        try {
            $rows = @(Import-Csv -LiteralPath $file.FullName -Encoding UTF8)

            if ($rows.Count -eq 0) {
                throw "CSV contains no data rows."
            }

            $actualColumns = @($rows[0].PSObject.Properties.Name)

            foreach ($column in $columns) {
                if ($column -notin $actualColumns) {
                    throw "Missing CSV column: $column"
                }
            }

            $data = New-Object System.Data.DataTable

            foreach ($column in $columns) {
                [void]$data.Columns.Add(
                    $column,
                    [string]
                )
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

            Write-Host "Rows read: $($data.Rows.Count)"

            $transaction = $connection.BeginTransaction()

            # Incoming staging must be empty before loading.
            $check = $connection.CreateCommand()
            $check.Transaction = $transaction
            $check.CommandText = "SELECT COUNT_BIG(*) FROM dbo.stg_Activations_Incoming;"

            try {
                $incomingCount = [long]$check.ExecuteScalar()
            }
            finally {
                $check.Dispose()
            }

            if ($incomingCount -ne 0) {
                throw "Incoming staging is not empty. Stopped for safety."
            }

            $bulkCopy = [System.Data.SqlClient.SqlBulkCopy]::new(
                $connection,
                [System.Data.SqlClient.SqlBulkCopyOptions]::CheckConstraints,
                $transaction
            )

            $bulkCopy.DestinationTableName = "dbo.stg_Activations_Incoming"
            $bulkCopy.BatchSize = 5000
            $bulkCopy.BulkCopyTimeout = 0

            foreach ($column in $columns) {
                [void]$bulkCopy.ColumnMappings.Add($column, $column)
            }

            $bulkCopy.WriteToServer($data)
            $bulkCopy.Dispose()
            $bulkCopy = $null

            $command = $connection.CreateCommand()
            $command.Transaction = $transaction
            $command.CommandTimeout = 0
            $command.CommandText = "EXEC dbo.usp_ProcessIncomingActivationFile @SourceFile;"

            [void]$command.Parameters.Add(
                "@SourceFile",
                [System.Data.SqlDbType]::NVarChar,
                260
            )
            $command.Parameters["@SourceFile"].Value = $file.Name

            try {
                [void]$command.ExecuteNonQuery()
            }
            finally {
                $command.Dispose()
            }

            if ($DryRun) {
                $transaction.Rollback()
                $transaction = $null
                Write-Host "DRY RUN PASSED - database changes rolled back."
            }
            else {
                $transaction.Commit()
                $transaction = $null
                Write-Host "LOADED SUCCESSFULLY: $($file.Name)"
            }
        }
        catch {
            if ($null -ne $bulkCopy) {
                $bulkCopy.Dispose()
            }

            if ($null -ne $transaction) {
                try {
                    $transaction.Rollback()
                }
                catch {
                    # The stored procedure may already have rolled it back.
                }
            }

            Write-Error "File failed: $($file.Name). $($_.Exception.Message)"
            throw
        }
        finally {
            if ($null -ne $data) {
                $data.Dispose()
            }
        }
    }
}
finally {
    $connection.Close()
    $connection.Dispose()
}

Write-Host "`nETL scan finished."
