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
            if ($id -in @('arch','c3')) {
                $file = [IO.Path]::GetTempFileName()
                try {
                    $curl = if ($env:OS -eq 'Windows_NT') { 'curl.exe' } else { 'curl' }
                    $status = & $curl --silent --show-error --location --max-redirs 5 --max-time 20 --user-agent 'DailyBrief/1.0 (news feed reader)' --output $file --write-out '%{http_code} %{content_type}' $url
                    if ($LASTEXITCODE -ne 0 -or $status -notmatch '^200\s') { throw "HTTP $status (curl exit $LASTEXITCODE)" }
                    return [IO.File]::ReadAllText($file)
                } finally {
                    [IO.File]::Delete($file)
                }
            }
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

function Get-GeneralArchitectureCategory($source, $title, $description) {
    if ($source.category -eq 'kr-news') {
        if ($title -match '공공건축|설계\s*공모|건축가|건축사사무소|도시재생|도시계획|건축문화재|건축법|건축물\s*안전|건축\s*인허가|부실시공') { return 'kr-arch' }
        if ($title -match '건립|재건축|재개발|리모델링|신축|복원|개관|붕괴' -and "$title $description" -match '공공시설|도서관|미술관|박물관|문화유산|문화재|설계안|설계변경|건축심의|구조\s*안전|주택\s*공급\s*계획') { return 'kr-arch' }
    }
    if ($source.category -eq 'world-news') {
        if ($title -match '\b(architects?|architectural designs?|urban planning|design competition|building safety|heritage restoration|Pritzker)\b') { return 'world-arch' }
        if ($title -match '\b(museum|library|buildings?|housing|landmark|heritage)\b' -and "$title $description" -match '\b(redevelopment|restoration|renovation|design unveiled|designed by|structural failure|planning approval)\b') { return 'world-arch' }
    }
}

function Get-PublisherCategory($title, $tags) {
    if ("$title $tags" -match '설계\s*공모|건축\s*공모|공모전|공모결과') { return 'competition' }
    if ($tags -match '해외건축|해외뉴스|c3globe|^세계$' -or $title -match '홍콩|타슈켄트|우즈베키스탄|벨기에|불가리아') { return 'world-arch' }
    if ($title -match '건축상|건축가상|건축비평|건축포럼|건축계|건축가협회') { return 'practice' }
    return 'kr-arch'
}

function Read-C3Listing($source) {
    $html = Get-Body $source.url $source.id
    $cards = [regex]::Matches($html, '(?is)<article\b[^>]*class="[^"]*\bjeg_post\b[^"]*"[^>]*>(.*?)</article>')
    if (!$cards.Count) {
        $pageTitle = Get-PlainText ([regex]::Match($html,'(?is)<title[^>]*>(.*?)</title>').Groups[1].Value)
        if ($pageTitle.Length -gt 90) { $pageTitle = $pageTitle.Substring(0,90) }
        $hasHeadings = $html.Contains('jeg_post_title')
        $challenge = $html -match 'cf-chl|challenges\.cloudflare\.com|Checking your browser|Just a moment|captcha'
        throw "C3 listing format not recognized (title: $pageTitle; size: $($html.Length); article headings: $hasHeadings; verification page: $challenge)"
    }
    foreach ($card in $cards) {
        $heading = [regex]::Match($card.Value,'(?is)<h[23] class="jeg_post_title">\s*<a href="(?<url>[^"]+)"[^>]*>(?<title>.*?)</a>')
        $date = [regex]::Match($card.Value,'(?is)<div class="jeg_meta_date">.*?(\d{4}-\d{2}-\d{2})\s*</a>').Groups[1].Value
        $tag = [regex]::Match($card.Value,'(?is)<div class="jeg_post_category"[^>]*>(.*?)</div>').Groups[1].Value
        if (!$heading.Success -or !$date) { continue }
        $title = Get-PlainText $heading.Groups['title'].Value
        $link = [Net.WebUtility]::HtmlDecode($heading.Groups['url'].Value)
        $category = Get-PublisherCategory $title (Get-PlainText $tag)
        New-ItemRecord $source $category $title $link $date '기사 내용은 C3코리아 원문에서 확인할 수 있습니다.'
    }
}

