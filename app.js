'use strict';

const categories = {
  'kr-news': '국내 사회·경제',
  'world-news': '해외 사회·경제',
  'kr-arch': '국내 건축이슈',
  'world-arch': '해외 건축이슈',
  competition: '건축공모',
  law: '건축법규',
  practice: '건축사·업계',
};
const el = id => document.getElementById(id);
const archive = el('archive');
const filters = el('filters');
const statusBox = el('status');
const articles = el('articles');
const timeZone = 'Asia/Seoul';
const issueDate = new Intl.DateTimeFormat('ko-KR', { dateStyle: 'full', timeZone });
const stamp = new Intl.DateTimeFormat('ko-KR', { dateStyle: 'medium', timeStyle: 'short', timeZone });
const dayParts = new Intl.DateTimeFormat('en-CA', {year:'numeric', month:'2-digit', day:'2-digit', timeZone});
let selected = 'all';
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

function card(item) {
  const article = node('article');
  const meta = node('p', item.source + ' · ', 'meta');
  const date = node('time', item.published.slice(0, 10));
  date.dateTime = item.published;
  meta.append(date);
  if (item.cached) meta.append(' · 이전 수집분');
  const link = external('원문 보기', item.url);
  link.setAttribute('aria-label', item.title + ' 원문 보기');
  article.append(meta, node('h3', item.title), node('p', item.summary), link);
  return article;
}

function showArticles() {
  if (!edition) return;
  const sections = document.createDocumentFragment();
  for (const [id, label] of Object.entries(categories)) {
    if (selected !== 'all' && selected !== id) continue;
    const items = edition.items.filter(item => item.category === id);
    const section = node('section');
    const heading = node('h2', label);
    heading.append(node('span', items.length + '건'));
    section.append(heading);
    if (items.length) {
      const grid = node('div', undefined, 'grid');
      grid.append(...items.map(card));
      section.append(grid);
    } else {
      section.append(node('p', '이 아침판에 표시할 항목이 없습니다.', 'empty'));
    }
    sections.append(section);
  }
  articles.replaceChildren(sections);
  for (const button of filters.querySelectorAll('button')) {
    button.setAttribute('aria-pressed', String(button.dataset.category === selected));
  }
}

async function openEdition(date) {
  const id = ++request;
  edition = null;
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

for (const [id, label] of Object.entries({all:'전체', ...categories})) {
  const button = node('button', label);
  button.type = 'button';
  button.dataset.category = id;
  button.setAttribute('aria-pressed', String(id === selected));
  filters.append(button);
}
filters.addEventListener('click', event => {
  if (event.target.matches('button[data-category]')) {
    selected = event.target.dataset.category;
    showArticles();
  }
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
