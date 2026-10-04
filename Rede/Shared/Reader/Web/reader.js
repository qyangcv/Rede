"use strict";

// 每个章节作为完整文档加载进 iframe，样式层交给 ReadiumCSS（cjk-horizontal）：
//   ReadiumCSS-before → 书自带样式 → [ReadiumCSS-default，仅当书没有样式] → ReadiumCSS-after
// 分页由 ReadiumCSS 在章节 :root 上分栏，本脚本只负责导航、锚点和进度。
// 手势只做识别并上报 Swift，是否翻页由各平台决定。

const XHTML_NS = "http://www.w3.org/1999/xhtml";
const READIUM_BASE = "rede://app/";
const ASSET_TIMEOUT_MS = 5000;
const MIN_COLUMN_EM = 20

// 版面相关的 ReadiumCSS 变量（页边距随 style 从 Swift 传入）：
// - 背景色设为 transparent：ReadiumCSS 以 !important 强制章节根元素的背景色，设为透明才能透出外壳页绘制的背景；
//   书内其他元素（含 body）的背景不受影响
const LAYOUT_VARS = {
  "--RS__backgroundColor": "transparent",
};

const frame = document.getElementById("chapter");
const ROOT = new URL(document.baseURI);

const state = {
  spinePaths: [],
  language: "",
  style: {},
  columns: 1,  // 每屏栏数，1 或 2
  chapterId: -1,
  spread: 0,
  spreadCount: 1,
  navId: 0,
  offset: 0,   // 当前页首个单位在本章坐标中的偏移量（阅读锚点），见 units()
  total: 0,    // 本章总单位数
  tocAnchors: [],
  anchors: {},
  range: null,     // 当前页的坐标区间 {start, end}，空白页为 null
  annotations: [], // 本书标注 [{id, kind, chapter, start, end, note}]，note 为是否带笔记
};

let doc = null;  // 当前章节文档
let pad = null;  // 当前章节的补白列，见 measure()
let highlights = [];  // 本章已绘制的高亮 [{id, start, end, range}]，供点击命中检测

// Swift 调用接口

const reader = {
  // 入口：保存 paths、绑定事件、恢复到 start（null 则从头开始）
  open(paths, language, style = {}, start = null, tocAnchors = [], annotations = []) {
    state.annotations = annotations;
    state.spinePaths = paths;
    state.tocAnchors = tocAnchors;
    state.language = language;
    state.style = style;
    applyStyle();
    window.addEventListener("resize", reflow);
    watchGestures(document);
    goto(start ? start.chapter : 0, start ?? 0);
  },

  // 本书标注变化：重绘本章高亮，并重新上报本页信息（书签角标、仿真翻页据此重截当前页）；
  // 章节加载中时由 goto 在 prepare 之后读取最新标注
  setAnnotations(list) {
    state.annotations = list;
    if (!doc || frame.classList.contains("loading")) return;
    paintHighlights();
    report();
  },

  // 取出章节里的选区并清除：返回 {chapter, start, end, text}；没有选区或选区不含任何单位时返回 null
  takeSelection() {
    const selection = doc?.getSelection();
    if (!selection || selection.isCollapsed) return null;
    const range = selection.getRangeAt(0);
    const start = offsetAt(range.startContainer, range.startOffset);
    const end = offsetAt(range.endContainer, range.endOffset);
    const rects = range.getClientRects();
    selection.removeAllRanges();
    if (start >= end || rects.length === 0) return null;
    // 原生侧把笔记编辑框指向选区末行
    const rect = shellRect(rects[rects.length - 1]);
    return { chapter: state.chapterId, start, end, text: excerpt(start, end - start), rect };
  },

  // 前后翻 delta 页，返回是否落位
  turn(delta) {
    return turn(delta);
  },

  // 相邻页渲染用：先落到 position 所在页，再翻 delta 页，返回落位后的进度；
  // 到书头书尾或被后续导航打断时返回 null
  async peek(position, delta) {
    const moved = await goto(position.chapter, position) && await turn(delta);
    return moved ? progress() : null;
  },

  jump(chapter, anchor) {
    goto(chapter, anchor || 0);
  },

  // 跳到保存的阅读位置：跟随其他设备同步来的进度，或仿真翻页翻完后同步到卷页层停下的那一页
  restore(position) {
    return goto(position.chapter, position);
  },

  setStyle(vars) {
    Object.assign(state.style, vars);
    reflow();
  },
};

