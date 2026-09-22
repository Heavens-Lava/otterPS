using module ..\Otter.Contract.psm1
using module .\Otter.Runtime.psm1

# Otter.Database.psm1
#
# D97: Database Provider Architecture & SQLite Reference Provider.
#
# Follows the Otter provider architecture:
#   - Otter language semantics remain constant across all database engines.
#   - Database providers implement the translation to host engines.
#   - Zero engine-specific branching in parser or interpreter.
#
# Reference Provider: SQLite using Windows built-in winsqlite3.dll.
# Zero external packages, zero NuGet dependencies, zero downloads.

class OtterDatabaseCapabilities {
    [bool]$SupportsTransactions = $true
    [bool]$SupportsLastInsertedId = $true
    [bool]$SupportsPreparedStatements = $false
    [bool]$SupportsSchemaIntrospection = $false
}

class OtterDatabaseConnection {
    [string]$ProviderName
    [string]$ConnectionString
    [object]$NativeHandle
    [bool]$IsOpen
    [object]$ActiveTransaction

    OtterDatabaseConnection([string]$providerName, [string]$connectionString, [object]$nativeHandle) {
        $this.ProviderName = $providerName
        $this.ConnectionString = $connectionString
        $this.NativeHandle = $nativeHandle
        $this.IsOpen = $true
        $this.ActiveTransaction = $null
    }

    [string] GetMaskedConnectionString() {
        if ([string]::IsNullOrEmpty($this.ConnectionString)) { return '' }
        return ($this.ConnectionString -replace '(?i)(password|pwd|secret)\s*=\s*[^;]+', '$1=****')
    }
}

class OtterDatabaseTransaction {
    [OtterDatabaseConnection]$Connection
    [bool]$IsActive
    [int]$Line

    OtterDatabaseTransaction([OtterDatabaseConnection]$connection, [int]$line) {
        $this.Connection = $connection
        $this.IsActive = $true
        $this.Line = $line
    }
}

class OtterDatabaseProvider {
    [string]$Name

    OtterDatabaseProvider([string]$name) {
        $this.Name = $name
    }

    [OtterDatabaseCapabilities] GetCapabilities() {
        return [OtterDatabaseCapabilities]::new()
    }

    [OtterDatabaseConnection] OpenConnection([hashtable]$config, [int]$line) {
        throw "OpenConnection not implemented in provider $($this.Name)"
    }

    [void] CloseConnection([OtterDatabaseConnection]$connection, [int]$line) {
        throw "CloseConnection not implemented in provider $($this.Name)"
    }

    [System.Collections.Generic.List[object]] ExecuteQuery([object]$connectionOrTx, [string]$sql, [hashtable]$parameters, [int]$line) {
        throw "ExecuteQuery not implemented in provider $($this.Name)"
    }

    [OtterObject] ExecuteCommand([object]$connectionOrTx, [string]$sql, [hashtable]$parameters, [int]$line) {
        throw "ExecuteCommand not implemented in provider $($this.Name)"
    }

    [OtterDatabaseTransaction] BeginTransaction([OtterDatabaseConnection]$connection, [int]$line) {
        throw "BeginTransaction not implemented in provider $($this.Name)"
    }

    [void] CommitTransaction([OtterDatabaseTransaction]$transaction, [int]$line) {
        throw "CommitTransaction not implemented in provider $($this.Name)"
    }

    [void] RollbackTransaction([OtterDatabaseTransaction]$transaction, [int]$line) {
        throw "RollbackTransaction not implemented in provider $($this.Name)"
    }

    [System.Collections.Generic.List[object]] GetTables([OtterDatabaseConnection]$connection, [int]$line) {
        throw "GetTables not implemented in provider $($this.Name)"
    }

    [System.Collections.Generic.List[object]] GetColumns([OtterDatabaseConnection]$connection, [object]$tableOrName, [int]$line) {
        throw "GetColumns not implemented in provider $($this.Name)"
    }
}

class OtterSqliteProvider : OtterDatabaseProvider {
    OtterSqliteProvider() : base('sqlite') {}

    [OtterDatabaseCapabilities] GetCapabilities() {
        $c = [OtterDatabaseCapabilities]::new()
        $c.SupportsTransactions = $true
        $c.SupportsLastInsertedId = $true
        $c.SupportsPreparedStatements = $true
        $c.SupportsSchemaIntrospection = $true
        return $c
    }

    [OtterDatabaseConnection] OpenConnection([hashtable]$config, [int]$line) {
        return (Open-OtterSqliteConnection -Config $config -Line $line)
    }

    [void] CloseConnection([OtterDatabaseConnection]$connection, [int]$line) {
        Close-OtterSqliteConnection -Connection $connection -Line $line
    }

    [System.Collections.Generic.List[object]] ExecuteQuery([object]$connectionOrTx, [string]$sql, [hashtable]$parameters, [int]$line) {
        return (Invoke-OtterSqliteQuery -ConnectionOrTx $connectionOrTx -Sql $sql -Parameters $parameters -Line $line)
    }

    [OtterObject] ExecuteCommand([object]$connectionOrTx, [string]$sql, [hashtable]$parameters, [int]$line) {
        return (Invoke-OtterSqliteCommand -ConnectionOrTx $connectionOrTx -Sql $sql -Parameters $parameters -Line $line)
    }

