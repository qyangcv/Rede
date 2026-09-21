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
};

// Swift 调用接口

const reader = {
  // 入口：保存 paths、绑定事件、打开第一章
  open(paths, style = {}, chapter = 0) {
    state.spinePaths = paths;
    applyStyle(style);
    book.addEventListener("click", onClick);
    book.addEventListener("load", reflow, true);
    window.addEventListener("resize", reflow);
    applyLayout();
    goto(chapter, 0);
  },

  next() {
    if (state.spread < state.spreadCount - 1) scrollToSpread(state.spread + 1);
    else goto(state.chapterId + 1, 0);
  },

  prev() {
    if (state.spread > 0) scrollToSpread(state.spread - 1);
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

// 导航，at 为数字（页码）或字符串（锚点）
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
    await waitAssets(book);
    if (token !== state.navId) return;
  }

  measure();
  scrollToSpread(locate(at));
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

// 把 at（页码或锚点）转成具体页码
function locate(at) {
  if (typeof at === "number") return at < 0 ? state.spreadCount + at : at;

  const id = CSS.escape(at);
  const el = book.querySelector(`#${id}, a[name="${id}"]`);
  const rect = el?.getClientRects()[0];
  if (!rect) return 0;

  const offset = rect.left - book.getBoundingClientRect().left + book.scrollLeft;
  return Math.floor((offset + 1) / state.spreadStride);
}

// 窗口缩放或图片加载后，重新测量并按比例恢复位置
function reflow() {
  applyLayout();
  if (book.classList.contains("loading")) return;
  const ratio = state.spread / state.spreadCount;
  measure();
  scrollToSpread(Math.round(ratio * state.spreadCount));
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
