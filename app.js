'use strict';

const regions = { issue: '어제의 ISSUE', kr: '국내', world: '해외' };
const topics = { society: '사회', economy: '경제', architecture: '건축' };
const ARCHIVE_SECTIONS = { competition: '건축공모', practice: '건축사·업계' };
const el = id => document.getElementById(id);
const archive = el('archive');
const filters = el('filters');
const statusBox = el('status');
const articles = el('articles');
const timeZone = 'Asia/Seoul';
const issueDate = new Intl.DateTimeFormat('ko-KR', { dateStyle: 'full', timeZone });
const stamp = new Intl.DateTimeFormat('ko-KR', { dateStyle: 'medium', timeStyle: 'short', timeZone });
const dayParts = new Intl.DateTimeFormat('en-CA', {year:'numeric', month:'2-digit', day:'2-digit', timeZone});
let region = 'issue';
let issueIndex = 0;
let topic = 'society';
let edition = null;
let request = 0;

function node(tag, value, className) {
  const result = document.createElement(tag);
  if (value !== undefined) result.textContent = value;
  if (className) result.className = className;
  return result;
}

function external(label, url) {
  const anchor = node('a', label);
  const target = new URL(url);
  if (!['https:', 'http:'].includes(target.protocol)) throw new Error('Invalid URL');
  anchor.href = target.href;
  anchor.target = '_blank';
  anchor.rel = 'noopener noreferrer';
  return anchor;
}

async function json(path) {
  const response = await fetch(path, {cache:'no-cache'});
  if (!response.ok) throw new Error('데이터를 불러오지 못했습니다.');
  return response.json();
}

function setStatus(label, warning = false) {
  statusBox.textContent = label;
  statusBox.classList.toggle('warn', warning);
}

function card(item, featured = false) {
  const article = node('article', undefined, featured ? 'story-feature' : 'story');
  const meta = node('p', item.source + ' · ', 'meta');
  const date = node('time', item.published.slice(0, 10));
  date.dateTime = item.published;
  meta.append(date);
  if (item.cached) meta.append(' · 이전 수집분');
  const link = external('원문 보기', item.url);
  link.setAttribute('aria-label', item.title + ' 원문 보기');
  article.append(meta, node('h3', item.title));
  if (item.summary && !/^(세부 내용은 언론사 원문|출처에서 별도의 요약)/.test(item.summary)) {
    article.append(node('p', item.summary, 'story-summary'));
  }
  article.append(link);
  return article;
}

function desk(item) {
  return item.desk || (/(?:-economy|-business)$/.test(item.sourceId) ? 'economy' : 'society');
}

function newsOrder(a, b) {
  return Number(Boolean(a.cached)) - Number(Boolean(b.cached)) ||
    (b.importance ?? 0) - (a.importance ?? 0) ||
    b.published.localeCompare(a.published);
}

function groupSection(label, tone, items) {
  const section = node('section', undefined, 'article-section');
  section.dataset.tone = tone;
  const header = node('div', undefined, 'section-heading');
  header.append(node('h2', label), node('span', items.length + '건'));
  section.append(header);
  if (!items.length) {
    section.append(node('p', '이 아침판에 표시할 항목이 없습니다.', 'empty'));
    return section;
  }
  const featured = node('div', undefined, 'lead-grid');
  featured.append(...items.slice(0, 2).map(item => card(item, true)));
  section.append(featured);
  if (items.length > 2) {
    const rest = node('div', undefined, 'card-grid');
    rest.append(...items.slice(2).map(item => card(item)));
    section.append(rest);
  }
  return section;
}

const issueSection = { society: '사회', economy: '경제', architecture: '건축' };
const issueArts = {
  civic: '시민과 공공기관을 그린 일러스트',
  economy: '금융시장과 화폐를 그린 일러스트',
  architecture: '건물과 설계 도면을 그린 일러스트',
  world: '지구와 국제 교류를 그린 일러스트',
  safety: '도시의 날씨와 안전을 그린 일러스트',
  technology: '반도체와 전력망을 그린 일러스트',
};