    [OtterDatabaseTransaction] BeginTransaction([OtterDatabaseConnection]$connection, [int]$line) {
        return (Start-OtterSqliteTransaction -Connection $connection -Line $line)
    }

    [void] CommitTransaction([OtterDatabaseTransaction]$transaction, [int]$line) {
        Complete-OtterSqliteTransaction -Transaction $transaction -Line $line
    }

    [void] RollbackTransaction([OtterDatabaseTransaction]$transaction, [int]$line) {
        Undo-OtterSqliteTransaction -Transaction $transaction -Line $line
    }

    [System.Collections.Generic.List[object]] GetTables([OtterDatabaseConnection]$connection, [int]$line) {
        return (Get-OtterSqliteTables -Connection $connection -Line $line)
    }

    [System.Collections.Generic.List[object]] GetColumns([OtterDatabaseConnection]$connection, [object]$tableOrName, [int]$line) {
        return (Get-OtterSqliteColumns -Connection $connection -TableOrName $tableOrName -Line $line)
    }
}

# Provider Registry
$script:DatabaseProviders = @{}

function Register-OtterDatabaseProvider {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][OtterDatabaseProvider]$Provider
    )
    $script:DatabaseProviders[$Name.ToLowerInvariant()] = $Provider
}

function Get-OtterDatabaseProvider {
    param(
        [Parameter(Mandatory)][string]$Name,
        [int]$Line = 0
    )
    $key = $Name.ToLowerInvariant()
    if ($script:DatabaseProviders.ContainsKey($key)) {
        return $script:DatabaseProviders[$key]
    }
    throw [OtterError]::new(
        "I do not know a database provider called `"$Name`". Available providers are: $(($script:DatabaseProviders.Keys | Sort-Object) -join ', ').",
        $Line, 'runtime'
    )
}


# ===============================================================
# SQLITE REFERENCE PROVIDER (winsqlite3.dll)
# ===============================================================

$script:WinSqliteInitialized = $false

function Initialize-OtterWinSqliteNative {
    if ($script:WinSqliteInitialized) { return }
    if ('OtterWinSqliteNative' -as [type]) {
        $script:WinSqliteInitialized = $true
        return
    }

    $nativeCode = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public class OtterWinSqliteNative {
    public const int SQLITE_OK = 0;
    public const int SQLITE_ERROR = 1;
    public const int SQLITE_ROW = 100;
    public const int SQLITE_DONE = 101;

    public const int SQLITE_INTEGER = 1;
    public const int SQLITE_FLOAT = 2;
    public const int SQLITE_TEXT = 3;
    public const int SQLITE_BLOB = 4;
    public const int SQLITE_NULL = 5;

    public const int SQLITE_OPEN_READWRITE = 0x00000002;
    public const int SQLITE_OPEN_CREATE = 0x00000004;
    public const int SQLITE_OPEN_READONLY = 0x00000001;

    public static readonly IntPtr SQLITE_TRANSIENT = new IntPtr(-1);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_open_v2", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_open_v2(byte[] filename, out IntPtr ppDb, int flags, byte[] zVfs);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_close_v2", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_close_v2(IntPtr db);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_prepare_v2", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_prepare_v2(IntPtr db, byte[] zSql, int nByte, out IntPtr ppStmt, IntPtr pzTail);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_step", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_step(IntPtr stmt);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_column_count", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_column_count(IntPtr stmt);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_column_name", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr sqlite3_column_name(IntPtr stmt, int N);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_column_type", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_column_type(IntPtr stmt, int iCol);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_column_int64", CallingConvention = CallingConvention.Cdecl)]
    public static extern long sqlite3_column_int64(IntPtr stmt, int iCol);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_column_double", CallingConvention = CallingConvention.Cdecl)]
    public static extern double sqlite3_column_double(IntPtr stmt, int iCol);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_column_text", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr sqlite3_column_text(IntPtr stmt, int iCol);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_column_bytes", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_column_bytes(IntPtr stmt, int iCol);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_bind_parameter_count", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_bind_parameter_count(IntPtr stmt);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_bind_parameter_index", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_bind_parameter_index(IntPtr stmt, byte[] zName);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_bind_null", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_bind_null(IntPtr stmt, int index);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_bind_int64", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_bind_int64(IntPtr stmt, int index, long value);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_bind_double", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_bind_double(IntPtr stmt, int index, double value);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_bind_text", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_bind_text(IntPtr stmt, int index, byte[] value, int length, IntPtr destructor);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_changes", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_changes(IntPtr db);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_last_insert_rowid", CallingConvention = CallingConvention.Cdecl)]
    public static extern long sqlite3_last_insert_rowid(IntPtr db);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_finalize", CallingConvention = CallingConvention.Cdecl)]
    public static extern int sqlite3_finalize(IntPtr stmt);

    [DllImport("winsqlite3.dll", EntryPoint = "sqlite3_errmsg", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr sqlite3_errmsg(IntPtr db);

    public static string Utf8PtrToString(IntPtr ptr) {
        if (ptr == IntPtr.Zero) return null;
        int len = 0;
        while (Marshal.ReadByte(ptr, len) != 0) len++;
        byte[] bytes = new byte[len];
        Marshal.Copy(ptr, bytes, 0, len);
        return Encoding.UTF8.GetString(bytes);
    }

    public static byte[] StringToUtf8Bytes(string str) {
        if (str == null) return null;
        byte[] bytes = Encoding.UTF8.GetBytes(str);
        byte[] nullTerminated = new byte[bytes.Length + 1];
        Array.Copy(bytes, nullTerminated, bytes.Length);
        nullTerminated[bytes.Length] = 0;
        return nullTerminated;
    }

    public static string GetErrorMessage(IntPtr db) {
        IntPtr ptr = sqlite3_errmsg(db);
        return Utf8PtrToString(ptr);
    }
}
'@

    Add-Type -TypeDefinition $nativeCode
    $script:WinSqliteInitialized = $true
}

function Open-OtterSqliteConnection {
    param(
        [hashtable]$Config,
        [int]$Line
    )
    Initialize-OtterWinSqliteNative

    if (-not $Config.ContainsKey('connection')) {
        throw [OtterError]::new(
            "SQLite database configuration is missing a `"connection`" property specifying the database path or `":memory:`".",
            $Line, 'runtime'
        )
    }

    $connStr = [string]$Config['connection']
    if ([string]::IsNullOrWhiteSpace($connStr)) {
        throw [OtterError]::new(
            "The database connection path cannot be empty.",
            $Line, 'runtime'
        )
    }

    $resolvedPath = $connStr
    $isMemory = $connStr -eq ':memory:' -or $connStr.StartsWith(':memory:')
    if (-not $isMemory) {
        if (-not [System.IO.Path]::IsPathRooted($connStr)) {
            $resolvedPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).Path, $connStr))
        }
        $dir = [System.IO.Path]::GetDirectoryName($resolvedPath)
        if (-not [string]::IsNullOrEmpty($dir) -and -not [System.IO.Directory]::Exists($dir)) {
            throw [OtterError]::new(
                "The folder `"$dir`" for the SQLite database does not exist.",
                $Line, 'runtime'
            )
        }
    }

    $flags = [OtterWinSqliteNative]::SQLITE_OPEN_READWRITE -bor [OtterWinSqliteNative]::SQLITE_OPEN_CREATE
    if ($Config.ContainsKey('readonly') -and $Config['readonly'] -eq $true) {
        $flags = [OtterWinSqliteNative]::SQLITE_OPEN_READONLY
    }

    $cleanPath = ($resolvedPath -split ';')[0]
    $dbPtr = [IntPtr]::Zero
    $pathBytes = [OtterWinSqliteNative]::StringToUtf8Bytes($cleanPath)
    $rc = [OtterWinSqliteNative]::sqlite3_open_v2($pathBytes, [ref]$dbPtr, $flags, $null)

    if ($rc -ne [OtterWinSqliteNative]::SQLITE_OK) {
        $err = if ($dbPtr -ne [IntPtr]::Zero) { [OtterWinSqliteNative]::GetErrorMessage($dbPtr) } else { "Error code $rc" }
        if ($dbPtr -ne [IntPtr]::Zero) { [OtterWinSqliteNative]::sqlite3_close_v2($dbPtr) | Out-Null }
        $masked = ($connStr -replace '(?i)(password|pwd|secret)\s*=\s*[^;]+', '$1=****')
        throw [OtterError]::new(
            "Could not open SQLite database `"$masked`": $err",
            $Line, 'runtime'
        )
    }

    return [OtterDatabaseConnection]::new('sqlite', $connStr, $dbPtr)
}

