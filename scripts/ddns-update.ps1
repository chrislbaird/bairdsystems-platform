# Keeps the bairdsystems.com A records that point at home following the home WAN IP.
# Only records still holding the previous home IP (ddns-ip.txt) are moved, so a record
# deliberately pointed somewhere else (an outside host) is never overwritten.
# Runs every 5 minutes as SYSTEM (scheduled task "Cloudflare DDNS"). Logs to ddns.log.
$ErrorActionPreference = 'Stop'
$root = 'C:\webgateway'
$log  = "$root\ddns.log"
$last = "$root\ddns-ip.txt"
function Log($m) { "$(Get-Date -Format s) $m" | Add-Content $log }

$s = @{}
Get-Content "$root\secrets.txt" | Where-Object { $_ -match '^\s*([A-Z_]+)\s*=\s*(.*)$' } | ForEach-Object { $s[$matches[1]] = $matches[2].Trim() }
$h = @{ Authorization = "Bearer $($s.CLOUDFLARE_API_TOKEN)" }
$api = 'https://api.cloudflare.com/client/v4'

try {
    $ip = (Invoke-RestMethod 'https://api.ipify.org' -TimeoutSec 15).Trim()
    if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw "bad IP '$ip'" }
    $prev = if (Test-Path $last) { (Get-Content $last -Raw).Trim() } else { $ip }
    if ($prev -eq $ip -and (Test-Path $last)) { return }        # nothing changed
    $zone = (Invoke-RestMethod "$api/zones?name=bairdsystems.com" -Headers $h).result[0].id
    $recs = @(); $page = 1
    do {
        $resp = Invoke-RestMethod "$api/zones/$zone/dns_records?type=A&per_page=100&page=$page" -Headers $h
        $recs += $resp.result; $page++
    } while ($page -le $resp.result_info.total_pages)
    foreach ($r in $recs | Where-Object { $_.content -eq $prev -and $_.content -ne $ip }) {
        $body = @{ content = $ip } | ConvertTo-Json
        Invoke-RestMethod "$api/zones/$zone/dns_records/$($r.id)" -Method Patch -Headers $h -Body $body -ContentType 'application/json' | Out-Null
        Log "updated $($r.name) $($r.content) -> $ip"
    }
    $others = @($recs | Where-Object { $_.content -ne $prev -and $_.content -ne $ip })
    if ($others) { Log "left alone (not the home IP): $(($others | ForEach-Object { "$($_.name)=$($_.content)" }) -join ', ')" }
    Set-Content $last $ip
} catch { Log "ERROR $_" }