// 翻一页，到章首章尾时载入相邻章节；返回是否落位
async function turn(delta) {
  const spread = state.spread + delta;
  if (spread >= 0 && spread < state.spreadCount) {
    settle(spread);
    return true;
  }
  return goto(state.chapterId + delta, delta > 0 ? 0 : -1);
}

// 导航，at 为数字（页码）、字符串（锚点）或位置对象；返回是否落位（被后续导航打断时为 false）
async function goto(chapter, at) {
  const path = state.spinePaths[chapter];
  if (path === undefined) return false;
  const token = ++state.navId;

  if (chapter !== state.chapterId) {
    frame.classList.add("loading");
    const loaded = await load(new URL(path.split("/").map(encodeURIComponent).join("/"), ROOT));
    if (token !== state.navId) return false;

    doc = loaded;
    state.chapterId = chapter;
    await prepare(doc);
    if (token !== state.navId) return false;
    state.total = contentLength();
    state.anchors = anchorOffsets(state.tocAnchors[chapter] ?? []);
    paintHighlights();
  }

  measure();
  // 从保存的位置恢复时沿用原锚点，不重新测量，避免多次恢复逐页回退
  settle(locate(at), isPosition(at) ? at.offset : null);
  frame.classList.remove("loading");
  return true;
}

// 把章节载入 iframe；被后续导航打断时由下一次 load 事件唤醒，交给 navId 丢弃
function load(url) {
  return new Promise((resolve) => {
    frame.addEventListener("load", () => resolve(frame.contentDocument), { once: true });
    frame.src = url.href;
  });
}

// 注入 ReadiumCSS、补齐语言、绑定事件，等样式和资源就绪
async function prepare(doc) {
  const root = doc.documentElement;
  if (!root.getAttribute("lang") && !root.getAttribute("xml:lang") && state.language) {
    root.setAttribute("lang", state.language);
  }

  // 关闭 macOS 的笔画扩张，即字体平滑，字形按原始轮廓渲染，粗细交给 --USER__fontWeight 控制
  root.style.webkitFontSmoothing = "antialiased";

  const head = doc.head ?? root.insertBefore(doc.createElementNS(XHTML_NS, "head"), root.firstChild);
  const unstyled = !doc.querySelector('link[rel~="stylesheet"], style');
  const fonts = stylesheet(doc, "fonts.css");
  const before = stylesheet(doc, "ReadiumCSS-before.css");
  const after = [
    ...(unstyled ? [stylesheet(doc, "ReadiumCSS-default.css")] : []),
    stylesheet(doc, "ReadiumCSS-after.css"),
  ];
  const marks = doc.createElementNS(XHTML_NS, "style");
  marks.textContent = `${HIGHLIGHT_LAYERS.map((name) => `::highlight(${name})`).join(", ")}
    { background-color: var(--reader-highlight); }
    ::highlight(${NOTE_LAYER}) { text-decoration: underline dashed 1.5px var(--reader-note); }`;
  head.prepend(fonts, before);
  head.append(...after, marks);
  for (const name of [...HIGHLIGHT_LAYERS, NOTE_LAYER]) {
    doc.defaultView.CSS.highlights.set(name, new doc.defaultView.Highlight());
  }

  pad = doc.createElementNS(XHTML_NS, "div");
  pad.style.cssText = "break-before: column; height: 1px;";
  root.append(pad);

  applyStyle();
  doc.addEventListener("click", onClick);
  watchGestures(doc);
  doc.addEventListener("load", reflow, true);
  doc.fonts.addEventListener("loadingdone", reflow);
  await waitAssets(doc, [fonts, before, ...after]);
}

function stylesheet(doc, name) {
  const link = doc.createElementNS(XHTML_NS, "link");
  link.rel = "stylesheet";
  link.href = READIUM_BASE + name;
  return link;
}

