/*
 * Xmind 快捷样式槽 —— 注入到 editor.js 的插件本体
 *
 * 用法：
 *   ⌃⌥1 ~ ⌃⌥5          应用第 N 个样式槽
 *   ⌃⌥⇧1 ~ ⌃⌥⇧5        把当前选中主题的样式存入第 N 个槽
 *
 * 槽位内容：文字颜色、字重（加粗）、字号
 * 槽位持久化在 localStorage，重启 Xmind 后仍在。
 */
(() => {
  if (window.__xmindStyleSlotsLoaded) return;
  window.__xmindStyleSlotsLoaded = true;

  const CONFIG = {
    slotCount: 5,
    storeKey: "xmindStyleSlots.v1",
    // 应用样式：Ctrl + Alt + 数字
    apply: { ctrl: true, alt: true, shift: false, meta: false },
    // 保存样式：Ctrl + Alt + Shift + 数字
    save: { ctrl: true, alt: true, shift: true, meta: false },
  };

  let slots = [];
  try {
    const raw = localStorage.getItem(CONFIG.storeKey);
    if (raw) slots = JSON.parse(raw) || [];
  } catch (e) {
    slots = [];
  }
  while (slots.length < CONFIG.slotCount) slots.push(null);

  function persist() {
    try {
      localStorage.setItem(CONFIG.storeKey, JSON.stringify(slots));
    } catch (e) {}
  }

  // 通过 webpack runtime 拿到 require，再取出编辑器状态单例
  function getRequire() {
    if (window.__xmindWpReq) return window.__xmindWpReq;
    try {
      window.webpackChunkxmind_vana.push([
        [987654321],
        {},
        (req) => {
          window.__xmindWpReq = req;
        },
      ]);
    } catch (e) {}
    return window.__xmindWpReq;
  }

  function getEditor() {
    const req = getRequire();
    if (!req) return null;
    try {
      return req(5805).nZ();
    } catch (e) {
      return null;
    }
  }

  function colorToHex(c) {
    if (!c) return null;
    if (typeof c === "string") return c.charAt(0) === "#" ? c : "#" + c;
    const hex = (n) =>
      Math.max(0, Math.min(255, Math.round(n || 0)))
        .toString(16)
        .padStart(2, "0")
        .toUpperCase();
    let out = "#" + hex(c.r) + hex(c.g) + hex(c.b);
    if (typeof c.a === "number" && c.a < 1) out += hex(c.a * 255);
    return out;
  }

  // 主题自身是否带了显式样式（不是从主题风格继承来的）
  function hasOwnStyle(st, topicId) {
    try {
      const sheet = st.activeSheet && st.activeSheet.value;
      const view = sheet && sheet.query({ id: topicId });
      const topic = view && view.asTopic ? view.asTopic() : null;
      if (!topic) return false;
      return !!(topic.textColor || topic.fontSize || topic.fontWeight);
    } catch (e) {
      return false;
    }
  }

  function hexToLabel(hex) {
    return hex || "继承";
  }

  let toastTimer = null;
  function toast(text) {
    try {
      let el = document.getElementById("__xmindSlotToast");
      if (!el) {
        el = document.createElement("div");
        el.id = "__xmindSlotToast";
        el.style.cssText =
          "position:fixed;left:50%;bottom:56px;transform:translateX(-50%);" +
          "background:rgba(28,28,30,.94);color:#fff;padding:9px 18px;border-radius:9px;" +
          "font:13px/1.4 -apple-system,BlinkMacSystemFont,'PingFang SC',sans-serif;" +
          "z-index:2147483647;pointer-events:none;box-shadow:0 4px 18px rgba(0,0,0,.28);" +
          "opacity:0;transition:opacity .18s ease;white-space:pre;letter-spacing:.2px;";
        document.body.appendChild(el);
      }
      el.textContent = text;
      el.style.opacity = "1";
      clearTimeout(toastTimer);
      toastTimer = setTimeout(() => {
        el.style.opacity = "0";
      }, 1400);
    } catch (e) {}
  }

  const SLOT_CN = ["一", "二", "三", "四", "五"];

  function selectedIds(st) {
    const sel = st.selection && st.selection.value;
    if (!sel || sel.type !== "topic" || !sel.modelIds || !sel.modelIds.length) return [];
    return sel.modelIds.filter(Boolean);
  }

  // ===== 文字选区（富文本 span）支持 =====

  // selection 里的 {index, offset} → 整段文字中的绝对字符位置
  function toAbsolute(spans, pos) {
    if (!pos) return 0;
    const idx = Math.max(0, Math.min(pos.index || 0, spans.length - 1));
    let base = 0;
    for (let i = 0; i < idx; i++) base += (spans[i].text || "").length;
    return base + (pos.offset || 0);
  }

  // 正在编辑文字且选中了一段文字时，返回选区信息
  function getTextSelection(st) {
    try {
      const viewer = st.activeSheetViewer && st.activeSheetViewer.value;
      const tim = viewer && viewer.textInputManager;
      if (!tim || !tim.isActive || !tim.isActive()) return null;
      const cur = tim.currentText();
      if (!cur || !cur.selection || !cur.textSpans || !cur.textSpans.length) return null;
      const a = toAbsolute(cur.textSpans, cur.selection.anchor);
      const f = toAbsolute(cur.textSpans, cur.selection.focus);
      const start = Math.min(a, f);
      const end = Math.max(a, f);
      if (end <= start) return null;
      return { cur: cur, start: start, end: end };
    } catch (e) {
      return null;
    }
  }

  function sizeToPt(v) {
    if (v == null) return null;
    if (typeof v === "number") return Math.round(v) + "pt";
    return String(v);
  }

  // 取主题对象；刚换过文档时可能短暂取不到
  function getTopicById(st, topicId) {
    try {
      const sheet = st.activeSheet && st.activeSheet.value;
      const view = sheet && sheet.query({ id: topicId });
      return view && view.asTopic ? view.asTopic() : null;
    } catch (e) {
      return null;
    }
  }

  // 主题富文本里，offset 所在的 span 的显式样式
  function spanStyleAt(topic, offset) {
    if (!topic) return null;
    const spans = (topic.attributedTitle || []).filter((s) => s && s.text);
    if (!spans.length) return null;
    if (spans.map((s) => s.text).join("") !== (topic.title || "")) return null;
    let pos = 0;
    for (const sp of spans) {
      const len = sp.text.length;
      if (offset >= pos && offset < pos + len) {
        return {
          textColor: sp.textColor || null,
          fontWeight: sp.fontWeight || null,
          fontSize: sp.fontSize || null,
        };
      }
      pos += len;
    }
    return null;
  }

  // 读取选区所在文字的样式
  function readSelectionStyle(st, sel, topicId) {
    const topic = topicId ? getTopicById(st, topicId) : null;
    const spanAttrs = spanStyleAt(topic, sel.start) || {};

    const spans = sel.cur.textSpans || [];
    const anchorIdx = Math.max(
      0,
      Math.min(((sel.cur.selection.anchor || {}).index) || 0, spans.length - 1)
    );
    const edSpan = spans[anchorIdx] || {};
    const fallback = sel.cur.defaultAttributes || {};

    const color =
      spanAttrs.textColor || edSpan.textColor || (topic && topic.textColor) || fallback.textColor;
    const weight =
      spanAttrs.fontWeight || edSpan.fontWeight || (topic && topic.fontWeight) || fallback.fontWeight;
    const size =
      spanAttrs.fontSize || edSpan.fontSize || (topic && topic.fontSize) || fallback.fontSize;

    if (!color && !weight && !size) return null;
    return {
      textColor: colorToHex(color),
      fontWeight: String(weight || "400"),
      fontSize: sizeToPt(size) || "18pt",
    };
  }

  // 把主题的富文本还原成完整 span 列表（保证拼接后等于标题）
  function normalizeSpans(topic) {
    const title = topic.title || "";
    const raw = (topic.attributedTitle || []).filter((s) => s && s.text);
    if (raw.length && raw.map((s) => s.text).join("") === title) {
      return raw.map((s) => Object.assign({}, s));
    }
    return [{ text: title }];
  }

  // 把 [start, end) 区间切出来打上样式
  function patchRange(spans, start, end, patch) {
    const out = [];
    let pos = 0;
    for (const span of spans) {
      const text = span.text || "";
      const spStart = pos;
      pos += text.length;
      if (pos <= start || spStart >= end) {
        out.push(Object.assign({}, span));
        continue;
      }
      const head = text.slice(0, Math.max(0, start - spStart));
      const midStart = Math.max(0, start - spStart);
      const midEnd = Math.min(text.length, end - spStart);
      const mid = text.slice(midStart, midEnd);
      const tail = text.slice(midEnd);
      if (head) out.push(Object.assign({}, span, { text: head }));
      if (mid) out.push(Object.assign({}, span, patch, { text: mid }));
      if (tail) out.push(Object.assign({}, span, { text: tail }));
    }
    return out;
  }

  // 套用到当前文字选区
  function applyToSelection(st, style) {
    const ids = selectedIds(st);
    if (!ids.length) return false;
    const topic = getTopicById(st, ids[0]);
    if (!topic) return false;

    const sel = getTextSelection(st);
    if (!sel) return false;

    const spans = normalizeSpans(topic);
    const patch = {};
    if (style.textColor) patch.textColor = style.textColor;
    if (style.fontWeight) patch.fontWeight = style.fontWeight;
    if (style.fontSize) patch.fontSize = style.fontSize;

    const next = patchRange(spans, sel.start, sel.end, patch);
    const committed = topic.asMutable().attrs({ attributedTitle: next }).commit();
    // 立即强制重绘，让用户像手动设置一样秒看到效果
    try { st.emitForceRendering && st.emitForceRendering(); } catch (e) {}
    // 异步补 undo（changeDoc 很重，放后面不阻塞视觉）
    Promise.resolve().then(() => {
      try {
        const doc =
          committed.ownerDocument ||
          (committed.primaryOwnerSheet && committed.primaryOwnerSheet.ownerDocument);
        if (doc && st.changeDoc) st.changeDoc(doc);
      } catch (e) {}
    });
    return true;
  }

  function readStyleOf(st, topicId) {
    // 模型属性（topic.textColor 等）是即时生效的；
    // 渲染层快照（figure.viewAttributes）会滞后数百毫秒，只能用来补全"继承值"。
    const topic = getTopicById(st, topicId);

    const fig = st.activeSheetFigure && st.activeSheetFigure.value;
    const f = fig && fig.topicFigureByTopicId && fig.topicFigureByTopicId[topicId];
    const va = f && f.viewAttributes;

    let textColor = null;
    if (topic && topic.textColor) textColor = colorToHex(topic.textColor);
    else if (va && va.titleTextColor) textColor = colorToHex(va.titleTextColor);

    let fontWeight = null;
    if (topic && topic.fontWeight) fontWeight = String(topic.fontWeight);
    else if (va && va.titleTextFontWeight) fontWeight = String(va.titleTextFontWeight);

    let fontSize = null;
    if (topic && topic.fontSize) fontSize = String(topic.fontSize);
    else if (va && va.titleTextFontSize) fontSize = Math.round(va.titleTextFontSize) + "pt";

    if (!fontSize && !fontWeight && !textColor) return null;
    return {
      textColor: textColor,
      fontWeight: fontWeight || "400",
      fontSize: fontSize || "18pt",
    };
  }

  function saveSlot(st, idx) {
    const ids = selectedIds(st);
    if (!ids.length) {
      toast("请先选中主题");
      return;
    }

    const commit = (style, fromText) => {
      if (!style) {
        toast("读取样式失败");
        return;
      }
      slots[idx] = style;
      persist();
      toast(
        (fromText ? "已保存选中文字的样式到槽 " : "已保存到样式槽 ") + SLOT_CN[idx] + "\n" +
          "颜色 " + hexToLabel(style.textColor) + "   " +
          "字号 " + style.fontSize + "   " +
          "字重 " + style.fontWeight
      );
    };

    // 优先：正在编辑文字且选中了一段 → 存这段文字的样式
    const textSel = getTextSelection(st);
    if (textSel) {
      const attempt = (retry) => {
        const topic = getTopicById(st, ids[0]);
        if (!topic && retry > 0) {
          setTimeout(() => attempt(retry - 1), 120);
          return;
        }
        commit(readSelectionStyle(st, textSel, ids[0]), true);
      };
      attempt(3);
      return;
    }

    // 主题用的是继承样式时，渲染快照可能还没跟上，强制重绘后再读一次
    if (hasOwnStyle(st, ids[0])) {
      commit(readStyleOf(st, ids[0]), false);
    } else {
      try {
        st.emitForceRendering && st.emitForceRendering();
      } catch (e) {}
      setTimeout(() => commit(readStyleOf(st, ids[0]), false), 350);
    }
  }

  function applySlot(st, idx) {
    const style = slots[idx];
    if (!style) {
      toast("样式槽 " + SLOT_CN[idx] + " 是空的\n先用 ⌃⌥⇧" + (idx + 1) + " 保存一个");
      return;
    }
    const ids = selectedIds(st);
    if (!ids.length) {
      toast("请先选中主题");
      return;
    }

    // 优先：正在编辑文字且选中了一段 → 只套用给这段文字
    const textSel = getTextSelection(st);
    if (textSel) {
      if (applyToSelection(st, style)) toast("已套用到选中的文字");
      else toast("套用失败，请再试一次");
      return;
    }

    if (st.isEditingTitle && st.isEditingTitle.value) {
      toast("请先在主题里选中要高亮的文字\n或按 Esc 退出编辑，套用给整个主题");
      return;
    }

    const patch = {};
    if (style.textColor) patch.textColor = style.textColor;
    if (style.fontWeight) patch.fontWeight = style.fontWeight;
    if (style.fontSize) patch.fontSize = style.fontSize;

    try {
      const sheet = st.activeSheet.value;
      const committed = sheet
        .queryList(ids.map((id) => ({ id })))
        .asTopics()
        .asMutable()
        .attrs(patch)
        .commit();
      // 立即强制重绘，让用户像手动设置一样秒看到效果
      try { st.emitForceRendering && st.emitForceRendering(); } catch (e) {}
      // 异步补 undo（changeDoc 很重，放后面不阻塞视觉）
      Promise.resolve().then(() => {
        try {
          const doc =
            committed.ownerDocument ||
            (committed.primaryOwnerSheet && committed.primaryOwnerSheet.ownerDocument) ||
            (committed.ownerSheet && committed.ownerSheet.ownerDocument);
          if (doc && st.changeDoc) st.changeDoc(doc);
        } catch (e) {}
      });
      toast("已应用样式槽 " + SLOT_CN[idx] + "（" + ids.length + " 个主题）");
    } catch (e) {
      toast("应用失败：" + (e && e.message ? e.message : e));
    }
  }

  function modsMatch(e, want) {
    return (
      e.ctrlKey === want.ctrl &&
      e.altKey === want.alt &&
      e.shiftKey === want.shift &&
      e.metaKey === want.meta
    );
  }

  window.addEventListener(
    "keydown",
    (e) => {
      if (e.repeat) return;
      const m = /^Digit([1-9])$/.exec(e.code || "");
      if (!m) return;
      const n = parseInt(m[1], 10);
      if (n > CONFIG.slotCount) return;
      const isApply = modsMatch(e, CONFIG.apply);
      const isSave = modsMatch(e, CONFIG.save);
      if (!isApply && !isSave) return;
      e.preventDefault();
      e.stopPropagation();
      const st = getEditor();
      if (!st) {
        toast("未连接编辑器");
        return;
      }
      if (isSave) saveSlot(st, n - 1);
      else applySlot(st, n - 1);
    },
    true
  );

  window.__xmindStyleSlots = {
    CONFIG,
    get slots() {
      return slots;
    },
    // 给外部面板读取：槽位内容 + 当前选中情况
    info() {
      const st = getEditor();
      const sel = st && st.selection ? st.selection.value : null;
      let textSelection = false;
      if (st) {
        try {
          textSelection = !!getTextSelection(st);
        } catch (e) {}
      }
      return {
        slots: slots,
        connected: !!st,
        editingTitle: !!(st && st.isEditingTitle && st.isEditingTitle.value),
        textSelection: textSelection,
        selection: sel ? { type: sel.type, count: (sel.modelIds || []).length } : null,
      };
    },
    save: (n) => saveSlot(getEditor(), n - 1),
    apply: (n) => applySlot(getEditor(), n - 1),
    clearSlot: (i) => {
      if (i >= 0 && i < CONFIG.slotCount) {
        slots[i] = null;
        persist();
      }
    },
    clear: () => {
      slots = new Array(CONFIG.slotCount).fill(null);
      persist();
    },
  };
})();