function Close-OtterSqliteConnection {
    param(
        [OtterDatabaseConnection]$Connection,
        [int]$Line
    )
    if ($null -eq $Connection -or -not $Connection.IsOpen) {
        throw [OtterError]::new("This database connection is already closed.", $Line, 'runtime')
    }

    $dbPtr = [IntPtr]$Connection.NativeHandle
    if ($null -ne $Connection.ActiveTransaction -and $Connection.ActiveTransaction.IsActive) {
        Undo-OtterSqliteTransaction -Transaction $Connection.ActiveTransaction -Line $Line
    }

    [OtterWinSqliteNative]::sqlite3_close_v2($dbPtr) | Out-Null
    $Connection.IsOpen = $false
    $Connection.NativeHandle = [IntPtr]::Zero
}

function Get-OtterSqliteConnectionHandle {
    param(
        [object]$ConnectionOrTx,
        [int]$Line
    )
    if ($ConnectionOrTx -is [OtterDatabaseTransaction]) {
        if (-not $ConnectionOrTx.IsActive) {
            throw [OtterError]::new("This transaction has already been completed.", $Line, 'runtime')
        }
        return (Get-OtterSqliteConnectionHandle -ConnectionOrTx $ConnectionOrTx.Connection -Line $Line)
    }

    if ($ConnectionOrTx -is [OtterDatabaseConnection]) {
        if (-not $ConnectionOrTx.IsOpen) {
            throw [OtterError]::new("This database connection is closed.", $Line, 'runtime')
        }
        return [IntPtr]$ConnectionOrTx.NativeHandle
    }

    if ($ConnectionOrTx -is [OtterObject]) {
        if ($ConnectionOrTx.TypeName -eq 'database transaction') {
            $tx = $ConnectionOrTx.ReadProperty('__transaction')
            if ($null -eq $tx -or -not $tx.IsActive) {
                throw [OtterError]::new("This transaction has already been completed.", $Line, 'runtime')
            }
            return (Get-OtterSqliteConnectionHandle -ConnectionOrTx $tx.Connection -Line $Line)
        }
        if ($ConnectionOrTx.TypeName -eq 'database connection') {
            $conn = $ConnectionOrTx.ReadProperty('__connection')
            if ($null -eq $conn -or -not $conn.IsOpen) {
                throw [OtterError]::new("This database connection is closed.", $Line, 'runtime')
            }
            return [IntPtr]$conn.NativeHandle
        }
    }

    throw [OtterError]::new("Expected an open database connection or active transaction.", $Line, 'runtime')
}