// Publicly licensed photographs reviewed for an exact article or named location.
const issuePhotos = [
  {
    matches: item => item.sourceId.startsWith('yna-') &&
      (/^https:\/\/www\.yna\.co\.kr\/view\/AKR20261120117100061(?:[?#]|$)/.test(item.url) ||
       /평택시청/.test(item.title)),
    url: 'https://upload.wikimedia.org/wikipedia/commons/f/f7/Pyeongtaek_City_Hall.JPG',
    source: 'https://commons.wikimedia.org/wiki/File:Pyeongtaek_City_Hall.JPG',
    label: '평택시청',
    year: '2015',
    credit: 'Hyolee2',
    license: 'CC BY-SA 3.0',
    licenseUrl: 'https://creativecommons.org/licenses/by-sa/3.0/',
  },
  {
    matches: item => /^https:\/\/www\.bbc\.co\.uk\/news\/articles\/ck20vl1dd8qzo(?:[?#]|$)/.test(item.url) ||
      /\bHuntsville Unit\b/.test(item.title),
    url: 'https://upload.wikimedia.org/wikipedia/commons/2/2e/HuntsvilleUnitHuntsvilleTX.jpg',
    source: 'https://commons.wikimedia.org/wiki/File:HuntsvilleUnitHuntsvilleTX.jpg',
    label: '텍사스 헌츠빌 교도소',
    year: '2007',
    credit: 'Nick DiFonzo',
    license: 'CC BY 2.0',
    licenseUrl: 'https://creativecommons.org/licenses/by/2.0/',
  },
  {
    matches: item => /\bRikers Island\b|라이커스\s*(섬|아일랜드)/i.test(item.title),
    url: 'https://upload.wikimedia.org/wikipedia/commons/5/5b/Rikers_Island_from_the_air.JPG',
    source: 'https://commons.wikimedia.org/wiki/File:Rikers_Island_from_the_air.JPG',
    label: '뉴욕 라이커스섬',
    year: '2008',
    credit: 'Cdogsimmons',
    license: '퍼블릭 도메인',
  },
];

function showIssuePicture(picture, item, art) {
  function illustration() {
    picture.classList.remove('issue-picture-photo');
    picture.dataset.art = art;
    picture.setAttribute('role', 'img');
    picture.setAttribute('aria-label', issueArts[art]);
    const note = node('span', '주제 일러스트', 'issue-art-note');
    note.setAttribute('aria-hidden', 'true');
    picture.replaceChildren(note);
  }

  illustration();
  const photo = issuePhotos.find(entry => entry.matches(item));
  if (!photo) return;

  const img = node('img', undefined, 'issue-news-photo');
  img.alt = photo.label + ' 자료사진';
  img.decoding = 'async';
  img.referrerPolicy = 'no-referrer';
  img.addEventListener('load', () => {
    picture.classList.add('issue-picture-photo');
    picture.removeAttribute('role');
    picture.removeAttribute('aria-label');
    const credit = node('figcaption', undefined, 'issue-photo-credit');
    credit.append('자료사진 · ' + photo.label + ' (' + photo.year + ')', node('br'),
      external(photo.credit + ' / Wikimedia Commons', photo.source), ' · ');
    credit.append(photo.licenseUrl ? external(photo.license, photo.licenseUrl) : photo.license);
    picture.replaceChildren(img, credit);
  }, { once: true });
  img.src = photo.url;
}

function issueKind(item) {
  if (item.category === 'competition' || item.category === 'practice' || item.category.endsWith('-arch')) return 'architecture';
  return desk(item);
}

function issueArt(item, kind) {
  if (kind === 'architecture') return 'architecture';
  if (/폭우|폭설|지진|태풍|재난|산불|대피|\b(flood|storm|earthquake|wildfire|evacuat)/i.test(item.title)) return 'safety';
  if (/반도체|인공지능|전력망|\b(AI|semiconductors?|chips?|power grid)\b/i.test(item.title)) return 'technology';
  if (kind === 'economy') return 'economy';
  return item.category.startsWith('world') ? 'world' : 'civic';
}

function previousDate(date) {
  const value = new Date(date + 'T00:00:00Z');
  value.setUTCDate(value.getUTCDate() - 1);
  return value.toISOString().slice(0, 10);
}

function recapItems() {
  if (Array.isArray(edition.issues)) return edition.issues;
  const groups = new Set();
  return edition.items.filter(item => !item.cached && item.published.startsWith(previousDate(edition.date)) &&
    item.summary?.length >= 28 && !/^(세부 내용은|기사 내용은|출처에서 별도의 요약|건축공간연구원)/.test(item.summary))
    .sort(newsOrder).filter(item => {
      const kind = issueKind(item);
      const group = kind === 'architecture' ? kind : item.category + '/' + kind;
      if (groups.has(group)) return false;
      groups.add(group);
      return true;
    });
}

function shortRecap(value) {
  const text = value.replace(/\s+/g, ' ').trim();
  const limit = /[가-힣]/.test(text) ? 115 : 145;
  if (text.length <= limit) return text;
  const slice = text.slice(0, limit);
  const boundary = slice.lastIndexOf(' ');
  return (boundary >= limit * 0.8 ? slice.slice(0, boundary) : slice).replace(/[\s.,…]+$/, '') + '…';
}

function showIssue() {
  const list = recapItems();
  const date = edition.issueDate || previousDate(edition.date);
  const section = node('section', undefined, 'issue-section');
  section.setAttribute('aria-label', '어제의 ISSUE');
  const header = node('div', undefined, 'issue-heading');
  const day = node('time', issueDate.format(new Date(date + 'T00:00:00+09:00')));
  day.dateTime = date;
  header.append(node('h2', '어제의 ISSUE'), day);
  section.append(header);
  if (!list.length) {
    section.append(node('p', '전날 발행 기사 중 이 아침판에서 확인할 수 있는 요약이 없습니다.', 'empty'));
    articles.replaceChildren(section);
    return;
  }

  const frame = node('div', undefined, 'issue-carousel');
  frame.setAttribute('aria-roledescription','슬라이드 모음');
  frame.setAttribute('role','group');
  frame.setAttribute('aria-label','전날 주요 뉴스');
  const viewport = node('div', undefined, 'issue-viewport');
  viewport.setAttribute('aria-live', 'polite');
  const controls = node('div', undefined, 'issue-controls');
  const dots = node('div', undefined, 'issue-dots');
  const progress = node('span', undefined, 'issue-progress');
  const back = node('button', '이전');
  const next = node('button', '다음');
  back.type = next.type = 'button';
  back.setAttribute('aria-label','이전 이슈');
  next.setAttribute('aria-label','다음 이슈');
  controls.append(back, dots, progress, next);
  frame.append(viewport);
  if (list.length > 1) frame.append(controls);
  let firstTouch = null;

  function change(index) {
    issueIndex = Math.min(list.length - 1, Math.max(0, index));
    const item = list[issueIndex];
    const kind = issueKind(item);
    const art = issueArt(item, kind);
    const story = node('article', undefined, 'issue-card');
    story.setAttribute('aria-label', String(issueIndex + 1) + ' / ' + list.length);
    const picture = node('figure', undefined, 'issue-picture');
    showIssuePicture(picture, item, art);
    const content = node('div', undefined, 'issue-copy');
    const location = item.category.startsWith('world') ? '해외' : '국내';
    const link = external('원문 보기', item.url);
    link.setAttribute('aria-label', item.title + ' 원문 보기');
    content.append(node('p', location + ' · ' + issueSection[kind], 'issue-topic'),
      node('h3', item.title), node('p', shortRecap(item.summary), 'issue-summary'),
      node('p', item.source, 'issue-source'), link);
    story.append(picture, content);
    viewport.replaceChildren(story);
    progress.textContent = String(issueIndex + 1) + ' / ' + list.length;
    back.setAttribute('aria-disabled', String(issueIndex === 0));
    next.setAttribute('aria-disabled', String(issueIndex === list.length - 1));
    for (const [slot, button] of [...dots.children].entries()) {
      if (slot === issueIndex) button.setAttribute('aria-current', 'true');
      else button.removeAttribute('aria-current');
    }
  }

  back.addEventListener('click', () => { if (issueIndex > 0) change(issueIndex - 1); });
  next.addEventListener('click', () => { if (issueIndex < list.length - 1) change(issueIndex + 1); });
  list.forEach((_, index) => {
    const button = node('button');
    button.type = 'button';
    button.setAttribute('aria-label', String(index + 1) + '번째 이슈 보기');
    button.addEventListener('click', () => change(index));
    dots.append(button);
  });
  frame.addEventListener('keydown', event => {
    const destinations = { ArrowLeft: issueIndex - 1, ArrowRight: issueIndex + 1, Home: 0, End: list.length - 1 };
    if (!Object.hasOwn(destinations, event.key) || event.altKey || event.ctrlKey || event.metaKey) return;
    event.preventDefault();
    change(destinations[event.key]);
  });
  viewport.addEventListener('pointerdown', event => {
    if (event.pointerType !== 'touch' || event.target.closest('a')) return;
    firstTouch = [event.clientX, event.clientY];
  });
  viewport.addEventListener('pointercancel', () => { firstTouch = null; });
  viewport.addEventListener('pointerup', event => {
    if (!firstTouch) return;
    const horizontal = event.clientX - firstTouch[0];
    const vertical = event.clientY - firstTouch[1];
    firstTouch = null;
    if (Math.abs(horizontal) > 45 && Math.abs(horizontal) > Math.abs(vertical)) change(issueIndex - Math.sign(horizontal));
  });
  change(issueIndex);
  section.append(frame);
  articles.replaceChildren(section);
}

function showArticles() {
  if (!edition) return;
  const topicTabs = filters.querySelector('.topic-tabs');
  topicTabs.hidden = region === 'issue';
  if (region === 'issue') {
    for (const button of filters.querySelectorAll('button[data-region]')) {
      button.setAttribute('aria-pressed', String(button.dataset.region === region));
    }
    showIssue();
    return;
  }
  const sections = [];
  if (topic === 'architecture') {
    const kinds = [[region + '-arch', regions[region] + ' 건축이슈']];
    if (region === 'kr') kinds.push(...Object.entries(ARCHIVE_SECTIONS));
    for (const [id, label] of kinds) {
      sections.push(groupSection(label, topic, edition.items.filter(item => item.category === id)));
    }
  } else {
    const items = edition.items.filter(item => item.category === region + '-news' && desk(item) === topic)
      .sort(newsOrder).slice(0, 4);
    sections.push(groupSection(regions[region] + ' ' + topics[topic], topic, items));
  }
  articles.replaceChildren(...sections);
  for (const button of filters.querySelectorAll('button')) {
    const active = button.dataset.region === region || button.dataset.topic === topic;
    button.setAttribute('aria-pressed', String(active));
  }
}

function makeTabs(label, className, choices, key) {
  const row = node('div', undefined, 'tab-row ' + className);
  row.setAttribute('role', 'group');
  row.setAttribute('aria-label', label);
  for (const [id, text] of Object.entries(choices)) {
    const button = node('button', text);
    button.type = 'button';
    button.dataset[key] = id;
    button.setAttribute('aria-controls', 'articles');
    row.append(button);
  }
  return row;
}

async function openEdition(date) {
  const id = ++request;
  edition = null;
  issueIndex = 0;
  articles.replaceChildren();
  articles.setAttribute('aria-busy','true');
  el('sources').hidden = true;
  filters.hidden = true;
  el('updated').textContent = '';
  el('edition-title').textContent = issueDate.format(new Date(date + 'T00:00:00+09:00'));
  setStatus('아침판을 불러오는 중입니다.');
  try {
    const next = await json('data/' + date + '.json');
    if (request !== id) return;
    const removedSources = new Set(['law', 'g2b']);
    next.sources = next.sources.filter(source => !removedSources.has(source.id));
    next.items = next.items.filter(item => !removedSources.has(item.sourceId));
    edition = next;
    const failures = edition.sources.filter(source => source.state === 'failed').length;
    const missing = edition.sources.filter(source => source.state === 'unconfigured').length;
    const today = Object.fromEntries(dayParts.formatToParts(new Date()).map(part => [part.type, part.value]));
    const old = date === archive.options[0]?.value && date !== [today.year, today.month, today.day].join('-');
    const lines = [];
    if (old) lines.push('오늘 아침판이 아직 게시되지 않아 최근 아침판을 표시합니다.');
    if (failures) lines.push('출처 ' + failures + '곳의 수집에 실패했습니다.');
    if (missing) lines.push('출처 ' + missing + '곳의 연결 설정이 필요합니다.');
    setStatus(lines.join(' ') || '수집 완료 · ' + edition.items.length + '건', Boolean(failures || missing || old));
    el('updated').textContent = '수집 시각 ' + stamp.format(new Date(edition.checked)) + ' KST';
    const list = el('source-list');
    list.replaceChildren(...edition.sources.map(source => {
      const li = node('li');
      const label = {ok:'수집 완료', failed:'수집 실패', unconfigured:'API 연결 필요'}[source.state];
      const count = source.state === 'ok' ? ' (' + source.count + '건)' :
        source.count ? ' (이전 수집분 ' + source.count + '건)' : '';
      li.append(external(source.name, source.info), ' · ' + label + count);
      return li;
    }));
    showArticles();
    filters.hidden = false;
    el('sources').hidden = false;
  } catch {
    if (request === id) setStatus('선택한 아침판을 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.', true);
  } finally {
    if (request === id) articles.setAttribute('aria-busy','false');
  }
}

filters.append(
  makeTabs('지역', 'region-tabs', regions, 'region'),
  makeTabs('분야', 'topic-tabs', topics, 'topic'),
);
filters.addEventListener('click', event => {
  const button = event.target.closest('button');
  if (!button) return;
  if (button.dataset.region) region = button.dataset.region;
  if (button.dataset.topic) topic = button.dataset.topic;
  showArticles();
});
archive.addEventListener('change', () => {
  const url = new URL(location.href);
  url.searchParams.set('date', archive.value);
  history.replaceState(null, '', url);
  openEdition(archive.value);
});

(async () => {
  try {
    const index = await json('data/index.json');
    const dates = index.dates.filter(date => /^\d{4}-\d{2}-\d{2}$/.test(date));
    if (!dates.length) {
      setStatus('첫 수집을 기다리고 있습니다.');
      articles.setAttribute('aria-busy','false');
      return;
    }
    archive.replaceChildren(...dates.map(date => new Option(date, date)));
    archive.disabled = false;
    const requested = new URL(location.href).searchParams.get('date');
    archive.value = dates.includes(requested) ? requested : dates[0];
    await openEdition(archive.value);
  } catch {
    setStatus('아카이브를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.', true);
    articles.setAttribute('aria-busy','false');
  }
})();