// 等样式表、图片、字体加载完再测量
function waitAssets(doc, links) {
  const pending = [...links, ...[...doc.images].filter((img) => !img.complete)]
    .map((el) => new Promise((resolve) => {
      el.addEventListener("load", resolve, { once: true });
      el.addEventListener("error", resolve, { once: true });
    }));
  const ready = Promise.all(pending).then(() => doc.fonts.ready);
  const timeout = new Promise((resolve) => setTimeout(resolve, ASSET_TIMEOUT_MS));
  return Promise.race([ready, timeout]);
}

function columnCount() {
  const scale = parseFloat(state.style["--USER__fontSize"] || "100") / 100;
  const fontPx = 16 * scale;
  // --RS__pageGutter 已按字号缩放预先除过（会被 body 的 zoom 放大回来），乘回 scale 才是屏幕上的实际留白
  const gutter = parseFloat(state.style["--RS__pageGutter"]) * scale;
  const columnEm = (frame.clientWidth / 2 - 2 * gutter) / fontPx;
  return columnEm >= MIN_COLUMN_EM ? 2 : 1;
}

// 把用户设置和版面变量写到外壳页和章节文档的 :root；
// 章节只认 --USER__* / --RS__* / --reader-highlight / --reader-note，外壳页只认 --reader-bg / --reader-pattern，互不干扰
function applyStyle() {
  state.columns = columnCount();
  const vars = { ...LAYOUT_VARS, ...state.style, "--USER__colCount": String(state.columns) };
  for (const root of [document.documentElement, doc?.documentElement]) {
    if (!root) continue;
    for (const [name, value] of Object.entries(vars)) root.style.setProperty(name, value);
  }
}

// ---------- 分页 ----------

// 一屏宽度即翻页步长（ReadiumCSS 列间距为 0，页边距在 body 的 padding 里）
function stride() {
  return frame.contentWindow.innerWidth;
}

// 双栏时总栏数若为奇数，最后一屏只有半屏宽，浏览器会把滚动夹在半屏处；
// 此时显示补白列凑成整屏
function measure() {
  pad.style.display = "none";
  const columns = Math.round(doc.scrollingElement.scrollWidth * state.columns / stride());
  pad.style.display = columns % state.columns ? "" : "none";
  state.spreadCount = Math.max(1, Math.ceil(columns / state.columns));
}

function scrollToSpread(page) {
  state.spread = Math.min(Math.max(page, 0), state.spreadCount - 1);
  frame.contentWindow.scrollTo(state.spread * stride(), 0);
}

// 翻页落位：滚动 + 刷新锚点 + 上报进度
function settle(page, offset = null) {
  scrollToSpread(page);
  state.range = pageRange();
  state.offset = offset ?? state.range?.start ?? -1;
  report();
}

function isPosition(at) {
  return at !== null && typeof at === "object";
}

// 把 at（页码、锚点或位置对象）转成具体页码
function locate(at) {
  if (typeof at === "number") return at < 0 ? state.spreadCount + at : at;

  if (isPosition(at)) {
    const spread = spreadAt(at.offset);
    return spread >= 0 ? spread : Math.round((at.ratio || 0) * (state.spreadCount - 1));
  }

  const rect = findAnchor(at)?.getClientRects()[0];
  return rect ? spreadOfRect(rect) : 0;
}

function findAnchor(anchor) {
  const id = CSS.escape(anchor);
  return doc.querySelector(`#${id}, a[name="${id}"]`);
}

// ---------- 阅读坐标 ----------

// 阅读位置、目录锚点、书签和高亮共用一套坐标：把章节 body 摊平成单位流，
// 文本节点按 UTF-16 长度计，媒体元素各计 1 且不深入其子节点。
// ReadiumCSS 把媒体限制在一栏以内且不许跨栏（ReadiumCSS-before.css 的 img, svg|svg, video），
// 每个媒体都完整落在某一页，整页插图因此也能被定位。
// 这是存储数据依赖的契约：标注存下后改动 MEDIA 会让已有偏移整体错位。
// Swift 侧 EpubBook.textStats 按本定义近似计数，仅用于百分比和字数。
const MEDIA = new Set(["img", "svg", "video"]);

function* units() {
  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
    acceptNode: (node) => node.nodeType === Node.TEXT_NODE || MEDIA.has(node.localName)
      ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP,
  });
  let start = 0;
  while (walker.nextNode()) {
    const node = walker.currentNode;
    const text = node.nodeType === Node.TEXT_NODE;
    const length = text ? node.length : 1;
    yield { node, start, length, text };
    start += length;
    if (!text) {
      // 跳过媒体内部（svg 的 <text>、video 的后备内容）：把游标移到其最后一个后代，下一步即离开子树
      let last = node;
      while (last.lastChild) last = last.lastChild;
      walker.currentNode = last;
    }
  }
}