function Bind-OtterSqliteParameters {
    param(
        [IntPtr]$DbPtr,
        [IntPtr]$StmtPtr,
        [hashtable]$Parameters,
        [int]$Line
    )
    if ($null -eq $Parameters -or $Parameters.Count -eq 0) { return }

    foreach ($pName in $Parameters.Keys) {
        $val = $Parameters[$pName]
        $idx = 0
        $prefixes = @('', '@', ':', '$')
        foreach ($prefix in $prefixes) {
            $candidate = if ($pName.StartsWith('@') -or $pName.StartsWith(':') -or $pName.StartsWith('$')) { $pName } else { "$prefix$pName" }
            $bytes = [OtterWinSqliteNative]::StringToUtf8Bytes($candidate)
            $idx = [OtterWinSqliteNative]::sqlite3_bind_parameter_index($StmtPtr, $bytes)
            if ($idx -gt 0) { break }
        }

        if ($idx -le 0) { continue }

        if ($null -eq $val -or $val -is [System.DBNull]) {
            [OtterWinSqliteNative]::sqlite3_bind_null($StmtPtr, $idx) | Out-Null
        } elseif ($val -is [bool]) {
            $intVal = if ($val) { 1L } else { 0L }
            [OtterWinSqliteNative]::sqlite3_bind_int64($StmtPtr, $idx, $intVal) | Out-Null
        } elseif ($val -is [int] -or $val -is [long] -or $val -is [int64]) {
            [OtterWinSqliteNative]::sqlite3_bind_int64($StmtPtr, $idx, [long]$val) | Out-Null
        } elseif ($val -is [double] -or $val -is [float] -or $val -is [decimal]) {
            if ($val -is [double] -and $val -eq [Math]::Floor($val) -and $val -ge [long]::MinValue -and $val -le [long]::MaxValue) {
                [OtterWinSqliteNative]::sqlite3_bind_int64($StmtPtr, $idx, [long]$val) | Out-Null
            } else {
                [OtterWinSqliteNative]::sqlite3_bind_double($StmtPtr, $idx, [double]$val) | Out-Null
            }
        } else {
            $textVal = [string]$val
            $textBytes = [OtterWinSqliteNative]::StringToUtf8Bytes($textVal)
            [OtterWinSqliteNative]::sqlite3_bind_text($StmtPtr, $idx, $textBytes, -1, [OtterWinSqliteNative]::SQLITE_TRANSIENT) | Out-Null
        }
    }
}

function Invoke-OtterSqliteQuery {
    param(
        [object]$ConnectionOrTx,
        [string]$Sql,
        [hashtable]$Parameters,
        [int]$Line
    )
    Initialize-OtterWinSqliteNative
    $dbPtr = Get-OtterSqliteConnectionHandle -ConnectionOrTx $ConnectionOrTx -Line $Line

    $stmtPtr = [IntPtr]::Zero
    $sqlBytes = [OtterWinSqliteNative]::StringToUtf8Bytes($Sql)
    $rc = [OtterWinSqliteNative]::sqlite3_prepare_v2($dbPtr, $sqlBytes, -1, [ref]$stmtPtr, [IntPtr]::Zero)

    if ($rc -ne [OtterWinSqliteNative]::SQLITE_OK) {
        $err = [OtterWinSqliteNative]::GetErrorMessage($dbPtr)
        throw [OtterError]::new("Database query error: $err", $Line, 'runtime')
    }

    try {
        Bind-OtterSqliteParameters -DbPtr $dbPtr -StmtPtr $stmtPtr -Parameters $Parameters -Line $Line

        $results = [System.Collections.Generic.List[object]]::new()
        while (($rc = [OtterWinSqliteNative]::sqlite3_step($stmtPtr)) -eq [OtterWinSqliteNative]::SQLITE_ROW) {
            $row = [OtterObject]::new('database row')
            $colCount = [OtterWinSqliteNative]::sqlite3_column_count($stmtPtr)

            for ($i = 0; $i -lt $colCount; $i++) {
                $namePtr = [OtterWinSqliteNative]::sqlite3_column_name($stmtPtr, $i)
                $colName = [OtterWinSqliteNative]::Utf8PtrToString($namePtr)
                $colType = [OtterWinSqliteNative]::sqlite3_column_type($stmtPtr, $i)

                $colVal = switch ($colType) {
                    ([OtterWinSqliteNative]::SQLITE_INTEGER) {
                        [double]([OtterWinSqliteNative]::sqlite3_column_int64($stmtPtr, $i))
                    }
                    ([OtterWinSqliteNative]::SQLITE_FLOAT) {
                        [OtterWinSqliteNative]::sqlite3_column_double($stmtPtr, $i)
                    }
                    ([OtterWinSqliteNative]::SQLITE_TEXT) {
                        $txtPtr = [OtterWinSqliteNative]::sqlite3_column_text($stmtPtr, $i)
                        [OtterWinSqliteNative]::Utf8PtrToString($txtPtr)
                    }
                    ([OtterWinSqliteNative]::SQLITE_NULL) {
                        $null  # Otter "gone"
                    }
                    default {
                        $txtPtr = [OtterWinSqliteNative]::sqlite3_column_text($stmtPtr, $i)
                        [OtterWinSqliteNative]::Utf8PtrToString($txtPtr)
                    }
                }

                $row.WriteProperty($colName, $colVal)
            }
            $results.Add($row)
        }

        if ($rc -ne [OtterWinSqliteNative]::SQLITE_DONE -and $rc -ne [OtterWinSqliteNative]::SQLITE_ROW) {
            $err = [OtterWinSqliteNative]::GetErrorMessage($dbPtr)
            throw [OtterError]::new("Database query execution error: $err", $Line, 'runtime')
        }

        return $results
    }
    finally {
        if ($stmtPtr -ne [IntPtr]::Zero) {
            [OtterWinSqliteNative]::sqlite3_finalize($stmtPtr) | Out-Null
        }
    }
}

