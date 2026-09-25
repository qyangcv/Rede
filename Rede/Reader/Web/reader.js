"use strict";

// 每个章节作为完整文档加载进 iframe，样式层交给 ReadiumCSS（cjk-horizontal）：
//   ReadiumCSS-before → 书自带样式 → [ReadiumCSS-default，仅当书没有样式] → ReadiumCSS-after
// 分页由 ReadiumCSS 在章节 :root 上分栏，本脚本只负责导航、锚点和进度。

const XHTML_NS = "http://www.w3.org/1999/xhtml";
const READIUM_BASE = "rede://app/";
const ASSET_TIMEOUT_MS = 5000;
const SPREAD_RATIO = 2 / 3;

// 版面相关的 ReadiumCSS 变量：
// - 左右页边距
// - 背景色设为 transparent：ReadiumCSS 以 !important 强制章节根元素的背景色，设为透明才能透出外壳页绘制的背景；
//   书内其他元素（含 body）的背景不受影响
const LAYOUT_VARS = {
  "--RS__pageGutter": "48px",
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
  offset: 0,   // 当前页首字符在本章文本流中的偏移量（阅读锚点）
  total: 0,    // 本章文本流总字符数
};

let doc = null;  // 当前章节文档
let pad = null;  // 当前章节的补白列，见 measure()

// Swift 调用接口

const reader = {
  // 入口：保存 paths、绑定事件、恢复到 start（null 则从头开始）
  open(paths, language, style = {}, start = null) {
    state.spinePaths = paths;
    state.language = language;
    state.style = style;
    applyStyle();
    window.addEventListener("resize", reflow);
    goto(start ? start.chapter : 0, start ?? 0);
  },

  next() {
    if (state.spread < state.spreadCount - 1) settle(state.spread + 1);
    else goto(state.chapterId + 1, 0);
  },

  prev() {
    if (state.spread > 0) settle(state.spread - 1);
    else goto(state.chapterId - 1, -1);
  },

  jump(chapter, anchor) {
    goto(chapter, anchor || 0);
  },

  setStyle(vars) {
    Object.assign(state.style, vars);
    reflow();
  },
};

// 导航，at 为数字（页码）、字符串（锚点）或位置对象
async function goto(chapter, at) {
  const path = state.spinePaths[chapter];
  if (path === undefined) return;
  const token = ++state.navId;

  if (chapter !== state.chapterId) {
    frame.classList.add("loading");
    const loaded = await load(new URL(path.split("/").map(encodeURIComponent).join("/"), ROOT));
    if (token !== state.navId) return;

    doc = loaded;
    state.chapterId = chapter;
    await prepare(doc);
    if (token !== state.navId) return;
    state.total = textLength();
  }

  measure();
  // 从保存的位置恢复时沿用原锚点，不重新测量，避免多次恢复逐页回退
  settle(locate(at), isPosition(at) ? at.offset : null);
  frame.classList.remove("loading");
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
  const before = stylesheet(doc, "ReadiumCSS-before.css");
  const after = [
    ...(unstyled ? [stylesheet(doc, "ReadiumCSS-default.css")] : []),
    stylesheet(doc, "ReadiumCSS-after.css"),
  ];
  head.prepend(before);
  head.append(...after);

  // 放在 body 之外，不进入文本流，不影响字符偏移
  pad = doc.createElementNS(XHTML_NS, "div");
  pad.style.cssText = "break-before: column; height: 1px;";
  root.append(pad);

  applyStyle();
  doc.addEventListener("click", onClick);
  doc.addEventListener("load", reflow, true);  // 图片等资源迟到时重新分页
  await waitAssets(doc, [before, ...after]);
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

// 把用户设置和版面变量写到外壳页和章节文档的 :root；
// 章节只认 --USER__* / --RS__*，外壳页只认 --reader-bg / --reader-pattern，互不干扰
function applyStyle() {
  state.columns = window.innerWidth > screen.availWidth * SPREAD_RATIO ? 2 : 1;
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
  state.offset = offset ?? anchorOffset();
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

  const id = CSS.escape(at);
  const el = doc.querySelector(`#${id}, a[name="${id}"]`);
  const rect = el?.getClientRects()[0];
  return rect ? spreadOfRect(rect) : 0;
}

// ---------- 阅读位置 ----------

// 本章文本流总字符数
function textLength() {
  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT);
  let total = 0;
  while (walker.nextNode()) total += walker.currentNode.length;
  return total;
}

// 第 offset 个字符的 Range，越界返回 null
function rangeAt(offset) {
  if (offset < 0 || offset >= state.total) return null;
  const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT);
  let seen = 0;
  while (walker.nextNode()) {
    const node = walker.currentNode;
    if (seen + node.length > offset) {
      const range = doc.createRange();
      range.setStart(node, offset - seen);
      range.setEnd(node, offset - seen + 1);
      return range;
    }
    seen += node.length;
  }
  return null;
}

// 矩形 → 页码（矩形是章节视口坐标，加上横向滚动量得到文档坐标）
function spreadOfRect(rect) {
  const offset = rect.left + frame.contentWindow.scrollX;
  return Math.floor((offset + 1) / stride());
}

// 字符偏移 → 页码；字符不可见（空白折叠等）返回 -1
function spreadAt(offset) {
  const rect = rangeAt(offset)?.getClientRects()[0];
  return rect ? spreadOfRect(rect) : -1;
}

// 二分查找当前页的第一个字符：分栏版面里页码随偏移量单调非递减
function anchorOffset() {
  let lo = 0, hi = state.total - 1, found = -1;
  while (lo <= hi) {
    const mid = (lo + hi) >> 1;
    const spread = spreadAt(mid);
    if (spread < 0 || spread < state.spread) lo = mid + 1;
    else { found = mid; hi = mid - 1; }
  }
  return found;
}

// 上报进度给 Swift（每次落位都发，节流交给 Swift 侧）
function report() {
  window.webkit?.messageHandlers?.reading_progress?.postMessage({
    chapter: state.chapterId,
    offset: state.offset,
    total: state.total,
    ratio: state.spreadCount > 1 ? state.spread / (state.spreadCount - 1) : 0,
  });
}

// 窗口缩放、改设置、图片加载后重新测量，回到锚点所在页；锚点本身不重算，所以反复缩放不会累积漂移
function reflow() {
  applyStyle();
  if (!doc || frame.classList.contains("loading")) return;
  measure();
  const spread = spreadAt(state.offset);
  scrollToSpread(spread >= 0 ? spread : state.spread);
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