// 本章总单位数
function contentLength() {
  let total = 0;
  for (const unit of units()) total += unit.length;
  return total;
}

// 节点起点在坐标中的位置，即排在它之前的单位数（不含其后代）
function offsetBefore(target) {
  let end = 0;
  for (const { node, start, length } of units()) {
    if (node === target || target.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING) return start;
    end = start + length;
  }
  return end;
}

// DOM 边界点 → 坐标：排在边界点之前的单位数，边界点落在文本单位内时加上字符位置。
// 落在媒体内部（如 svg 的 <text>）的边界点归到该媒体之后
function offsetAt(container, index) {
  const point = doc.createRange();
  point.setStart(container, index);
  let end = 0;
  for (const { node, start, length } of units()) {
    if (node === container) return start + index;
    if (point.comparePoint(node, 0) > 0) return start;
    end = start + length;
  }
  return end;
}

function anchorOffsets(ids) {
  const offsets = {};
  for (const id of ids) {
    const el = findAnchor(id);
    if (!el || el === doc.body || !doc.body.contains(el)) continue;
    offsets[id] = offsetBefore(el);
  }
  return offsets;
}

// 重叠加深：同一 Highlight 内的 Range 重叠时只画一层，所以按重叠深度分层注册，
// 第 k 层覆盖至少 k+1 条高亮重叠的区域，各层同一半透明色叠加，越深越浓；超过层数的深度不再加深
const HIGHLIGHT_LAYERS = ["rede-highlight-1", "rede-highlight-2"];
// 带笔记的高亮额外加入此层，画虚线下划线
const NOTE_LAYER = "rede-note";

// 本章高亮整体替换。Highlight 对象在 prepare 里按章注册一次，这里只清空再加入：
// WebKit 在 clear/add 时重绘被移除和新加入的 Range，而整体替换注册表条目只重绘新对象，删掉的高亮会残留到下次重绘。
// Range 是活的 DOM 对象，换字号、缩放后随重排自动跟随，无需重算
function paintHighlights() {
  const spans = state.annotations.filter((a) => a.kind === "highlight" && a.chapter === state.chapterId);
  const layers = depthLayers(spans);
  const ranges = rangesOf([...spans, ...layers.flat()]);
  highlights = spans.map((s, i) => ({ id: s.id, start: s.start, end: s.end, range: ranges[i] }));
  let next = spans.length;
  layers.forEach((intervals, k) => {
    const highlight = doc.defaultView.CSS.highlights.get(HIGHLIGHT_LAYERS[k]);
    highlight.clear();
    for (let i = 0; i < intervals.length; i++) highlight.add(ranges[next++]);
  });
  const notes = doc.defaultView.CSS.highlights.get(NOTE_LAYER);
  notes.clear();
  spans.forEach((s, i) => { if (s.note) notes.add(ranges[i]); });
}

// 章节视口矩形 → 外壳页坐标（即 WebView 坐标）
function shellRect(rect) {
  const origin = frame.getBoundingClientRect();
  return { x: rect.left + origin.left, y: rect.top + origin.top, width: rect.width, height: rect.height };
}

// 按重叠深度分层：第 k 层是至少 k+1 条高亮重叠的区间，层内互不相交。
// 扫描端点，同一位置先结束后开始，首尾相接的高亮不算重叠
function depthLayers(spans) {
  const events = spans.flatMap((s) => [[s.start, 1], [s.end, -1]])
    .sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const layers = HIGHLIGHT_LAYERS.map(() => []);
  let depth = 0;
  for (const [at, delta] of events) {
    if (delta > 0) {
      if (depth < layers.length) layers[depth].push({ start: at, end: at });
      depth++;
    } else {
      depth--;
      if (depth < layers.length) layers[depth].at(-1).end = at;
    }
  }
  return layers.map((intervals) => intervals.filter((s) => s.start < s.end));
}

