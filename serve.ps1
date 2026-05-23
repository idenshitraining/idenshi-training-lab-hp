# シンプルな静的ファイルサーバー + Claude API プロキシ
# 起動前に環境変数 ANTHROPIC_API_KEY をセットしてください:
#   $env:ANTHROPIC_API_KEY = "sk-ant-..."

$ANTHROPIC_API_KEY = $env:ANTHROPIC_API_KEY
if (-not $ANTHROPIC_API_KEY) {
    Write-Host '[警告] 環境変数 ANTHROPIC_API_KEY が設定されていません。チャットボットは動作しません。' -ForegroundColor Yellow
}

# ジムのシステムプロンプト
$SYSTEM_PROMPT = @"
あなたは「遺伝子トレーニング研究所」の親切なAIアシスタントです。
訪問者からの質問に丁寧かつ簡潔に日本語で答えてください。

【店舗情報】
- 店舗名：遺伝子トレーニング研究所
- 住所：神奈川県藤沢市獺郷
- 最寄り駅：寒川駅（徒歩約10分）
- 営業時間：10:00〜20:00
- お問い合わせ：公式LINEまたはページ下部フォーム

【サービス内容】
- 遺伝子検査（唾液採取、痛みなし・自宅可能）をベースにした完全個別プログラム
- 体質・代謝・筋肉タイプを遺伝子レベルで分析し、最適なトレーニング・食事プランを提供
- オンライン（Zoom）・対面どちらも対応可能
- 遺伝子情報は先天的なもので生涯変わらず、一度受ければ長期にわたって活用できる
- 検査キットのみの単体販売は行っていない（専門アドバイザーによる解説とセット）

【料金プラン】
- 体質分析サービス：¥58,500〜（遺伝子検査＋解説カウンセリング1回）
- 2ヶ月サポートプラン：¥220,000（週2回×8回＋栄養指導＋24時間LINE相談）
- 3ヶ月本格プラン：¥300,000（週2回×12回＋栄養指導＋24時間LINE相談）

【よくある質問】
Q: トレーナーを途中で変更できますか？
A: 可能です。体質情報はトレーナー間で共有されるためスムーズに引き継ぎされます。

Q: 遺伝子検査はどのように行いますか？
A: ご自宅で唾液を採取する方法です。採血は不要で痛みもありません。

Q: カウンセリングはオンラインですか？
A: 基本はZoomを使ったオンライン形式ですが、対面でも対応可能です。

Q: 申し込みはどうすればいいですか？
A: 公式LINEまたはページ下部のお問い合わせフォームからご連絡ください。

【回答のルール】
- 回答は2〜4文程度で簡潔にまとめること
- 案内できない内容は「お電話またはお問い合わせフォームよりご連絡ください」と伝える
- 競合他社への言及は避ける
- 常に親切で丁寧なトーンを保つ
"@

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://localhost:3000/')
$listener.Start()
Write-Host 'Server started at http://localhost:3000' -ForegroundColor Cyan

while ($listener.IsListening) {
    $context  = $listener.GetContext()
    $request  = $context.Request
    $response = $context.Response
    $localPath = $request.Url.LocalPath

    # CORS ヘッダー（開発環境用）
    $response.Headers.Add('Access-Control-Allow-Origin', '*')
    $response.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')

    # プリフライトリクエスト対応
    if ($request.HttpMethod -eq 'OPTIONS') {
        $response.StatusCode = 204
        $response.OutputStream.Close()
        continue
    }

    # ===== Claude API プロキシ =====
    if ($localPath -eq '/api/chat' -and $request.HttpMethod -eq 'POST') {
        try {
            # リクエストボディを読み込む
            $reader = New-Object System.IO.StreamReader($request.InputStream, [System.Text.Encoding]::UTF8)
            $body = $reader.ReadToEnd()
            $reader.Close()
            $data = $body | ConvertFrom-Json

            # メッセージ履歴を構築（最大10ターン保持）
            $messages = @()
            if ($data.history) {
                $trimmed = $data.history | Select-Object -Last 20
                foreach ($h in $trimmed) {
                    $messages += @{ role = $h.role; content = $h.content }
                }
            }
            $messages += @{ role = 'user'; content = $data.message }

            # Claude API リクエストボディ
            $apiPayload = @{
                model      = 'claude-haiku-4-5'
                max_tokens = 512
                system     = $SYSTEM_PROMPT
                messages   = $messages
            } | ConvertTo-Json -Depth 10
            $apiBytes = [System.Text.Encoding]::UTF8.GetBytes($apiPayload)

            # Claude API へ送信
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

            Write-Host "[Chat] Q: $($data.message.Substring(0, [Math]::Min(40,$data.message.Length)))..." -ForegroundColor Green

            $replyJson = @{ reply = $replyText } | ConvertTo-Json -Compress
            $outBytes  = [System.Text.Encoding]::UTF8.GetBytes($replyJson)
            $response.ContentType = 'application/json; charset=utf-8'
            $response.ContentLength64 = $outBytes.Length
            $response.OutputStream.Write($outBytes, 0, $outBytes.Length)

        } catch {
            Write-Host "[Chat Error] $_" -ForegroundColor Red
            $errJson  = @{ reply = '申し訳ありません。一時的にエラーが発生しました。お電話またはフォームよりお問い合わせください。' } | ConvertTo-Json -Compress
            $outBytes = [System.Text.Encoding]::UTF8.GetBytes($errJson)
            $response.StatusCode = 500
            $response.ContentType = 'application/json; charset=utf-8'
            $response.ContentLength64 = $outBytes.Length
            $response.OutputStream.Write($outBytes, 0, $outBytes.Length)
        }
        $response.OutputStream.Close()
        continue
    }

    # ===== 静的ファイル配信 =====
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
