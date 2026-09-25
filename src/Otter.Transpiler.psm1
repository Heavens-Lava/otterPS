using module ..\Otter.Contract.psm1
using module .\Otter.Lexer.psm1
using module .\Otter.Parser.psm1
using module .\Otter.Compiler.JavaScript.psm1

# Otter.Transpiler.psm1
#
# Public orchestration layer for source-to-source compilation.
#
# This module deliberately owns NO JavaScript language semantics. The real
# AST -> JavaScript implementation remains in Otter.Compiler.JavaScript.psm1.
# Keeping this layer thin gives the CLI, Studio, documentation website/compiler
# service, and future tools one stable entry point without creating a second
# compiler implementation.
#
# Pipeline:
#   source -> lexer -> tokens -> parser -> ProgramNode -> JavaScript emitter
#
# Raw source transpilation does not resolve use module files because it has
# no source-file identity. File/project callers should resolve modules first
# through Otter.Module.psm1 and pass the resulting CombinedSource here.

function ConvertTo-OtterJavaScriptProgram {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ProgramNode]$Program,

        [ValidateRange(0, 64)]
        [int]$Indent = 0
    )

    $statements = @($Program.Statements)
    if ($statements.Count -eq 0) {
        return ''
    }

    $knownGlobals = (Get-OtterJsTopLevelGlobalNames -TopLevelStatements $statements).Names

    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($statement in $statements) {
        $generated = ConvertTo-OtterJsStatement -Stmt $statement -Indent $Indent -KnownGlobals $knownGlobals

        if ($null -ne $generated -and $generated -ne '') {
            $lines.Add([string]$generated)
        }
    }

    # Deterministic LF-separated compiler output. No trailing newline is added.
    return ($lines -join [char]10)
}

function ConvertTo-OtterJavaScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Source,

        [ValidateRange(0, 64)]
        [int]$Indent = 0
    )

    # Do not catch OtterError here. Lexer/parser diagnostics are part of the
    # language contract and should reach CLI/Studio/service callers unchanged.
    $tokens = ConvertTo-OtterTokens -Source $Source
    $program = ConvertTo-OtterAst -Tokens $tokens
    return ConvertTo-OtterJavaScriptProgram -Program $program -Indent $Indent
}

Export-ModuleMember -Function ConvertTo-OtterJavaScript, ConvertTo-OtterJavaScriptProgram
