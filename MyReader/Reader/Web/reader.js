"use strict";

const ASSET_TIMEOUT_MS = 5000;

const book = document.getElementById("book");
const base = document.querySelector("base");
const ROOT = new URL(document.baseURI);

const state = {
  spinePaths: [],
  chapterId: -1,
  page: 0,
  pageCount: 1,
  pageStride: 0,
  navId: 0,
};

// Swift 调用接口

const reader = {
  // 入口：保存 paths、绑定事件、打开第一章
  open(paths, chapter = 0) {
    state.spinePaths = paths;
    book.addEventListener("click", onClick);
    book.addEventListener("load", reflow, true);
    window.addEventListener("resize", reflow);
    goto(chapter, 0);
  },

  next() {
    if (state.page < state.pageCount - 1) scrollToPage(state.page + 1);
    else goto(state.chapterId + 1, 0);
  },

  prev() {
    if (state.page > 0) scrollToPage(state.page - 1);
    else goto(state.chapterId - 1, -1);
  },

  jump(chapter, anchor) {
    goto(chapter, anchor || 0);
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
  scrollToPage(locate(at));
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

// 计算 step 和 pageCount
function measure() {
  const gap = parseFloat(getComputedStyle(book).columnGap) || 0;
  state.pageStride = book.clientWidth + gap;
  state.pageCount = Math.max(1, Math.round((book.scrollWidth + gap) / state.pageStride));
}

// 修改 scrollLeft 进行滚动
function scrollToPage(page) {
  state.page = Math.min(Math.max(page, 0), state.pageCount - 1);
  book.scrollLeft = state.page * state.pageStride;
}

// 把 at（页码或锚点）转成具体页码
function locate(at) {
  if (typeof at === "number") return at < 0 ? state.pageCount + at : at;

  const id = CSS.escape(at);
  const el = book.querySelector(`#${id}, a[name="${id}"]`);
  const rect = el?.getClientRects()[0];
  if (!rect) return 0;

  const offset = rect.left - book.getBoundingClientRect().left + book.scrollLeft;
  return Math.floor((offset + 1) / state.pageStride);
}

// 窗口缩放或图片加载后，重新测量并按比例恢复位置
function reflow() {
  if (book.classList.contains("loading")) return;
  const ratio = state.page / state.pageCount;
  measure();
  scrollToPage(Math.round(ratio * state.pageCount));
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
