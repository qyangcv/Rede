"use strict";

// ---------- 阅读坐标 ----------

// 阅读位置、目录锚点、书签和高亮共用一套坐标：把章节 body 摊平成单位流，
// 文本节点按 UTF-16 长度计，媒体元素各计 1 且不深入其子节点。
// 媒体被限制在一栏以内（见 mediaLimits）且不许跨栏（ReadiumCSS-before.css 的 img, svg|svg, video），
// 每个媒体都完整落在某一页，整页插图因此也能被定位。
// 这是存储数据依赖的契约：标注存下后改动 MEDIA 会让已有偏移整体错位。
// Swift 侧 EpubBook.textStats 按本定义近似计数，仅用于百分比和字数。
const MEDIA = new Set(["img", "svg", "video"]);

function* units(doc) {
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
function contentLength(doc) {
  let total = 0;
  for (const unit of units(doc)) total += unit.length;
  return total;
}

// 节点起点在坐标中的位置，即排在它之前的单位数（不含其后代）
function offsetBefore(doc, target) {
  let end = 0;
  for (const { node, start, length } of units(doc)) {
    if (node === target || target.compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING) return start;
    end = start + length;
  }
  return end;
}

// DOM 边界点 → 坐标：排在边界点之前的单位数，边界点落在文本单位内时加上字符位置。
// 落在媒体内部（如 svg 的 <text>）的边界点归到该媒体之后
function offsetAt(doc, container, index) {
  const point = doc.createRange();
  point.setStart(container, index);
  let end = 0;
  for (const { node, start, length } of units(doc)) {
    if (node === container) return start + index;
    if (point.comparePoint(node, 0) > 0) return start;
    end = start + length;
  }
  return end;
}

function findAnchor(doc, anchor) {
  const id = CSS.escape(anchor);
  return doc.querySelector(`#${id}, a[name="${id}"]`);
}

function anchorOffsets(doc, ids) {
  const offsets = {};
  for (const id of ids) {
    const el = findAnchor(doc, id);
    if (!el || el === doc.body || !doc.body.contains(el)) continue;
    offsets[id] = offsetBefore(doc, el);
  }
  return offsets;
}

// 坐标区间 [start, end) → DOM Range
function rangesOf(doc, spans) {
  const points = boundaries(doc, spans.flatMap((s) => [s.start, s.end]));
  return spans.map((s) => {
    const range = doc.createRange();
    range.setStart(...points.get(s.start));
    range.setEnd(...points.get(s.end));
    return range;
  });
}

// 一次遍历把一组偏移转成 DOM 边界点：落在文本单位内取字符位置，落在媒体单位上取其前方，越过章末取 body 末尾。
// 恰好等于某单位起点的偏移落在该单位之前，区间终点因此不含该单位
function boundaries(doc, offsets) {
  const sorted = [...new Set(offsets)].sort((a, b) => a - b);
  const points = new Map();
  let i = 0;
  for (const { node, start, length, text } of units(doc)) {
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

// 从 start 起 length 个单位内的文字，空白折叠；媒体不产出文字
function excerpt(doc, start, length) {
  const end = start + length;
  let text = "";
  for (const unit of units(doc)) {
    if (unit.start >= end) break;
    if (!unit.text || unit.start + unit.length <= start) continue;
    text += unit.node.data.slice(Math.max(start - unit.start, 0), end - unit.start);
  }
  return text.replace(/\s+/g, " ").trim();
}
