# シンプルな静的ファイルサーバー
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://localhost:3000/')
$listener.Start()
Write-Host 'Server started at http://localhost:3000'
while ($listener.IsListening) {
    $context  = $listener.GetContext()
    $request  = $context.Request
    $response = $context.Response
    $localPath = $request.Url.LocalPath
    if ($localPath -eq '/') { $localPath = '/gym.html' }
    $filePath = 'C:\Users\Owner' + $localPath.Replace('/', '\')
    if (Test-Path $filePath -PathType Leaf) {
        $bytes = [System.IO.File]::ReadAllBytes($filePath)
        $ext   = [System.IO.Path]::GetExtension($filePath).ToLower()
        $response.ContentType = switch ($ext) {
            '.html' { 'text/html; charset=utf-8' }
            '.css'  { 'text/css' }
            '.js'   { 'application/javascript' }
            '.jpg'  { 'image/jpeg' }
            '.jpeg' { 'image/jpeg' }
            '.png'  { 'image/png' }
            '.webp' { 'image/webp' }
            default { 'application/octet-stream' }
        }
        $response.ContentLength64 = $bytes.Length
        $response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        $response.StatusCode = 404
    }
    $response.OutputStream.Close()
}