function Invoke-OtterSqliteCommand {
    param(
        [object]$ConnectionOrTx,
        [string]$Sql,
        [hashtable]$Parameters,
        [int]$Line
    )
    Initialize-OtterWinSqliteNative
    $dbPtr = Get-OtterSqliteConnectionHandle -ConnectionOrTx $ConnectionOrTx -Line $Line

    $stmtPtr = [IntPtr]::Zero
    $sqlBytes = [OtterWinSqliteNative]::StringToUtf8Bytes($Sql)
    $rc = [OtterWinSqliteNative]::sqlite3_prepare_v2($dbPtr, $sqlBytes, -1, [ref]$stmtPtr, [IntPtr]::Zero)

    if ($rc -ne [OtterWinSqliteNative]::SQLITE_OK) {
        $err = [OtterWinSqliteNative]::GetErrorMessage($dbPtr)
        throw [OtterError]::new("Database command error: $err", $Line, 'runtime')
    }

    try {
        Bind-OtterSqliteParameters -DbPtr $dbPtr -StmtPtr $stmtPtr -Parameters $Parameters -Line $Line

        $rc = [OtterWinSqliteNative]::sqlite3_step($stmtPtr)
        if ($rc -ne [OtterWinSqliteNative]::SQLITE_DONE -and $rc -ne [OtterWinSqliteNative]::SQLITE_ROW) {
            $err = [OtterWinSqliteNative]::GetErrorMessage($dbPtr)
            throw [OtterError]::new("Database command execution error: $err", $Line, 'runtime')
        }

        $changes = [OtterWinSqliteNative]::sqlite3_changes($dbPtr)
        $lastRowId = [OtterWinSqliteNative]::sqlite3_last_insert_rowid($dbPtr)

        $result = [OtterObject]::new('database result')
        $result.WriteProperty('rows affected', [double]$changes)
        if ($lastRowId -gt 0) {
            $result.WriteProperty('last inserted id', [double]$lastRowId)
        } else {
            $result.WriteProperty('last inserted id', $null) # gone
        }
        return $result
    }
    finally {
        if ($stmtPtr -ne [IntPtr]::Zero) {
            [OtterWinSqliteNative]::sqlite3_finalize($stmtPtr) | Out-Null
        }
    }
}

function Start-OtterSqliteTransaction {
    param(
        [OtterDatabaseConnection]$Connection,
        [int]$Line
    )
    Initialize-OtterWinSqliteNative
    if (-not $Connection.IsOpen) {
        throw [OtterError]::new("Cannot begin a transaction on a closed database connection.", $Line, 'runtime')
    }
    if ($null -ne $Connection.ActiveTransaction -and $Connection.ActiveTransaction.IsActive) {
        throw [OtterError]::new("A transaction is already active on this database connection.", $Line, 'runtime')
    }

    Invoke-OtterSqliteCommand -ConnectionOrTx $Connection -Sql "BEGIN IMMEDIATE TRANSACTION" -Parameters @{} -Line $Line | Out-Null
    $tx = [OtterDatabaseTransaction]::new($Connection, $Line)
    $Connection.ActiveTransaction = $tx
    return $tx
}

function Complete-OtterSqliteTransaction {
    param(
        [OtterDatabaseTransaction]$Transaction,
        [int]$Line
    )
    Initialize-OtterWinSqliteNative
    if ($null -eq $Transaction -or -not $Transaction.IsActive) {
        throw [OtterError]::new("This transaction has already been completed.", $Line, 'runtime')
    }
    $conn = $Transaction.Connection
    if (-not $conn.IsOpen) {
        throw [OtterError]::new("Cannot commit transaction because the database connection is closed.", $Line, 'runtime')
    }

    Invoke-OtterSqliteCommand -ConnectionOrTx $conn -Sql "COMMIT TRANSACTION" -Parameters @{} -Line $Line | Out-Null
    $Transaction.IsActive = $false
    $conn.ActiveTransaction = $null
}

function Undo-OtterSqliteTransaction {
    param(
        [OtterDatabaseTransaction]$Transaction,
        [int]$Line
    )
    Initialize-OtterWinSqliteNative
    if ($null -eq $Transaction -or -not $Transaction.IsActive) {
        throw [OtterError]::new("This transaction has already been completed.", $Line, 'runtime')
    }
    $conn = $Transaction.Connection
    if (-not $conn.IsOpen) {
        throw [OtterError]::new("Cannot roll back transaction because the database connection is closed.", $Line, 'runtime')
    }

    Invoke-OtterSqliteCommand -ConnectionOrTx $conn -Sql "ROLLBACK TRANSACTION" -Parameters @{} -Line $Line | Out-Null
    $Transaction.IsActive = $false
    $conn.ActiveTransaction = $null
}

