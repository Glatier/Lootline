param([string]$Root = (Split-Path -Parent $PSScriptRoot), [int]$Port = $(if ($env:PORT) { [int]$env:PORT } else { 8765 }))
# Minimal read-only static file server for local Lua testing (GET only, localhost only).
# Open http://localhost:8765/tests/harness.html?test=smoke.lua (or anim.lua, options.lua).
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving $Root on http://localhost:$Port/"
$rootFull = [IO.Path]::GetFullPath($Root)
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $res = $ctx.Response
    try {
        $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart('/'))
        if ($rel -eq '') { $rel = 'index.html' }
        $path = [IO.Path]::GetFullPath((Join-Path $rootFull $rel))
        if ($ctx.Request.HttpMethod -ne 'GET' -or -not $path.StartsWith($rootFull) -or -not (Test-Path $path -PathType Leaf)) {
            $res.StatusCode = 404
            $bytes = [Text.Encoding]::UTF8.GetBytes("not found")
        } else {
            $bytes = [IO.File]::ReadAllBytes($path)
            $res.ContentType = if ($path -like '*.html') { 'text/html; charset=utf-8' } else { 'text/plain; charset=utf-8' }
        }
        $res.Headers.Add('Cache-Control', 'no-store')
        $res.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch {
        $res.StatusCode = 500
    } finally {
        $res.Close()
    }
}
