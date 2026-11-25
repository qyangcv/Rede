"use strict";

// 每个章节作为完整文档加载进 iframe，样式层交给 ReadiumCSS（cjk-horizontal）：
//   ReadiumCSS-before → 书自带样式 → [ReadiumCSS-default，仅当书没有样式] → ReadiumCSS-after
// 分页由 ReadiumCSS 在章节 :root 上分栏，本脚本只负责导航、锚点和进度。
// 手势只做识别并上报 Swift，是否翻页由各平台决定。

const XHTML_NS = "http://www.w3.org/1999/xhtml";
const READIUM_BASE = "rede://app/";
const ASSET_TIMEOUT_MS = 5000;
const MIN_COLUMN_EM = 20
const COLUMN_GAP_RATIO = 0.05;
const COLUMN_GAP_MIN_EM = 3;

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
  offset: 0,   // 当前页首个单位在本章坐标中的偏移量（阅读锚点），见 offsets.js
  total: 0,    // 本章总单位数
  tocAnchors: [],
  anchors: {},
  range: null,     // 当前页的坐标区间 {start, end}，空白页为 null
  annotations: [], // 本书标注 [{id, kind, chapter, start, end, note}]，note 为是否带笔记
};

let doc = null;  // 当前章节文档
let pad = null;  // 当前章节的补白列，见 measure()
let selectionBounds = null;  // 当前屏的 DOM Range，有选区时才计算
let highlights = [];  // 本章已绘制的高亮 [{id, start, end, range}]，供点击命中检测
let hadSelectionOnMouseDown = false;  // 按下鼠标前是否已有选区，用于区分取消选区和直接点击/右键高亮
let activeHighlightId = null;  // 当前激活（左键/双击/右键）的高亮 id，由独立的 CSS Highlight 层绘制
let highlightTapTimer = null;  // 桌面端单击高亮延迟上报，避免双击时先弹出面板再撤回
let lastPointerType = "";

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

  clearActiveHighlight() {
    setActiveHighlight(null);
  },

  // 取出章节里的选区并清除：返回 {chapter, start, end, text}；没有选区或选区不含任何单位时返回 null
  takeSelection() {
    const selection = pageSelection();
    if (!selection || selection.isCollapsed) return null;
    const range = selection.getRangeAt(0);
    const start = offsetAt(doc, range.startContainer, range.startOffset);
    const end = offsetAt(doc, range.endContainer, range.endOffset);
    const lastRect = Array.from(range.getClientRects()).findLast((rect) =>
      hasArea(rect) && spreadOfRect(rect) === state.spread);
    selection.removeAllRanges();
    if (start >= end || !lastRect) return null;
    // 原生侧把笔记编辑框指向选区末行
    const rect = shellRect(lastRect);
    return {
      chapter: state.chapterId, start, end, text: excerpt(doc, start, end - start), rect, anchors: state.anchors,
      merge: crossPageMerge(start, end),
    };
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

  showSearchHit(chapter, start, end) {
    return goto(chapter, { offset: start }, { start, end });
  },

  clearSearchHit() {
    activeSearchHit = null;
    doc?.defaultView?.CSS.highlights.get(SEARCH_LAYER)?.clear();
  },

  setStyle(vars) {
    Object.assign(state.style, vars);
    reflow();
  },
};

// 翻一页，到章首章尾时载入相邻章节；返回是否落位
async function turn(delta) {
  reader.clearSearchHit();
  const spread = state.spread + delta;
  if (spread >= 0 && spread < state.spreadCount) {
    settle(spread);
    return true;
  }
  return goto(state.chapterId + delta, delta > 0 ? 0 : -1);
}