// 章节视口坐标 (x, y) 处的高亮及其被点中的那一行矩形；重叠时取最短的一条（最具体）
function highlightAt(x, y) {
  let hit = null;
  for (const h of highlights) {
    const rect = [...h.range.getClientRects()]
      .find((r) => x >= r.left && x <= r.right && y >= r.top && y <= r.bottom);
    if (rect && (!hit || h.end - h.start < hit.end - hit.start)) hit = { ...h, rect };
  }
  return hit;
}

// 坐标区间 [start, end) → DOM Range
function rangesOf(spans) {
  const points = boundaries(spans.flatMap((s) => [s.start, s.end]));
  return spans.map((s) => {
    const range = doc.createRange();
    range.setStart(...points.get(s.start));
    range.setEnd(...points.get(s.end));
    return range;
  });
}

// 一次遍历把一组偏移转成 DOM 边界点：落在文本单位内取字符位置，落在媒体单位上取其前方，越过章末取 body 末尾。
// 恰好等于某单位起点的偏移落在该单位之前，区间终点因此不含该单位
function boundaries(offsets) {
  const sorted = [...new Set(offsets)].sort((a, b) => a - b);
  const points = new Map();
  let i = 0;
  for (const { node, start, length, text } of units()) {
    for (; i < sorted.length && sorted[i] < start + length; i++) {
      points.set(sorted[i], text
        ? [node, sorted[i] - start]
        : [node.parentNode, [...node.parentNode.childNodes].indexOf(node)]);
    }
    if (i === sorted.length) break;
  }
  for (; i < sorted.length; i++) points.set(sorted[i], [doc.body, doc.body.childNodes.length]);
  return points;
}

// 矩形 → 页码（矩形是章节视口坐标，加上横向滚动量得到文档坐标）
function spreadOfRect(rect) {
  const offset = rect.left + frame.contentWindow.scrollX;
  return Math.floor((offset + 1) / stride());
}

// 偏移 → 页码：不可见的单位（折叠的空白、隐藏元素）沿用其后第一个可见单位的页码，
// 保证页码随偏移量单调非递减；其后再无可见单位返回 -1
function spreadAt(offset) {
  if (offset < 0) return -1;
  const range = doc.createRange();
  for (const { node, start, length, text } of units()) {
    if (start + length <= offset) continue;
    if (!text) {
      const rect = node.getClientRects()[0];
      if (rect) return spreadOfRect(rect);
      continue;
    }
    range.selectNodeContents(node);
    if (range.getClientRects().length === 0) continue;  // 整个节点不渲染，直接跳过
    for (let i = Math.max(offset - start, 0); i < length; i++) {
      range.setStart(node, i);
      range.setEnd(node, i + 1);
      const rect = range.getClientRects()[0];
      if (rect) return spreadOfRect(rect);
    }
  }
  return -1;
}

// 二分查找第 spread 页的第一个单位（spreadAt 单调，-1 只出现在章末）
function spreadStart(spread) {
  let lo = 0, hi = state.total - 1, found = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    const s = spreadAt(mid);
    if (s >= 0 && s < spread) lo = mid + 1;
    else { if (s >= 0) found = mid; hi = mid - 1; }
  }
  return found;
}

// 当前页的坐标区间 [start, end)；页上没有任何可见单位时为 null
function pageRange() {
  const start = spreadStart(state.spread);
  if (start < 0 || spreadAt(start) !== state.spread) return null;
  const next = state.spread + 1 < state.spreadCount ? spreadStart(state.spread + 1) : -1;
  return { start, end: next < 0 ? state.total : next };
}

function progress() {
  return {
    chapter: state.chapterId,
    offset: state.offset,
    total: state.total,
    ratio: state.spreadCount > 1 ? state.spread / (state.spreadCount - 1) : 0,
    page: state.spread,
    pageCount: state.spreadCount,
    anchors: state.anchors,
    start: state.range?.start ?? null,
    excerpt: state.range ? excerpt(state.range.start, EXCERPT_LENGTH) : "",
    bookmarks: pageBookmarks(),
  };
}

const EXCERPT_LENGTH = 60;

// 本页上的书签 id
function pageBookmarks() {
  const range = state.range;
  if (!range) return [];
  return state.annotations
    .filter((b) => b.kind === "bookmark" && b.chapter === state.chapterId
      && b.start >= range.start && b.start < range.end)
    .map((b) => b.id);
}

