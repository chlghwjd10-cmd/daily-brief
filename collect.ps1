param([string]$FixtureDirectory)
$ErrorActionPreference = 'Stop'
$kst = [TimeSpan]::FromHours(9)
$now = [DateTimeOffset]::UtcNow.ToOffset($kst)
$day = $now.ToString('yyyy-MM-dd')
$data = Join-Path $PSScriptRoot 'site/data'
[void][IO.Directory]::CreateDirectory($data)
$utf8 = [Text.UTF8Encoding]::new($false)

function Write-Json($path, $value) {
    $temp = "$path.tmp"
    [IO.File]::WriteAllText($temp, (ConvertTo-Json -InputObject $value -Depth 12 -Compress), $utf8)
    Move-Item -LiteralPath $temp -Destination $path -Force
}

function Get-Body($url, $id) {
    if ($FixtureDirectory) {
        return [IO.File]::ReadAllText((Join-Path $FixtureDirectory $id))
    }
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 20 -UserAgent 'DailyBrief/1.0 (news feed reader)'
            if ($response.Content -is [byte[]]) { return [Text.Encoding]::UTF8.GetString($response.Content) }
            return $response.Content
        } catch {
            if ($attempt -eq 2) { throw }
            Start-Sleep -Seconds 2
        }
    }
}

function Get-PlainText([string]$value) {
    $value = [regex]::Replace($value, '<(?:script|style)\b[^>]*>.*?</(?:script|style)>', '', 'IgnoreCase,Singleline')
    $value = [regex]::Replace($value, '<[^>]*>', ' ')
    return ([Net.WebUtility]::HtmlDecode($value) -replace '\s+', ' ').Trim()
}

function Parse-Date([string]$value) {
    if ($value -match '^\d{8}$') { $value = $value.Insert(6,'-').Insert(4,'-') }
    if ($value -match '^\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2})?)?$') { $value += ' +09:00' }
    $date = [DateTimeOffset]::MinValue
    if ([DateTimeOffset]::TryParse($value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref]$date)) {
        return $date.ToOffset($kst)
    }
}

function New-ItemRecord($source, $category, $title, $link, $dateText, $summary) {
    $date = Parse-Date $dateText
    if (!$title -or !$date -or $date -gt $now -or $date -lt $now.AddDays(-$source.days)) { return }
    $url = $null
    if (![Uri]::TryCreate($link,[UriKind]::Absolute,[ref]$url) -or $url.Scheme -notin @('http','https') -or $url.UserInfo -or $url.Host -notmatch $source.host) { return }
    $canonical = [UriBuilder]::new($url)
    $canonical.Fragment = ''
    $canonical.Query = (($url.Query.TrimStart('?') -split '&' | Where-Object { $_ -and $_ -notmatch '^(utm_[^=]+|fbclid|gclid|at_[^=]+|input|ref|from)=' } | Sort-Object) -join '&')
    return @{
        sourceId = $source.id; source = $source.name; category = $category
        title = $title; url = $url.AbsoluteUri; key = $canonical.Uri.Host + $canonical.Uri.PathAndQuery.TrimEnd('/')
        published = $date.ToString('o'); summary = $summary
    }
}

function Read-Feed($source) {
    [xml]$xml = Get-Body $source.url $source.id
    if ($xml.DocumentElement.LocalName -ne 'rss' -or !$xml.SelectSingleNode('/rss/channel')) { throw 'Invalid feed' }
    foreach ($entry in $xml.SelectNodes('/rss/channel/item')) {
        $title = Get-PlainText ($entry.SelectSingleNode('title').InnerText)
        $link = [string]$entry.SelectSingleNode('link').InnerText
        $date = [string]$entry.SelectSingleNode('pubDate').InnerText
        $description = Get-PlainText ($entry.SelectSingleNode('description').InnerText)
        $description = $description -replace '^\([^)]{2,65}\)\s*[^=]{0,35}=\s*',''
        $category = $source.category
        if ($source.id -eq 'arch') {
            $tags = ($entry.SelectNodes('category') | ForEach-Object { $_.InnerText }) -join ' '
            $category = if ("$title $tags $description" -match '\b(competition|open call)\b' -and "$title $tags" -match 'competitions|call for entries|call for submissions|open call') { 'competition' }
                elseif ("$title $tags" -match 'Pritzker|appoint|obituary|firm merger|industry|practice|awards?') { 'practice' }
                elseif ("$title $tags $description" -match '\b(South Korea|Republic of Korea|Seoul|Busan|Incheon|Jeju|Daejeon|Daegu|Gwangju)\b') { 'kr-arch' }
                else { 'world-arch' }
        }
        $summary = if ($description) { ($description -split '(?<=[.!?。])\s+', 2)[0] } else { '' }
        if ($summary.Length -gt 180) { $summary = $summary.Substring(0,180).TrimEnd() + '…' }
        if (!$summary -or $summary -eq $title -or $summary -match '^Read more') { $summary = '출처에서 별도의 요약을 제공하지 않았습니다.' }
        New-ItemRecord $source $category $title $link $date $summary
    }
}