// 导航，at 为数字（页码）、字符串（锚点）或位置对象；返回是否落位（被后续导航打断时为 false）
async function goto(chapter, at, searchHit = null) {
  const path = state.spinePaths[chapter];
  if (path === undefined) return false;
  reader.clearSearchHit();
  activeSearchHit = searchHit;
  const token = ++state.navId;

  if (chapter !== state.chapterId || frame.classList.contains("loading")) {
    frame.classList.add("loading");
    const loaded = await load(new URL(path.split("/").map(encodeURIComponent).join("/"), ROOT));
    if (token !== state.navId) return false;

    doc = loaded;
    state.chapterId = chapter;
    await prepare(doc);
    if (token !== state.navId) return false;
    state.total = contentLength(doc);
    state.anchors = anchorOffsets(doc, state.tocAnchors[chapter] ?? []);
    paintHighlights();
  }

  measure();
  // 从保存的位置恢复时沿用原锚点，不重新测量，避免多次恢复逐页回退
  if (activeSearchHit) {
    const [range] = rangesOf(doc, [activeSearchHit]);
    doc.defaultView.CSS.highlights.get(SEARCH_LAYER).add(range);
  }
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
    ::highlight(${ACTIVE_HIGHLIGHT_LAYER}) { background-color: var(--reader-highlight-active); }
    ::highlight(${NOTE_LAYER}) { text-decoration: underline dashed 1.5px var(--reader-note); }
    ::highlight(${SEARCH_LAYER}) { background-color: #ffd457; color: #241b00; }
    :root.over-highlight { cursor: default; }
    @layer rede {
      body {
        text-align: justify;
      }
      img, svg, video, object, embed, iframe, canvas, input[type="image"] {
        max-width: min(100%, var(--rede-media-width)) !important;
        max-height: var(--rede-media-height) !important;
      }
    }`;
  head.prepend(fonts, before);
  head.append(...after, marks);
  for (const name of [...HIGHLIGHT_LAYERS, ACTIVE_HIGHLIGHT_LAYER, NOTE_LAYER, SEARCH_LAYER]) {
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
  liftBodyBackground(doc);
}

// 按 CSS 规范，根元素没有背景时 body 背景提升到画布、按根元素盒子（即一屏）定位，body 自身不再绘制。
// 但根元素分栏后 body 的渲染父节点变成分栏 flow，WebKit 不再跳过 body 自身的背景，于是画两份：
// 画布上一份，body 盒子里再按栏切成碎片一份。这里手动把背景图搬到根元素，只留画布那份。
// 背景色不搬：根元素背景色须保持透明，透出外壳页的背景
const BACKGROUND_PROPS = ["image", "position", "size", "repeat", "origin", "clip", "attachment"]
  .map((name) => `background-${name}`);

function liftBodyBackground(doc) {
  const root = doc.documentElement;
  const view = doc.defaultView;
  const body = view.getComputedStyle(doc.body);
  if (view.getComputedStyle(root).backgroundImage !== "none" || body.backgroundImage === "none") return;
  for (const name of BACKGROUND_PROPS) root.style.setProperty(name, body.getPropertyValue(name));
  doc.body.style.setProperty("background-image", "none", "important");
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

// 字号比例，即 ReadiumCSS 加在 body 上的 zoom
function fontScale() {
  return parseFloat(state.style["--USER__fontSize"] || "100") / 100;
}

function columnGapPx(columns) {
  if (columns < 2) return 0;
  return Math.max(frame.clientWidth * COLUMN_GAP_RATIO, COLUMN_GAP_MIN_EM * 16 * fontScale());
}

function columnCount() {
  const columnEm = (frame.clientWidth - columnGapPx(2)) / 2 / (16 * fontScale());
  return columnEm >= MIN_COLUMN_EM ? 2 : 1;
}

// 嵌入内容的尺寸上限：一栏的内容区，高度留出 5% 给图片所在行的行高。
// 约束写在 prepare 注入的 @layer rede 里，分层的 !important 压过书里所有不分层的声明（含书自己的 !important），
// 且只设上限：放得下一页的元素不受任何影响。
// 上限以页面而非父容器为参照，父容器被书撑得比一栏还宽时图片也不会越界；
// 元素在 body 内会被 zoom 放大，所以预先除以字号比例
const MEDIA_HEIGHT_RATIO = 0.95;

function mediaLimits() {
  const scale = fontScale();
  const width = (frame.clientWidth - (state.columns - 1) * columnGapPx(state.columns)) / state.columns;
  const height = frame.clientHeight * MEDIA_HEIGHT_RATIO;
  return { "--rede-media-width": `${width / scale}px`, "--rede-media-height": `${height / scale}px` };
}

// 把用户设置和版面变量写到外壳页和章节文档的 :root；
// 章节只认 --USER__* / --RS__* / --rede-media-* / --reader-highlight / --reader-note，外壳页只认 --reader-bg，互不干扰
function applyStyle() {
  state.columns = columnCount();
  const vars = {
    ...LAYOUT_VARS,
    ...state.style,
    "--USER__colCount": String(state.columns),
    "--RS__colGap": `${columnGapPx(state.columns)}px`,
    ...mediaLimits(),
  };
  for (const root of [document.documentElement, doc?.documentElement]) {
    if (!root) continue;
    for (const [name, value] of Object.entries(vars)) root.style.setProperty(name, value);
  }
}

// ---------- 分页 ----------

// 翻页步长 = 一屏宽 + 一个栏间距：每栏后面都跟一个 column-gap，下一屏的首栏从 (栏宽 + 间距) × 栏数 处开始
function stride() {
  return frame.contentWindow.innerWidth + columnGapPx(state.columns);
}

// 双栏时总栏数若为奇数，最后一屏只有半屏宽，浏览器会把滚动夹在半屏处；
// 此时显示补白列凑成整屏
function measure() {
  pad.style.display = "none";
  const gap = columnGapPx(state.columns);
  const columns = Math.round((doc.scrollingElement.scrollWidth + gap) * state.columns / stride());
  pad.style.display = columns % state.columns ? "" : "none";
  state.spreadCount = Math.max(1, Math.ceil(columns / state.columns));
}

function scrollToSpread(page) {
  state.spread = Math.min(Math.max(page, 0), state.spreadCount - 1);
  frame.contentWindow.scrollTo(state.spread * stride(), 0);
}

// 翻页落位：滚动 + 刷新锚点 + 上报进度
function settle(page, offset = null) {
  const previousSpread = state.spread;
  scrollToSpread(page);
  updatePageRange();
  if (state.spread !== previousSpread) {
    cancelHighlightTap();
    clearHoverHighlight();
    setActiveHighlight(null);
    doc.getSelection().removeAllRanges();
  } else {
    pageSelection();
  }
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

  const rect = findAnchor(doc, at)?.getClientRects()[0];
  return rect ? spreadOfRect(rect) : 0;
}

// 重叠加深：同一 Highlight 内的 Range 重叠时只画一层，所以按重叠深度分层注册，
// 第 k 层覆盖至少 k+1 条高亮重叠的区域，各层同一半透明色叠加，越深越浓；超过层数的深度不再加深
const HIGHLIGHT_LAYERS = ["rede-highlight-1", "rede-highlight-2"];
const ACTIVE_HIGHLIGHT_LAYER = "rede-highlight-active";
// 带笔记的高亮额外加入此层，画虚线下划线
const NOTE_LAYER = "rede-note";
const SEARCH_LAYER = "rede-search";
let activeSearchHit = null;

// 本章高亮整体替换。Highlight 对象在 prepare 里按章注册一次，这里只清空再加入：
// WebKit 在 clear/add 时重绘被移除和新加入的 Range，而整体替换注册表条目只重绘新对象，删掉的高亮会残留到下次重绘。
// Range 是活的 DOM 对象，换字号、缩放后随重排自动跟随，无需重算
function paintHighlights() {
  const spans = state.annotations.filter((a) => a.kind === "highlight" && a.chapter === state.chapterId);
  const layers = depthLayers(spans);
  const ranges = rangesOf(doc, [...spans, ...layers.flat()]);
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
  paintActiveHighlight();
  if (highlights.length === 0) clearHoverHighlight();
}

function paintActiveHighlight() {
  const layer = doc?.defaultView?.CSS.highlights.get(ACTIVE_HIGHLIGHT_LAYER);
  if (!layer) return;
  layer.clear();
  if (!activeHighlightId) return;
  const hit = highlights.find((h) => h.id === activeHighlightId);
  if (hit) {
    layer.add(hit.range);
  } else {
    activeHighlightId = null;
    window.webkit?.messageHandlers?.gesture?.postMessage({ type: "activeHighlight", id: null });
  }
}

function setActiveHighlight(id) {
  if (activeHighlightId === id) return;
  activeHighlightId = id;
  paintActiveHighlight();
  window.webkit?.messageHandlers?.gesture?.postMessage({ type: "activeHighlight", id: activeHighlightId });
}

function refreshHighlights(chapter) {
  for (const name of [...HIGHLIGHT_LAYERS, ACTIVE_HIGHLIGHT_LAYER, NOTE_LAYER, SEARCH_LAYER]) {
    const highlight = chapter.defaultView.CSS.highlights.get(name);
    const ranges = [...highlight];
    highlight.clear();
    for (const range of ranges) highlight.add(range);
  }
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

const HIGHLIGHT_HIT_SLOP = 1.5;

function columnOfRect(rect) {
  if (state.columns < 2) return 0;
  return rect.left + rect.width / 2 < frame.contentWindow.innerWidth / 2 ? 0 : 1;
}

// 只收集文本节点子区间的矩形，避免跨段 Range 混入块级容器矩形
function textRects(range) {
  if (range.startContainer === range.endContainer && range.startContainer.nodeType === Node.TEXT_NODE) {
    return [...range.getClientRects()];
  }
  const rects = [];
  const sub = doc.createRange();
  const root = range.commonAncestorContainer;
  const walker = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let node = root.nodeType === Node.TEXT_NODE ? root : walker.nextNode();
  while (node) {
    if (range.intersectsNode(node)) {
      const start = node === range.startContainer ? range.startOffset : 0;
      const end = node === range.endContainer ? range.endOffset : node.length;
      if (start < end) {
        sub.setStart(node, start);
        sub.setEnd(node, end);
        rects.push(...sub.getClientRects());
      }
    }
    node = walker.nextNode();
  }
  return rects;
}

// 合并同一栏、同一行的碎片矩形，消除跨节点/两端对齐/亚像素导致的命中缝隙
function lineRects(range) {
  const merged = [];
  for (const r of textRects(range)) {
    if (!hasArea(r)) continue;
    const col = columnOfRect(r);
    const line = merged.find((m) => m.col === col && Math.min(m.bottom, r.bottom) > Math.max(m.top, r.top));
    if (line) {
      line.left = Math.min(line.left, r.left);
      line.right = Math.max(line.right, r.right);
      line.top = Math.min(line.top, r.top);
      line.bottom = Math.max(line.bottom, r.bottom);
    } else {
      merged.push({ col, left: r.left, right: r.right, top: r.top, bottom: r.bottom });
    }
  }
  return merged;
}

// 章节视口坐标 (x, y) 处的高亮及其被点中的那一行矩形；重叠时取最短的一条（最具体）
function highlightAt(x, y) {
  let hit = null;
  for (const h of highlights) {
    const rect = lineRects(h.range).find((r) =>
      x >= r.left - HIGHLIGHT_HIT_SLOP && x <= r.right + HIGHLIGHT_HIT_SLOP
      && y >= r.top - HIGHLIGHT_HIT_SLOP && y <= r.bottom + HIGHLIGHT_HIT_SLOP);
    if (rect && (!hit || h.end - h.start < hit.end - hit.start)) {
      hit = { ...h, rect: { left: rect.left, top: rect.top, width: rect.right - rect.left, height: rect.bottom - rect.top } };
    }
  }
  return hit;
}

// 第二次标注时，按当前排版检查最近的前后两条高亮；同一屏的两栏不算跨页。
function crossPageMerge(start, end) {
  let previous = null;
  let next = null;
  for (const mark of highlights) {
    if (mark.end <= start && (!previous || mark.end > previous.end)) previous = mark;
    if (mark.start >= end && (!next || mark.start < next.start)) next = mark;
  }

  for (const [mark, direction] of [[previous, -1], [next, 1]]) {
    if (!mark) continue;
    const rects = Array.from(mark.range.getClientRects());
    const edge = direction < 0 ? rects.findLast(hasArea) : rects.find(hasArea);
    if (!edge || spreadOfRect(edge) !== state.spread + direction) continue;

    const gapStart = direction < 0 ? mark.end : end;
    const gapEnd = direction < 0 ? start : mark.start;
    if (!gapIsCollapsedWhitespace(gapStart, gapEnd)) continue;

    const mergedStart = Math.min(start, mark.start);
    const mergedEnd = Math.max(end, mark.end);
    return { id: mark.id, start: mark.start, end: mark.end, text: excerpt(doc, mergedStart, mergedEnd - mergedStart) };
  }
  return null;
}

// 只允许跨过排版折叠的 HTML 空白，保留标点、可见空格和媒体形成的间隔。
function gapIsCollapsedWhitespace(start, end) {
  if (start === end) return true;
  const range = doc.createRange();
  for (const { node, start: offset, length, text } of unitsFrom(doc, start)) {
    if (offset >= end) break;
    if (!text) return false;

    const from = Math.max(0, start - offset);
    const to = Math.min(length, end - offset);
    if (/[^ \t\r\n\f]/.test(node.data.slice(from, to))) return false;
    range.setStart(node, from);
    range.setEnd(node, to);
    if (Array.from(range.getClientRects()).some(hasArea)) return false;
  }
  return true;
}

function hasArea(rect) {
  return rect.width > 0 && rect.height > 0;
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
  for (const { node, start, length, text } of unitsFrom(doc, offset)) {
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

function updatePageRange() {
  state.range = pageRange();
  selectionBounds = null;
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
    excerpt: state.range ? excerpt(doc, state.range.start, EXCERPT_LENGTH) : "",
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
  updatePageRange();
  pageSelection();
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

// 约束原生选区而非只截断标注偏移，让拖选、复制和标注使用相同范围。
function pageSelection() {
  if (!doc || frame.classList.contains("loading")) return null;
  const selection = doc.getSelection();
  if (selection.isCollapsed) return selection;

  if (!state.range) {
    selection.removeAllRanges();
    return selection;
  }

  const bounds = selectionBounds ??= rangesOf(doc, [state.range])[0];
  const { anchorNode, anchorOffset, focusNode, focusOffset } = selection;
  const anchorSide = bounds.comparePoint(anchorNode, anchorOffset);
  const focusSide = bounds.comparePoint(focusNode, focusOffset);
  if (anchorSide === 0 && focusSide === 0) return selection;

  if (anchorSide === focusSide) {
    selection.removeAllRanges();
  } else {
    const point = (side, node, offset) => {
      if (side < 0) return [bounds.startContainer, bounds.startOffset];
      if (side > 0) return [bounds.endContainer, bounds.endOffset];
      return [node, offset];
    };
    selection.setBaseAndExtent(...point(anchorSide, anchorNode, anchorOffset),
                               ...point(focusSide, focusNode, focusOffset));
  }
  return selection;
}

// 外壳页和每个章节文档各自绑定：iframe 里的事件不会冒泡到外壳页，上下页边距上的点击落在外壳页
function watchGestures(target) {
  target.addEventListener("click", onTap);
  target.addEventListener("contextmenu", onContextMenu);
  if (target !== document) {
    target.addEventListener("pointerdown", (event) => { lastPointerType = event.pointerType; });
    target.addEventListener("mousedown", onMouseDown);
    target.addEventListener("pointermove", onPointerMove);
    target.addEventListener("pointerleave", clearHoverHighlight);
  }
  target.addEventListener("selectionchange", () => {
    if (target !== document && target !== doc) return;
    if (target === doc) {
      const selection = pageSelection();
      if (selection && !selection.isCollapsed) {
        cancelHighlightTap();
        setActiveHighlight(null);
      }
    }
    reportSelection(target);
    if (target !== document) refreshHighlights(target);
  });
  // 换章后旧文档里的选区随之消失，不会再触发 selectionchange
  if (target !== document) {
    cancelHighlightTap();
    setActiveHighlight(null);
  }
  reportSelection(target);
}

const HIGHLIGHT_TAP_DELAY_MS = 240;

function cancelHighlightTap() {
  if (highlightTapTimer !== null) {
    clearTimeout(highlightTapTimer);
    highlightTapTimer = null;
  }
}

function clearHoverHighlight() {
  doc?.documentElement?.classList.remove("over-highlight");
}

function onPointerMove(event) {
  if (event.pointerType === "touch") return;
  const over = highlights.length > 0 && event.buttons === 0
    && !event.target.closest("a[href]")
    && Boolean(highlightAt(event.clientX, event.clientY));
  doc.documentElement.classList.toggle("over-highlight", over);
}

function onMouseDown(event) {
  cancelHighlightTap();
  hadSelectionOnMouseDown = !doc.getSelection().isCollapsed;
  if (event.button !== 0) return;
  if (event.detail === 2 && !event.target.closest("a[href]")) {
    const hit = highlightAt(event.clientX, event.clientY);
    if (hit) {
      event.preventDefault();
      doc.getSelection().removeAllRanges();
      setActiveHighlight(hit.id);
      return;
    }
  }
  if (activeHighlightId) setActiveHighlight(null);
}

// 有选区时拖动是在调整选区，原生侧据此不把下滑当作关闭
function reportSelection(target) {
  const selection = target === doc ? pageSelection() : target.getSelection();
  window.webkit?.messageHandlers?.gesture?.postMessage({
    type: "selection",
    active: selection != null && !selection.isCollapsed,
  });
}

// 原生侧在右键菜单打开时同步补充菜单项，所以在 contextmenu 事件里先上报命中的高亮和选区状态。
// 事件派发在菜单交给原生侧之前，两条消息走同一 IPC 通道，菜单打开时原生侧已收到本消息；
// 右键未选中的高亮时清除 WebKit 自动选中的局部词，交由活跃高亮层绘制，原生侧直接拷贝完整高亮文本
function onContextMenu(event) {
  cancelHighlightTap();
  const hit = event.view === window ? null : highlightAt(event.clientX, event.clientY);
  const hadSelection = hadSelectionOnMouseDown;
  hadSelectionOnMouseDown = false;
  if (hit && !hadSelection) {
    doc.getSelection().removeAllRanges();
    setActiveHighlight(hit.id);
  } else if (!hit) {
    setActiveHighlight(null);
  }
  const selection = event.currentTarget === doc ? pageSelection() : event.view.getSelection();
  window.webkit?.messageHandlers?.gesture?.postMessage({
    type: "context",
    highlight: hit ? { id: hit.id, rect: shellRect(hit.rect) } : null,
    selecting: selection != null && !selection.isCollapsed,
  });
}

// 点在链接上交给 onClick 和原生导航；有选区时这次点击是在取消选中，都不上报。
// 点在高亮上上报高亮及其行矩形（外壳页坐标，即 WebView 坐标），不再当作翻页点击
function onTap(event) {
  const hadSelection = hadSelectionOnMouseDown;
  hadSelectionOnMouseDown = false;
  if (event.detail > 1 || hadSelection || event.target.closest("a[href]") || !event.view.getSelection().isCollapsed) return;
  const inChapter = event.view !== window;
  const origin = inChapter ? frame.getBoundingClientRect() : { left: 0, top: 0 };
  const hit = inChapter ? highlightAt(event.clientX, event.clientY) : null;
  if (hit) {
    const message = { type: "highlight", id: hit.id, rect: shellRect(hit.rect) };
    if (lastPointerType === "touch") {
      window.webkit?.messageHandlers?.gesture?.postMessage(message);
    } else {
      cancelHighlightTap();
      highlightTapTimer = setTimeout(() => {
        highlightTapTimer = null;
        setActiveHighlight(hit.id);
        window.webkit?.messageHandlers?.gesture?.postMessage(message);
      }, HIGHLIGHT_TAP_DELAY_MS);
    }
    return;
  }
  setActiveHighlight(null);
  window.webkit?.messageHandlers?.gesture?.postMessage({
    type: "tap",
    x: (event.clientX + origin.left) / window.innerWidth,
  });
}