// 从 start 起 length 个单位内的文字，空白折叠；媒体不产出文字
function excerpt(start, length) {
  const end = start + length;
  let text = "";
  for (const unit of units()) {
    if (unit.start >= end) break;
    if (!unit.text || unit.start + unit.length <= start) continue;
    text += unit.node.data.slice(Math.max(start - unit.start, 0), end - unit.start);
  }
  return text.replace(/\s+/g, " ").trim();
}

// 上报进度给 Swift
function report() {
  const info = progress();
  document.documentElement.classList.toggle("bookmarked", info.bookmarks.length > 0);
  window.webkit?.messageHandlers?.reading_progress?.postMessage(info);
}

// 窗口缩放、改设置、图片加载后重新测量，回到锚点所在页并上报新页码；锚点本身不重算，所以反复缩放不会累积漂移
function reflow() {
  applyStyle();
  if (!doc || frame.classList.contains("loading")) return;
  measure();
  const spread = spreadAt(state.offset);
  scrollToSpread(spread >= 0 ? spread : state.spread);
  state.range = pageRange();
  report();
}

// 拦截章节内的链接，站内链接转成章节跳转；站外链接放行，交给原生导航策略
function onClick(event) {
  const link = event.target.closest("a[href]");
  if (!link) return;

  let url, path, anchor;
  try {
    url = new URL(link.getAttribute("href"), doc.baseURI);
    path = decodeURIComponent(url.pathname.slice(1));
    anchor = decodeURIComponent(url.hash.slice(1));
  } catch {
    event.preventDefault();
    return;
  }
  if (url.protocol !== ROOT.protocol || url.host !== ROOT.host) return;

  event.preventDefault();
  const chapter = state.spinePaths.indexOf(path);
  if (chapter >= 0) reader.jump(chapter, anchor);
}

// ---------- 手势 ----------

// 外壳页和每个章节文档各自绑定：iframe 里的事件不会冒泡到外壳页，上下页边距上的点击落在外壳页
function watchGestures(target) {
  target.addEventListener("click", onTap);
  target.addEventListener("contextmenu", onContextMenu);
  target.addEventListener("selectionchange", () => reportSelection(target));
  // 换章后旧文档里的选区随之消失，不会再触发 selectionchange
  reportSelection(target);
}

// 有选区时拖动是在调整选区，原生侧据此不把下滑当作关闭
function reportSelection(doc) {
  window.webkit?.messageHandlers?.gesture?.postMessage({
    type: "selection",
    active: !doc.getSelection().isCollapsed,
  });
}

// 原生侧在右键菜单打开时同步补充菜单项，所以在 contextmenu 事件里先上报命中的高亮和选区状态。
// 事件派发在菜单交给原生侧之前，两条消息走同一 IPC 通道，菜单打开时原生侧已收到本消息；
// 右键未选中的词时 WebKit 在派发前已选中该词，这里读到的选区状态也比 selectionchange 及时
function onContextMenu(event) {
  const hit = event.view === window ? null : highlightAt(event.clientX, event.clientY);
  window.webkit?.messageHandlers?.gesture?.postMessage({
    type: "context",
    highlight: hit ? { id: hit.id, rect: shellRect(hit.rect) } : null,
    selecting: !event.view.getSelection().isCollapsed,
  });
}

// 点在链接上交给 onClick 和原生导航；有选区时这次点击是在取消选中，都不上报。
// 点在高亮上上报高亮及其行矩形（外壳页坐标，即 WebView 坐标），不再当作翻页点击
function onTap(event) {
  if (event.target.closest("a[href]") || !event.view.getSelection().isCollapsed) return;
  const inChapter = event.view !== window;
  const origin = inChapter ? frame.getBoundingClientRect() : { left: 0, top: 0 };
  const hit = inChapter ? highlightAt(event.clientX, event.clientY) : null;
  if (hit) {
    window.webkit?.messageHandlers?.gesture?.postMessage({ type: "highlight", id: hit.id, rect: shellRect(hit.rect) });
    return;
  }
  window.webkit?.messageHandlers?.gesture?.postMessage({
    type: "tap",
    x: (event.clientX + origin.left) / window.innerWidth,
  });
}
