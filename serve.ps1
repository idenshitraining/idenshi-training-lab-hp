# Static file server + Claude API proxy
# Set ANTHROPIC_API_KEY before starting:
#   $env:ANTHROPIC_API_KEY = "sk-ant-..."

$ANTHROPIC_API_KEY = $env:ANTHROPIC_API_KEY
if (-not $ANTHROPIC_API_KEY) {
    Write-Host '[WARNING] ANTHROPIC_API_KEY is not set. Chatbot will not work.' -ForegroundColor Yellow
}

# Load system prompt from external UTF-8 file (avoids Shift-JIS encoding issues in PS5.1)
$PROMPT_FILE = Join-Path $PSScriptRoot 'system_prompt.txt'
if (Test-Path $PROMPT_FILE) {
    $SYSTEM_PROMPT = [System.IO.File]::ReadAllText($PROMPT_FILE, [System.Text.Encoding]::UTF8)
} else {
    $SYSTEM_PROMPT = 'You are a helpful assistant for a personal gym. Answer in Japanese.'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://localhost:3001/')
$listener.Start()
Write-Host 'Server started at http://localhost:3001' -ForegroundColor Cyan

while ($listener.IsListening) {
    $context  = $listener.GetContext()
    $request  = $context.Request
    $response = $context.Response
    $localPath = $request.Url.LocalPath

    # CORS headers (for local development)
    $response.Headers.Add('Access-Control-Allow-Origin', '*')
    $response.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')

    # Preflight
    if ($request.HttpMethod -eq 'OPTIONS') {
        $response.StatusCode = 204
        $response.OutputStream.Close()
        continue
    }

    # ===== Claude API proxy =====
    if ($localPath -eq '/api/chat' -and $request.HttpMethod -eq 'POST') {
        try {
            # Read request body
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $data = $body | ConvertFrom-Json

            # Build message history (keep last 20 messages = 10 turns)
            $messages = @()
            if ($data.history) {
                $trimmed = $data.history | Select-Object -Last 20
                foreach ($h in $trimmed) {
                    $messages += @{ role = $h.role; content = $h.content }
                }
            }
            $messages += @{ role = 'user'; content = $data.message }

            # Build Claude API payload
            $apiPayload = @{
                model      = 'claude-haiku-4-5'
                max_tokens = 512
                system     = $SYSTEM_PROMPT
                messages   = $messages
            } | ConvertTo-Json -Depth 10
            $apiBytes = [System.Text.Encoding]::UTF8.GetBytes($apiPayload)

            # Send to Claude API
            $webReq = [System.Net.WebRequest]::Create('https://api.anthropic.com/v1/messages')
            $webReq.Method = 'POST'
            $webReq.ContentType = 'application/json'
            $webReq.Headers.Add('x-api-key', $ANTHROPIC_API_KEY)
            $webReq.Headers.Add('anthropic-version', '2023-06-01')
            $webReq.ContentLength = $apiBytes.Length
            $reqStream = $webReq.GetRequestStream()
            $reqStream.Write($apiBytes, 0, $apiBytes.Length)
            $reqStream.Close()

            $webRes    = $webReq.GetResponse()
            $resReader = New-Object System.IO.StreamReader($webRes.GetResponseStream(), [System.Text.Encoding]::UTF8)
            $resBody   = $resReader.ReadToEnd()
            $resReader.Close()
            $webRes.Close()

            $parsed    = $resBody | ConvertFrom-Json
            $replyText = $parsed.content[0].text

            $shortQ = $data.message.Substring(0, [Math]::Min(40, $data.message.Length))
            Write-Host "[Chat] Q: $shortQ ..." -ForegroundColor Green

            $replyJson = @{ reply = $replyText } | ConvertTo-Json -Compress
            $outBytes  = [System.Text.Encoding]::UTF8.GetBytes($replyJson)
            $response.ContentType = 'application/json; charset=utf-8'
            $response.ContentLength64 = $outBytes.Length
            $response.OutputStream.Write($outBytes, 0, $outBytes.Length)

        } catch {
            Write-Host "[Chat Error] $_" -ForegroundColor Red
            $fallback = 'An error occurred. Please contact us via phone or the inquiry form.'
            $errJson  = @{ reply = $fallback } | ConvertTo-Json -Compress
            $outBytes = [System.Text.Encoding]::UTF8.GetBytes($errJson)
            $response.StatusCode = 500
            $response.ContentType = 'application/json; charset=utf-8'
            $response.ContentLength64 = $outBytes.Length
            $response.OutputStream.Write($outBytes, 0, $outBytes.Length)
        }
        $response.OutputStream.Close()
        continue
    }

    # ===== Static file server =====
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