function Get-OtterSqliteTables {
    param(
        [OtterDatabaseConnection]$Connection,
        [int]$Line
    )
    if (-not $Connection.IsOpen) {
        throw [OtterError]::new("This database connection is closed.", $Line, 'runtime')
    }

    $sql = "SELECT name, type FROM sqlite_master WHERE type IN ('table', 'view') AND name NOT LIKE 'sqlite_%' ORDER BY name"
    $rows = Invoke-OtterSqliteQuery -ConnectionOrTx $Connection -Sql $sql -Parameters @{} -Line $Line

    $tables = [System.Collections.Generic.List[object]]::new()
    foreach ($row in $rows) {
        $tblObj = [OtterObject]::new('database table')
        $tblObj.WriteProperty('name', [string]($row.ReadProperty('name')))
        $tblObj.WriteProperty('schema', 'main')
        $rawType = [string]($row.ReadProperty('type'))
        $kind = if ($rawType.ToLowerInvariant() -eq 'view') { 'view' } else { 'table' }
        $tblObj.WriteProperty('kind', $kind)
        $tables.Add($tblObj)
    }
    return $tables
}

function Get-OtterPortableColumnType([string]$declaredType) {
    if ([string]::IsNullOrWhiteSpace($declaredType)) { return 'any' }
    $t = $declaredType.Trim().ToUpperInvariant()

    if ($t -match '\b(INT|INTEGER|TINYINT|SMALLINT|MEDIUMINT|BIGINT|INT2|INT8|NUMERIC|DECIMAL|REAL|DOUBLE|FLOAT)\b') {
        return 'number'
    }
    if ($t -match '\b(CHAR|CHARACTER|VARCHAR|VARYING CHARACTER|NCHAR|NATIVE CHARACTER|NVARCHAR|TEXT|CLOB|STRING)\b') {
        return 'text'
    }
    if ($t -match '\b(BOOL|BOOLEAN)\b') {
        return 'boolean'
    }
    if ($t -match '\b(BLOB|BINARY|VARBINARY)\b') {
        return 'bytes'
    }
    if ($t -match '\b(DATE|DATETIME|TIME|TIMESTAMP)\b') {
        return 'time'
    }
    return 'any'
}

