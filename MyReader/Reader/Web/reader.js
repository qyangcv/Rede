"use strict";

const ASSET_TIMEOUT_MS = 5000;

const book = document.getElementById("book");
const base = document.querySelector("base");
const ROOT = new URL(document.baseURI);

const SPREAD_RATIO = 2 / 3;

const state = {
  spinePaths: [],
  chapterId: -1,
  spread: 0,
  spreadCount: 1,
  spreadStride: 0,
  navId: 0,
  offset: 0,   // 当前页首字符在本章文本流中的偏移量（阅读锚点）
  total: 0,    // 本章文本流总字符数
};

// Swift 调用接口

const reader = {
  // 入口：保存 paths、绑定事件、恢复到 start（null 则从头开始）
  open(paths, style = {}, start = null) {
    state.spinePaths = paths;
    applyStyle(style);
    book.addEventListener("click", onClick);
    book.addEventListener("load", reflow, true);
    window.addEventListener("resize", reflow);
    applyLayout();
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
    applyStyle(vars);
    reflow();
  },
};

// 导航，at 为数字（页码）、字符串（锚点）或位置对象
async function goto(chapter, at) {
  const path = state.spinePaths[chapter];
  if (path === undefined) return;
  const token = ++state.navId;

  if (chapter !== state.chapterId) {
    const url = new URL(path.split("/").map(encodeURIComponent).join("/"), ROOT);
    const nodes = await load(url);
    if (token !== state.navId) return;

    book.classList.add("loading");
    base.href = url.href;
    book.replaceChildren(...nodes);
    state.chapterId = chapter;
    state.total = textLength();
    await waitAssets(book);
    if (token !== state.navId) return;
  }

  measure();
  // 从保存的位置恢复时沿用原锚点，不重新测量，避免多次恢复逐页回退
  settle(locate(at), isPosition(at) ? at.offset : null);
  book.classList.remove("loading");
}

// fetch 章节文件，解析成 DOM 节点
async function load(url) {
  try {
    const text = await (await fetch(url)).text();
    const parser = new DOMParser();
    let doc = parser.parseFromString(text, "application/xhtml+xml");
    if (doc.getElementsByTagName("parsererror").length > 0) {
      doc = parser.parseFromString(text, "text/html");
    }
    return [...(doc.body ?? doc.documentElement).childNodes];
  } catch (error) {
    console.error(`[reader] loading failed: ${url}`, error);
    return [];
  }
}

// 等图片加载完再测量
function waitAssets(root) {
  const images = [...root.querySelectorAll("img")]
    .filter((img) => !img.complete)
    .map((img) => new Promise((resolve) => {
      img.addEventListener("load", resolve, { once: true });
      img.addEventListener("error", resolve, { once: true });
    }));
  const timeout = new Promise((resolve) => setTimeout(resolve, ASSET_TIMEOUT_MS));
  return Promise.race([Promise.all([document.fonts.ready, ...images]), timeout]);
}

// 根据窗口宽度切换单栏 / 双栏
function applyLayout() {
  const spread = window.innerWidth > screen.availWidth * SPREAD_RATIO;
  book.classList.toggle("spread", spread);
}

// 把 CSS 变量写到 :root 的内联样式，覆盖 reader.css 的默认值
function applyStyle(vars = {}) {
  const root = document.documentElement.style;
  for (const [name, value] of Object.entries(vars)) root.setProperty(name, value);
}

// 计算 spreadStride 和 spreadCount
function measure() {
  const gap = parseFloat(getComputedStyle(book).columnGap) || 0;
  state.spreadStride = book.clientWidth + gap;
  state.spreadCount = Math.max(1, Math.round((book.scrollWidth + gap) / state.spreadStride));
}

// 修改 scrollLeft 进行滚动
function scrollToSpread(page) {
  state.spread = Math.min(Math.max(page, 0), state.spreadCount - 1);
  book.scrollLeft = state.spread * state.spreadStride;
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
  const el = book.querySelector(`#${id}, a[name="${id}"]`);
  const rect = el?.getClientRects()[0];
  return rect ? spreadOfRect(rect) : 0;
}

// ---------- 阅读位置 ----------

// 本章文本流总字符数
function textLength() {
  const walker = document.createTreeWalker(book, NodeFilter.SHOW_TEXT);
  let total = 0;
  while (walker.nextNode()) total += walker.currentNode.length;
  return total;
}

// 第 offset 个字符的 Range，越界返回 null
function rangeAt(offset) {
  if (offset < 0 || offset >= state.total) return null;
  const walker = document.createTreeWalker(book, NodeFilter.SHOW_TEXT);
  let seen = 0;
  while (walker.nextNode()) {
    const node = walker.currentNode;
    if (seen + node.length > offset) {
      const range = document.createRange();
      range.setStart(node, offset - seen);
      range.setEnd(node, offset - seen + 1);
      return range;
    }
    seen += node.length;
  }
  return null;
}

// 矩形 → 页码
function spreadOfRect(rect) {
  const offset = rect.left - book.getBoundingClientRect().left + book.scrollLeft;
  return Math.floor((offset + 1) / state.spreadStride);
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

// 窗口缩放,改字号,图片加载后重新测量，回到锚点所在页；锚点本身不重算，所以反复缩放不会累积漂移
function reflow() {
  applyLayout();
  if (book.classList.contains("loading")) return;
  measure();
  const spread = spreadAt(state.offset);
  scrollToSpread(spread >= 0 ? spread : state.spread);
}

// 拦截链接跳转
function onClick(event) {
  const link = event.target.closest("a[href]");
  if (!link) return;
  event.preventDefault();

  let url, path, anchor;
  try {
    url = new URL(link.getAttribute("href"), document.baseURI);
    path = decodeURIComponent(url.pathname.slice(1));
    anchor = decodeURIComponent(url.hash.slice(1));
  } catch {
    return;
  }
  if (url.protocol !== ROOT.protocol || url.host !== ROOT.host) return;

  const chapter = state.spinePaths.indexOf(path);
  if (chapter >= 0) reader.jump(chapter, anchor);
}