function Read-Hub($source) {
    $html = Get-Body $source.url $source.id
    $pattern = '(?s)<p class="tit link"><a[^>]*fnDprDesignDtlInfo\(''(?<id>[A-Z0-9]+)'',''(?<round>\d+)'',''(?<step>\d+)'',''(?<mode>[A-Z])''\);?"[^>]*>(?<title>.*?)</a></p>(?<fields>.*?)</li>'
    $rows = [regex]::Matches($html, $pattern)
    if (!$rows.Count -and $html -notmatch '총\s*<em>\s*0\s*</em>\s*건') { throw 'Unknown competition page' }
    foreach ($row in $rows) {
        if ($row.Groups['step'].Value -eq '000') { continue }
        $fields = $row.Groups['fields'].Value
        $date = [regex]::Match($fields, '공고일\s*:\s*(\d{4}-\d{2}-\d{2})').Groups[1].Value
        $lines = @(
            [regex]::Match($fields, '<p class="detail">([^<]+)').Groups[1].Value
            [regex]::Match($fields, '참가등록 기간\s*:[^<]+').Value
            [regex]::Match($fields, '작품접수 기간\s*:[^<]+').Value
        ) | ForEach-Object { Get-PlainText $_ } | Where-Object { $_ }
        $summary = ($lines -join ' · ') -replace '\(D[+-]\d+\)', ''
        $link = 'https://www.hub.go.kr/portal/dps/dpr/idx-dpr-selectDprDesignDtlInfo.do?designPbpNo={0}&cycl={1}&detailMode={2}' -f $row.Groups['id'].Value,$row.Groups['round'].Value,$row.Groups['mode'].Value
        New-ItemRecord $source 'competition' (Get-PlainText $row.Groups['title'].Value) $link $date $summary
    }
}

function Read-Auri($source) {
    $html = Get-Body $source.url $source.id
    $pattern = '(?s)<a href="(?<link>/board\.es\?[^"]*act=view[^"]*)">\s*<span class="news_cate">(?<type>[^<]*)</span>\s*<strong class="tit">(?<title>.*?)</strong>\s*<span class="date">\s*(?<month>\d{4}\.\d{2})\s*<b>(?<day>\d{2})</b>'
    $rows = [regex]::Matches($html, $pattern)
    if (!$rows.Count) { throw 'Unknown research institute page' }
    foreach ($row in $rows) {
        $type = Get-PlainText $row.Groups['type'].Value
        if ($type -eq '언론기사') { continue }
        $title = Get-PlainText $row.Groups['title'].Value
        $date = $row.Groups['month'].Value.Replace('.','-') + '-' + $row.Groups['day'].Value
        $link = 'https://www.auri.re.kr' + [Net.WebUtility]::HtmlDecode($row.Groups['link'].Value)
        $category = if ($title -match '설계공모|건축공모') { 'competition' }
            elseif ($title -match '건축사|건축서비스산업|건축업계|채용|공청회|포럼') { 'practice' }
            else { 'kr-arch' }
        $summary = "건축공간연구원 $type. 세부 내용과 일정은 기관 원문에서 확인할 수 있습니다."
        New-ItemRecord $source $category $title $link $date $summary
    }
}

$sources = Get-Content -Raw -Encoding UTF8 (Join-Path $PSScriptRoot 'sources.json') | ConvertFrom-Json
$history = @(Get-ChildItem -LiteralPath $data -Filter '????-??-??.json' | Sort-Object Name -Descending)
$previous = if ($history.Count) { Get-Content -Raw -Encoding UTF8 $history[0].FullName | ConvertFrom-Json }
$items = [Collections.Generic.List[object]]::new()
$statuses = foreach ($source in $sources) {
    $status = @{ id = $source.id; name = $source.name; info = $source.info; state = 'ok'; count = 0 }
    if ($source.secret -and ![Environment]::GetEnvironmentVariable($source.secret)) {
        $status.state = 'unconfigured'
    } else {
        try {
            $results = @(switch ($source.kind) {
                'hub' { Read-Hub $source }
                'auri' { Read-Auri $source }
                default { Read-Feed $source }
            })
            $status.count = $results.Count
            foreach ($item in $results) { $items.Add($item) }
        } catch {
            $status.state = 'failed'
            $cached = @($previous.items | Where-Object { $_.sourceId -eq $source.id -and (Parse-Date $_.published) -ge $now.AddDays(-$source.days) })
            foreach ($item in $cached) {
                $copy = @{}
                foreach ($field in $item.PSObject.Properties) { $copy[$field.Name] = $field.Value }
                $copy.cached = $true
                $items.Add($copy)
            }
            $status.count = $cached.Count
            if ($source.id -eq 'arch') {
                $response = $_.Exception.Response
                if ($response) {
                    $challenge = $response.Headers -and ($response.Headers | Out-String) -match 'cf-mitigated'
                    Write-Warning "ArchDaily RSS returned HTTP $([int]$response.StatusCode); challenge header: $challenge"
                } else {
                    Write-Warning "ArchDaily RSS: $($_.Exception.Message)"
                }
            } else {
                Write-Warning "$($source.id): collection failed ($($_.Exception.GetType().Name))"
            }
        }
    }
    $status
}

$seenUrls = @{}
$seenTitles = @{}
$counts = @{}
$digest = @(foreach ($item in ($items | Sort-Object @{Expression={ [bool]$_.cached }; Ascending=$true}, @{Expression={$_.published}; Descending=$true})) {
    $headline = ($item.title.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant() -replace '[^\p{L}\p{N}]','')
    if ($seenUrls.ContainsKey($item.key) -or ($headline.Length -ge 12 -and $seenTitles.ContainsKey($headline))) { continue }
    $seenUrls[$item.key] = $true
    $seenTitles[$headline] = $true
    if ([int]$counts[$item.category] -ge 12) { continue }
    $counts[$item.category] = 1 + [int]$counts[$item.category]
    $item
})
Write-Json (Join-Path $data "$day.json") @{ date = $day; checked = $now.ToString('o'); sources = @($statuses); items = $digest }
$dates = @(Get-ChildItem -LiteralPath $data -Filter '????-??-??.json' | Sort-Object Name -Descending | ForEach-Object { $_.BaseName })
Write-Json (Join-Path $data 'index.json') @{ dates = $dates }
Write-Output ("{0} · {1} articles · {2} sources" -f $day,$digest.Count,$statuses.Count)