function Get-OtterSqliteColumns {
    param(
        [OtterDatabaseConnection]$Connection,
        [object]$TableOrName,
        [int]$Line
    )
    if (-not $Connection.IsOpen) {
        throw [OtterError]::new("This database connection is closed.", $Line, 'runtime')
    }

    $tableName = $null
    if ($TableOrName -is [OtterObject]) {
        if ($TableOrName.HasProperty('name')) {
            $tableName = [string]($TableOrName.ReadProperty('name'))
        } else {
            throw [OtterError]::new("I expected a database table object with a 'name' property, or a table name as text.", $Line, 'runtime')
        }
    } elseif ($TableOrName -is [string]) {
        $tableName = $TableOrName
    } else {
        throw [OtterError]::new("I expected a table name as text, or a database table object.", $Line, 'runtime')
    }

    if ([string]::IsNullOrWhiteSpace($tableName)) {
        throw [OtterError]::new("Table name cannot be empty.", $Line, 'runtime')
    }

    # Verify table or view exists in sqlite_master using parameterized query (100% injection-proof)
    $checkSql = "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') AND name = @tableName"
    $checkParams = @{ 'tableName' = $tableName }
    $existing = Invoke-OtterSqliteQuery -ConnectionOrTx $Connection -Sql $checkSql -Parameters $checkParams -Line $Line
    if ($existing.Count -eq 0) {
        throw [OtterError]::new("I could not find a table or view called `"$tableName`" in the database.", $Line, 'runtime')
    }

    # Execute safe PRAGMA table_info using doubled-quote escaping
    $escaped = $tableName -replace '"', '""'
    $pragmaSql = "PRAGMA table_info(`"$escaped`")"
    $rawColumns = Invoke-OtterSqliteQuery -ConnectionOrTx $Connection -Sql $pragmaSql -Parameters @{} -Line $Line

    $columns = [System.Collections.Generic.List[object]]::new()
    foreach ($col in $rawColumns) {
        $colObj = [OtterObject]::new('database column')
        $colName = [string]($col.ReadProperty('name'))
        $rawDeclaredType = if ($col.HasProperty('type') -and $null -ne $col.ReadProperty('type')) { [string]($col.ReadProperty('type')) } else { '' }
        $notNull = if ($col.HasProperty('notnull')) { [int]($col.ReadProperty('notnull')) } else { 0 }
        $dfltVal = if ($col.HasProperty('dflt_value')) { $col.ReadProperty('dflt_value') } else { $null }
        $pk = if ($col.HasProperty('pk')) { [int]($col.ReadProperty('pk')) } else { 0 }

        $colObj.WriteProperty('name', $colName)
        $colObj.WriteProperty('type', (Get-OtterPortableColumnType $rawDeclaredType))
        $colObj.WriteProperty('database type', $rawDeclaredType)
        $colObj.WriteProperty('nullable', ($notNull -eq 0))
        $colObj.WriteProperty('primary key', ($pk -gt 0))
        $colObj.WriteProperty('primary key position', $(if ($pk -gt 0) { $pk } else { $null }))
        $colObj.WriteProperty('default expression', $(if ($null -ne $dfltVal) { [string]$dfltVal } else { $null }))

        $columns.Add($colObj)
    }

    return $columns
}

# Register default SQLite provider
$script:SqliteProviderInstance = [OtterSqliteProvider]::new()
Register-OtterDatabaseProvider -Name 'sqlite' -Provider $script:SqliteProviderInstance

# High-level helper functions called by Interpreter
function Connect-OtterDatabase {
    param(
        [Parameter(Mandatory)][object]$ConfigValue,
        [int]$Line
    )

    $configHash = @{}
    if ($ConfigValue -is [OtterObject]) {
        foreach ($prop in $ConfigValue.PropertyNames()) {
            $configHash[$prop] = $ConfigValue.ReadProperty($prop)
        }
    } elseif ($ConfigValue -is [hashtable]) {
        $configHash = $ConfigValue
    } elseif ($ConfigValue -is [string]) {
        $configHash['provider'] = 'sqlite'
        $configHash['connection'] = $ConfigValue
    } else {
        throw [OtterError]::new("I expected a database configuration object created with 'has'.", $Line, 'runtime')
    }

    if (-not $configHash.ContainsKey('provider')) {
        throw [OtterError]::new("Database configuration must include a `"provider`" property (such as `"sqlite`").", $Line, 'runtime')
    }

    $providerName = [string]$configHash['provider']
    $provider = Get-OtterDatabaseProvider -Name $providerName -Line $Line
    $conn = $provider.OpenConnection($configHash, $Line)

    $connObj = [OtterObject]::new('database connection')
    $connObj.WriteProperty('provider', $providerName)
    $connObj.WriteProperty('connection', $conn.GetMaskedConnectionString())
    $connObj.WriteProperty('__connection', $conn)
    return $connObj
}

function Disconnect-OtterDatabase {
    param(
        [Parameter(Mandatory)][object]$ConnectionValue,
        [int]$Line
    )

    $conn = $null
    if ($ConnectionValue -is [OtterDatabaseConnection]) {
        $conn = $ConnectionValue
    } elseif ($ConnectionValue -is [OtterObject] -and $ConnectionValue.TypeName -eq 'database connection') {
        $conn = $ConnectionValue.ReadProperty('__connection')
    } else {
        throw [OtterError]::new("I can only disconnect a live database connection.", $Line, 'runtime')
    }

    if ($null -eq $conn -or -not $conn.IsOpen) {
        throw [OtterError]::new("This database connection is already closed.", $Line, 'runtime')
    }

    $provider = Get-OtterDatabaseProvider -Name $conn.ProviderName -Line $Line
    $provider.CloseConnection($conn, $Line)
}

function Invoke-OtterDatabaseQuery {
    param(
        [Parameter(Mandatory)][object]$TargetValue,
        [Parameter(Mandatory)][string]$Sql,
        [hashtable]$Parameters = @{},
        [int]$Line
    )

    $providerName = 'sqlite'
    if ($TargetValue -is [OtterDatabaseConnection]) {
        $providerName = $TargetValue.ProviderName
    } elseif ($TargetValue -is [OtterDatabaseTransaction]) {
        $providerName = $TargetValue.Connection.ProviderName
    } elseif ($TargetValue -is [OtterObject]) {
        if ($TargetValue.TypeName -eq 'database connection') {
            $conn = $TargetValue.ReadProperty('__connection')
            if ($null -ne $conn) { $providerName = $conn.ProviderName }
        } elseif ($TargetValue.TypeName -eq 'database transaction') {
            $tx = $TargetValue.ReadProperty('__transaction')
            if ($null -ne $tx) { $providerName = $tx.Connection.ProviderName }
        }
    }

    $provider = Get-OtterDatabaseProvider -Name $providerName -Line $Line
    return $provider.ExecuteQuery($TargetValue, $Sql, $Parameters, $Line)
}

function Invoke-OtterDatabaseCommand {
    param(
        [Parameter(Mandatory)][object]$TargetValue,
        [Parameter(Mandatory)][string]$Sql,
        [hashtable]$Parameters = @{},
        [int]$Line
    )

    $providerName = 'sqlite'
    if ($TargetValue -is [OtterDatabaseConnection]) {
        $providerName = $TargetValue.ProviderName
    } elseif ($TargetValue -is [OtterDatabaseTransaction]) {
        $providerName = $TargetValue.Connection.ProviderName
    } elseif ($TargetValue -is [OtterObject]) {
        if ($TargetValue.TypeName -eq 'database connection') {
            $conn = $TargetValue.ReadProperty('__connection')
            if ($null -ne $conn) { $providerName = $conn.ProviderName }
        } elseif ($TargetValue.TypeName -eq 'database transaction') {
            $tx = $TargetValue.ReadProperty('__transaction')
            if ($null -ne $tx) { $providerName = $tx.Connection.ProviderName }
        }
    }

    $provider = Get-OtterDatabaseProvider -Name $providerName -Line $Line
    return $provider.ExecuteCommand($TargetValue, $Sql, $Parameters, $Line)
}

function Start-OtterDatabaseTransaction {
    param(
        [Parameter(Mandatory)][object]$ConnectionValue,
        [int]$Line
    )

    $conn = $null
    if ($ConnectionValue -is [OtterDatabaseConnection]) {
        $conn = $ConnectionValue
    } elseif ($ConnectionValue -is [OtterObject] -and $ConnectionValue.TypeName -eq 'database connection') {
        $conn = $ConnectionValue.ReadProperty('__connection')
    } else {
        throw [OtterError]::new("I can only begin a transaction on a live database connection.", $Line, 'runtime')
    }

    if ($null -eq $conn -or -not $conn.IsOpen) {
        throw [OtterError]::new("Cannot begin a transaction on a closed database connection.", $Line, 'runtime')
    }

    $provider = Get-OtterDatabaseProvider -Name $conn.ProviderName -Line $Line
    $tx = $provider.BeginTransaction($conn, $Line)

    $txObj = [OtterObject]::new('database transaction')
    $txObj.WriteProperty('provider', $conn.ProviderName)
    $txObj.WriteProperty('__transaction', $tx)
    return $txObj
}

function Complete-OtterDatabaseTransaction {
    param(
        [Parameter(Mandatory)][object]$TransactionValue,
        [int]$Line
    )

    $tx = $null
    if ($TransactionValue -is [OtterDatabaseTransaction]) {
        $tx = $TransactionValue
    } elseif ($TransactionValue -is [OtterObject] -and $TransactionValue.TypeName -eq 'database transaction') {
        $tx = $TransactionValue.ReadProperty('__transaction')
    } else {
        throw [OtterError]::new("I can only commit a real database transaction.", $Line, 'runtime')
    }

    if ($null -eq $tx -or -not $tx.IsActive) {
        throw [OtterError]::new("This transaction has already been completed.", $Line, 'runtime')
    }

    $provider = Get-OtterDatabaseProvider -Name $tx.Connection.ProviderName -Line $Line
    $provider.CommitTransaction($tx, $Line)
}

function Undo-OtterDatabaseTransaction {
    param(
        [Parameter(Mandatory)][object]$TransactionValue,
        [int]$Line
    )

    $tx = $null
    if ($TransactionValue -is [OtterDatabaseTransaction]) {
        $tx = $TransactionValue
    } elseif ($TransactionValue -is [OtterObject] -and $TransactionValue.TypeName -eq 'database transaction') {
        $tx = $TransactionValue.ReadProperty('__transaction')
    } else {
        throw [OtterError]::new("I can only roll back a real database transaction.", $Line, 'runtime')
    }

    if ($null -eq $tx -or -not $tx.IsActive) {
        throw [OtterError]::new("This transaction has already been completed.", $Line, 'runtime')
    }

    $provider = Get-OtterDatabaseProvider -Name $tx.Connection.ProviderName -Line $Line
    $provider.RollbackTransaction($tx, $Line)
}

function Get-OtterDatabaseTables {
    param(
        [Parameter(Mandatory)][object]$TargetValue,
        [int]$Line
    )

    $conn = $null
    if ($TargetValue -is [OtterDatabaseConnection]) {
        $conn = $TargetValue
    } elseif ($TargetValue -is [OtterObject] -and $TargetValue.TypeName -eq 'database connection') {
        $conn = $TargetValue.ReadProperty('__connection')
    } else {
        throw [OtterError]::new("I expected a database connection after 'from'.", $Line, 'runtime')
    }

    if ($null -eq $conn -or -not $conn.IsOpen) {
        throw [OtterError]::new("This database connection is closed.", $Line, 'runtime')
    }

    $provider = Get-OtterDatabaseProvider -Name $conn.ProviderName -Line $Line
    $caps = $provider.GetCapabilities()
    if (-not $caps.SupportsSchemaIntrospection) {
        throw [OtterError]::new("The $($conn.ProviderName) provider does not support schema introspection.", $Line, 'runtime')
    }

    return $provider.GetTables($conn, $Line)
}

function Get-OtterDatabaseColumns {
    param(
        [Parameter(Mandatory)][object]$TargetValue,
        [Parameter(Mandatory)][object]$TableOrName,
        [int]$Line
    )

    $conn = $null
    if ($TargetValue -is [OtterDatabaseConnection]) {
        $conn = $TargetValue
    } elseif ($TargetValue -is [OtterObject] -and $TargetValue.TypeName -eq 'database connection') {
        $conn = $TargetValue.ReadProperty('__connection')
    } else {
        throw [OtterError]::new("I expected a database connection after 'in'.", $Line, 'runtime')
    }

    if ($null -eq $conn -or -not $conn.IsOpen) {
        throw [OtterError]::new("This database connection is closed.", $Line, 'runtime')
    }

    $provider = Get-OtterDatabaseProvider -Name $conn.ProviderName -Line $Line
    $caps = $provider.GetCapabilities()
    if (-not $caps.SupportsSchemaIntrospection) {
        throw [OtterError]::new("The $($conn.ProviderName) provider does not support schema introspection.", $Line, 'runtime')
    }

    return $provider.GetColumns($conn, $TableOrName, $Line)
}

Export-ModuleMember -Function `
    Register-OtterDatabaseProvider, `
    Get-OtterDatabaseProvider, `
    Connect-OtterDatabase, `
    Disconnect-OtterDatabase, `
    Invoke-OtterDatabaseQuery, `
    Invoke-OtterDatabaseCommand, `
    Start-OtterDatabaseTransaction, `
    Complete-OtterDatabaseTransaction, `
    Undo-OtterDatabaseTransaction, `
    Get-OtterDatabaseTables, `
    Get-OtterDatabaseColumns