function Read-OfficialListing($source) {
    $html = Get-Body $source.url $source.id
    if ($source.id -eq 'space') {
        $pattern = '(?is)<a\b[^>]*href="(?<url>[^"]*news_view\.html\?[^"]+)"[^>]*>\s*<div\b[^>]*>\s*<h4[^>]*>(?<title>.*?)</h4>\s*<p\b[^>]*class="lead-report"[^>]*>(?<summary>.*?)</p>\s*<p class="date">(?<date>\d{4}\.\d{2}\.\d{2})</p>'
    } else {
        $pattern = '(?is)<a\b[^>]*class="ps-notice-row[^"]*"[^>]*href="(?<url>/view/viewDetailCptt\.do\?[^"]+)"[^>]*>\s*<span class="dt[^"]*">\s*(?<date>\d{4}\.\d{2}\.\d{2})\s*</span>\s*<span class="ttl">\s*<span class="src">(?<competition>.*?)</span>(?<title>.*?)</span>'
    }
    $rows = [regex]::Matches($html,$pattern)
    if (!$rows.Count) {
        if ($source.id -eq 'seoul' -and $html -match '등록된 (게시물|공지사항)이 없습니다') { return }
        throw 'Official listing format not recognized'
    }
    foreach ($row in $rows) {
        $title = Get-PlainText $row.Groups['title'].Value
        $summary = Get-PlainText $row.Groups['summary'].Value
        $category = Get-PublisherCategory $title ''
        if ($source.id -eq 'seoul') {
            $category = 'competition'
            $competition = Get-PlainText $row.Groups['competition'].Value
            $title = "$competition $title"
            $summary = '서울시 공식 공모 알림 · ' + $competition.Trim('[',']')
        }
        $date = $row.Groups['date'].Value.Replace('.','-')
        $relative = [Net.WebUtility]::HtmlDecode($row.Groups['url'].Value)
        $link = [Uri]::new([Uri]$source.url,$relative).AbsoluteUri
        if ($summary.Length -gt 150) { $summary = $summary.Substring(0,150).TrimEnd() + '…' }
        if (!$summary) { $summary = '세부 내용은 발행처 원문에서 확인할 수 있습니다.' }
        New-ItemRecord $source $category $title $link $date $summary
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
        $generalArchitecture = Get-GeneralArchitectureCategory $source $title $description
        if ($generalArchitecture) { $category = $generalArchitecture }
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
                'listing' { Read-OfficialListing $source }
                'c3-listing' { Read-C3Listing $source }
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
            if ($source.id -in @('arch','c3')) {
                $response = $_.Exception.Response
                if ($response) {
                    $challenge = $response.Headers -and ($response.Headers | Out-String) -match 'cf-mitigated'
                    Write-Warning "$($source.name) RSS returned HTTP $([int]$response.StatusCode); challenge header: $challenge"
                } else {
                    Write-Warning "$($source.name) source: $($_.Exception.Message). $($_.ScriptStackTrace)"
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
$architectureCounts = @{}
$priority = @{
    Expression = {
        if ($_.category -in @('kr-arch','world-arch') -and $_.sourceId -in @('c3','space','yna-social','yna-economy','world','world-business')) { 0 } else { 1 }
    }
    Ascending = $true
}
$digest = @(foreach ($item in ($items | Sort-Object @{Expression={ [bool]$_.cached }; Ascending=$true}, $priority, @{Expression={$_.published}; Descending=$true})) {
    $headline = ($item.title.Normalize([Text.NormalizationForm]::FormKC).ToLowerInvariant() -replace '[^\p{L}\p{N}]','')
    if ($seenUrls.ContainsKey($item.key) -or ($headline.Length -ge 12 -and $seenTitles.ContainsKey($headline))) { continue }
    if ([int]$counts[$item.category] -ge 12) { continue }
    if ($item.category -in @('kr-arch','world-arch') -and $item.sourceId -ne 'arch') {
        $group = if ($item.sourceId -in @('yna-social','yna-economy','world','world-business')) { 'general' } else { $item.sourceId }
        $slot = "$($item.category)/$group"
        if ([int]$architectureCounts[$slot] -ge 6) { continue }
        $architectureCounts[$slot] = 1 + [int]$architectureCounts[$slot]
    }
    $seenUrls[$item.key] = $true
    $seenTitles[$headline] = $true
    $counts[$item.category] = 1 + [int]$counts[$item.category]
    $item
})
Write-Json (Join-Path $data "$day.json") @{ date = $day; checked = $now.ToString('o'); sources = @($statuses); items = @($digest | Sort-Object @{Expression={ [bool]$_.cached }; Ascending=$true}, @{Expression={$_.published}; Descending=$true}) }
$dates = @(Get-ChildItem -LiteralPath $data -Filter '????-??-??.json' | Sort-Object Name -Descending | ForEach-Object { $_.BaseName })
Write-Json (Join-Path $data 'index.json') @{ dates = $dates }
Write-Output ("{0} · {1} articles · {2} sources" -f $day,$digest.Count,$statuses.Count)
