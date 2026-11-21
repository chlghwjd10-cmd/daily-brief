# DAILY BRIEF

국내외 사회·경제, 국내외 건축이슈, 건축공모, 건축사·업계 소식을 모아 보는 한국어 아침 뉴스 사이트입니다. 설치할 라이브러리 없이 PowerShell 수집기와 정적 웹사이트를 사용합니다.

## GitHub Pages 배포

1. 압축 파일을 풀고 `.github` 폴더를 포함해 파일을 GitHub 공개 저장소의 기본 브랜치 루트에 올립니다.
2. 저장소에서 **Settings → Pages → Build and deployment → Source → GitHub Actions**를 선택합니다.
3. **Actions → DAILY BRIEF → Run workflow**에서 기본 브랜치를 선택합니다. 실행의 `deploy` 단계와 **Settings → Pages**의 배포 상태가 성공이면 해당 화면에서 사이트 주소를 확인합니다.

예약 실행은 매일 UTC 22:00, 한국시간으로 다음 날 오전 07:00에 시작합니다. 수집·배포 시간만큼 게시 시각에 차이가 있습니다. 기본 브랜치에 자동 아카이브 커밋을 저장할 수 있어야 합니다. 브랜치 규칙으로 직접 푸시가 막혀 있는 저장소라면 규칙에 맞게 아카이브 저장 정책을 구성하세요.

### 비용과 제한

- 공개 저장소의 GitHub Pages와 표준 GitHub 호스팅 러너는 GitHub Free에서 사용할 수 있습니다. [Pages 설정](https://docs.github.com/en/pages/getting-started-with-github-pages/using-custom-workflows-with-github-pages) · [Actions 요금](https://docs.github.com/en/actions/concepts/billing-and-usage)
- GitHub Actions는 정각 등 혼잡 시 예약이 지연되거나 누락될 수 있습니다. 공개 저장소에서 60일 동안 활동이 없으면 예약 실행이 비활성화됩니다. 누락 시 같은 작업을 수동 실행할 수 있습니다. [예약 실행 동작](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)
- Render 정적 사이트는 무료로 제공됩니다. Render에서 예약 수집까지 운영하는 경우 Cron Job은 서비스당 월 최소 US$1이며, 무료 웹 서비스는 15분 비활성 후 절전됩니다. 이 패키지의 배포 설정은 GitHub Pages용입니다. [Render 무료 요금제](https://render.com/docs/free) · [Render Cron Job](https://render.com/docs/cronjobs)

## 데이터와 수집 상태

- 연합뉴스·SBS 뉴스·동아일보·매일경제의 사회·경제, BBC World·Business, ArchDaily의 발행사 RSS와 [건축HUB](https://www.hub.go.kr/portal/dps/dsr/idx-dsr-selectDesignPbpPbancList.do), [건축공간연구원](https://www.auri.re.kr/index.asp)의 공식 게시물을 사용합니다. [C3코리아](https://c3korea.com/category/recent/)의 최신 기사 목록와 [월간 SPACE](https://vmspace.com/news/news.html)의 뉴스 목록, [프로젝트 서울](https://project.seoul.go.kr/view/viewListNotice.do?noticeType=CPTT)의 공모 알림을 추가로 수집합니다. 기관 HTML이 바뀌면 해당 파서를 업데이트해야 합니다.
- 국내·해외별 사회 4건, 경제 4건까지 표시합니다. 제목에서 주요 정책, 경제지표, 전국적 영향, 재난·안전 등의 신호를 반영해 우선순위를 정합니다. 국내는 매체당 최대 3건, 같은 매체의 같은 분야는 최대 2건을 표시합니다. 새 언론사 피드는 제목·날짜·원문 링크를 공개합니다.
- 일반 뉴스는 제목과 공개 요약에서 공공건축, 설계공모, 도시계획, 문화유산 복원, 건축물 안전 등 관련성이 높은 기사를 국내외 건축이슈에 분류합니다. C3코리아는 제목·발행일·원문 링크를 수집합니다.
- 해외 기사의 RSS 요약은 출처 언어로 표시합니다. 요약은 RSS 설명의 첫 문장 또는 기관이 제공한 공고 정보를 사용하며, RSS에 요약이 없으면 그렇게 표시합니다. 발행사 본문·사진은 다운로드하지 않습니다. 공개 운영 전 발행사별 RSS 이용 조건을 확인하세요.
- 날짜와 발행사 원문 주소가 확인된 항목을 표시합니다. 한 아침판에서 추적 매개변수를 제거한 URL과 정규화한 제목이 같은 항목은 한 번만 표시합니다. 제목이 서로 다른 동일 사건은 각각 표시될 수 있습니다.
- 사회·경제는 최근 2일, 건축은 출처별 7~30일의 자료를 확인해 섹션별 최신 12건을 표시합니다. 아침판 날짜와 발행일은 한국시간 기준입니다. 공모의 참가는 공식 공고를 기준으로 확인하세요.
- 실패한 출처는 이전 수집분이 유효 기간 안에 있으면 '이전 수집분'으로 표시합니다. 날짜가 같은 실행은 그날 아침판을 갱신하고 이전 날짜는 보존합니다.

## 로컬에서 실행

PowerShell 7과 Python 3가 있다면 압축을 푼 폴더에서 다음 명령을 실행합니다. Python은 미리보기 서버에만 사용됩니다.

```powershell
pwsh -NoProfile -File ./collect.ps1
New-Item -ItemType Directory -Force work-preview | Out-Null
Copy-Item index.html,style.css,app.js,site/data work-preview -Recurse -Force
python -m http.server 8080 --bind 127.0.0.1 --directory work-preview
```

브라우저에서 `http://127.0.0.1:8080`을 엽니다.

## 파일

- `collect.ps1` · 수집, 검증, 분류, 중복 제거, 상태 처리, 날짜별 저장
- `sources.json` · 수집 출처 및 원문 도메인 설정
- `site/` · 모바일 대응 브리핑과 아카이브
- `.github/workflows/brief.yml` · 예약 수집, 아카이브 커밋, Pages 배포
