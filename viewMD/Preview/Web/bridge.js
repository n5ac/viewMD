// bridge.js: the preview page's side of the Swift <-> page bridge.
//
// Swift → page:
//   viewmd.render({blocks: [{src, html}], placeholder, editable})
//   viewmd.format(command)        formatting from the pull-downs (REQ-015)
//   viewmd.caretLine()            last source line of the block at the caret
//   viewmd.scrollToLine(line)     scroll sync from the source pane (REQ-020)
//   viewmd.find(query, step)      find in the pane (REQ-025); → {count, current}
//   viewmd.endFind(select)        clear find highlights, optionally selecting
//                                 the current match
//   viewmd.selectionText()        the selected text
//
// Page → Swift (window.webkit.messageHandlers.viewmd):
//   {type: "ready"}                         page loaded
//   {type: "focus"}                         the rendered pane gained focus
//   {type: "openLink", href}                ⌘-click (or click when read-only)
//   {type: "edit", start, end, afterLine, html}
//                                           blocks edited in the pane (REQ-013)
//   {type: "scroll", line}                  top visible source line (REQ-020)
//   {type: "find", count, current}          matches recounted after a render
//
// Rendering patches the DOM instead of replacing it. Each top-level block is
// tracked in `entries` with the source lines it came from and its serialized
// HTML at render time. When the user edits, the changed run of blocks is
// found by comparing against those snapshots, and only that run is sent to
// Swift with its line range.
//
// Copyright (C) 2026 Stephen Hicks, N5AC
//
// This file is part of viewMD.
//
// viewMD is free software: you can redistribute it and/or modify it under
// the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version.
//
// viewMD is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
// FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
// details.
//
// You should have received a copy of the GNU General Public License along
// with viewMD. If not, see <https://www.gnu.org/licenses/>.
(() => {
  "use strict";

  const content = document.getElementById("content");

  /** Delay after the last keystroke before an edit is sent. */
  const EDIT_DELAY_MS = 250;

  /**
   * Tracked blocks, in document order. Each entry:
   *   start, end   source lines (end = start - 1 for a block not yet in the
   *                source: it is inserted after line `start - 1`)
   *   html         rendered HTML (null for blocks created by editing)
   *   nodes        the DOM nodes showing it
   *   snapshot     each node's outerHTML when last synced (null = dirty)
   */
  let entries = [];

  let editTimer = null;      // pending debounced edit
  let awaitingRender = false; // an edit was sent; its re-render hasn't arrived
  let awaitingSince = 0;
  let composing = false;     // IME composition in progress
  let editable = false;
  let suppressScrollReport = false;

  /** Sends a message to Swift. */
  function post(message) {
    window.webkit.messageHandlers.viewmd.postMessage(message);
  }

  // MARK: Rendering

  /** Builds DOM nodes from an HTML string. */
  function nodesFromHTML(html) {
    const template = document.createElement("template");
    template.innerHTML = html;
    return Array.from(template.content.children);
  }

  /** Applies highlight.js to code blocks inside `root` that name a language (REQ-019). */
  function highlightCode(root) {
    if (!window.hljs) return;
    root.querySelectorAll("pre code[class*='language-']").forEach((code) => {
      const match = code.className.match(/language-(\S+)/);
      if (match && hljs.getLanguage(match[1])) hljs.highlightElement(code);
    });
  }

  /** Prepares a freshly rendered block node for display and editing. */
  function prepareNode(node) {
    highlightCode(node);
    if (editable) {
      // Task boxes become clickable while editing.
      node.querySelectorAll("input[type=checkbox]").forEach((box) => box.removeAttribute("disabled"));
    }
    return node;
  }

  function parseSrc(src) {
    const [start, end] = src.split("-").map(Number);
    return { start, end };
  }

  const stripSrc = (html) => (html || "").replace(/ data-src="\d+-\d+"/, "");

  /** The caret position as a character offset into the pane's text. */
  function captureCaret() {
    const selection = window.getSelection();
    if (!selection.rangeCount || !content.contains(selection.focusNode)) return null;
    return textOffset(selection.focusNode, selection.focusOffset);
  }

  function textOffset(targetNode, targetOffset) {
    const range = document.createRange();
    range.setStart(content, 0);
    try { range.setEnd(targetNode, targetOffset); } catch { return null; }
    return range.toString().length;
  }

  /** Puts the caret back at a character offset. */
  function restoreCaret(offset) {
    if (offset === null) return;
    const walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT);
    let remaining = offset;
    let node;
    let last = null;
    while ((node = walker.nextNode())) {
      last = node;
      if (remaining <= node.data.length) {
        window.getSelection().collapse(node, remaining);
        return;
      }
      remaining -= node.data.length;
    }
    if (last) window.getSelection().collapse(last, last.data.length);
  }

  /**
   * Shows `blocks`. Unchanged blocks keep their DOM nodes (matched by HTML
   * from the front and back), and the run in between is replaced. If the
   * user has typed since the last edit was sent, the edited DOM in that run
   * is kept instead and marked dirty, so the pending edit is still sent.
   */
  function render(payload) {
    const blocks = payload.blocks;
    content.setAttribute("data-placeholder", payload.placeholder || "");
    if (payload.editable !== undefined && payload.editable !== editable) {
      editable = payload.editable;
      content.contentEditable = editable ? "true" : "false";
    }
    awaitingRender = false;

    const hasUnsentEdits = editTimer !== null || composing;
    const same = (entry, block) => entry.html !== null && stripSrc(entry.html) === stripSrc(block.html) &&
      entry.nodes.every((node) => node.parentNode === content);

    let prefix = 0;
    while (prefix < entries.length && prefix < blocks.length && same(entries[prefix], blocks[prefix])) prefix++;
    let suffix = 0;
    while (suffix < entries.length - prefix && suffix < blocks.length - prefix &&
           same(entries[entries.length - 1 - suffix], blocks[blocks.length - 1 - suffix])) suffix++;

    const refresh = (entry, block) => {
      // A kept block the user has edited (not yet sent) stays dirty.
      const wasClean = entry.snapshot !== null && entry.nodes.every((node, i) => node.outerHTML === entry.snapshot[i]);
      const { start, end } = parseSrc(block.src);
      entry.start = start;
      entry.end = end;
      entry.html = block.html;
      entry.nodes.forEach((node) => node.setAttribute("data-src", block.src));
      entry.snapshot = wasClean ? entry.nodes.map((node) => node.outerHTML) : null;
      return entry;
    };
    const head = entries.slice(0, prefix).map((entry, i) => refresh(entry, blocks[i]));
    const tail = entries.slice(entries.length - suffix).map((entry, i) => refresh(entry, blocks[blocks.length - suffix + i]));
    const middleBlocks = blocks.slice(prefix, blocks.length - suffix);

    // DOM range between the last kept head node and the first kept tail node.
    const afterNode = head.length ? head[head.length - 1].nodes.at(-1) : null;
    const beforeNode = tail.length ? tail[0].nodes[0] : null;
    const middleDOM = [];
    for (let node = afterNode ? afterNode.nextSibling : content.firstChild; node && node !== beforeNode; node = node.nextSibling) {
      middleDOM.push(node);
    }

    let middle;
    if (hasUnsentEdits && middleDOM.length) {
      // Keep what the user is typing; it becomes one dirty group covering
      // the new render's lines for this run.
      const elements = middleDOM.filter((node) => node.nodeType === Node.ELEMENT_NODE);
      const first = middleBlocks.length ? parseSrc(middleBlocks[0].src).start : (head.length ? head.at(-1).end + 1 : 1);
      const last = middleBlocks.length ? parseSrc(middleBlocks.at(-1).src).end : first - 1;
      middle = [{ start: first, end: last, html: null, nodes: elements, snapshot: null }];
    } else {
      const caret = captureCaret();
      middleDOM.forEach((node) => node.remove());
      middle = middleBlocks.map((block) => {
        const node = prepareNode(nodesFromHTML(block.html)[0] || document.createElement("div"));
        content.insertBefore(node, beforeNode);
        const { start, end } = parseSrc(block.src);
        return { start, end, html: block.html, nodes: [node], snapshot: [node.outerHTML] };
      });
      if (caret !== null && document.activeElement === content) restoreCaret(caret);
    }
    entries = head.concat(middle, tail);
    if (find.query) {
      const result = findInPane(find.query, "refresh");
      post({ type: "find", count: result.count, current: result.current });
    }
  }

  // MARK: Editing (REQ-013)

  /** Wraps stray top-level text (typed into an empty pane) in a paragraph. */
  function wrapStrayText() {
    for (const node of Array.from(content.childNodes)) {
      if (node.nodeType === Node.TEXT_NODE && node.data.trim() !== "") {
        const caret = captureCaret();
        const paragraph = document.createElement("p");
        content.insertBefore(paragraph, node);
        paragraph.appendChild(node);
        restoreCaret(caret);
      }
    }
  }

  const isClean = (entry, node, index) => entry.snapshot !== null && node === entry.nodes[index] &&
    node.outerHTML === entry.snapshot[index];

  /**
   * Finds the run of blocks that changed since the last sync and sends it
   * to Swift with its source lines.
   */
  function sendEdit() {
    editTimer = null;
    if (composing) return scheduleEdit();
    if (awaitingRender && Date.now() - awaitingSince < 2000) return scheduleEdit();
    wrapStrayText();

    const nodes = Array.from(content.children);
    let prefix = 0;
    let first = 0;
    while (prefix < entries.length) {
      const entry = entries[prefix];
      if (!entry.nodes.every((node, i) => isClean(entry, nodes[first + i], i))) break;
      first += entry.nodes.length;
      prefix++;
    }
    let suffix = 0;
    let end = nodes.length;
    while (suffix < entries.length - prefix) {
      const entry = entries[entries.length - 1 - suffix];
      const offset = end - entry.nodes.length;
      if (offset < first || !entry.nodes.every((node, i) => isClean(entry, nodes[offset + i], i))) break;
      end = offset;
      suffix++;
    }

    const oldMiddle = entries.slice(prefix, entries.length - suffix);
    const newNodes = nodes.slice(first, end);
    if (!oldMiddle.length && !newNodes.length) return;

    const message = { type: "edit", html: newNodes.map((node) => node.outerHTML).join("\n") };
    const ranged = oldMiddle.filter((entry) => entry.end >= entry.start);
    let start;
    let last;
    if (ranged.length) {
      start = ranged[0].start;
      last = ranged.at(-1).end;
      message.start = start;
      message.end = last;
    } else {
      const afterLine = oldMiddle.length ? oldMiddle[0].start - 1 : (prefix > 0 ? entries[prefix - 1].end : 0);
      message.afterLine = afterLine;
      start = afterLine + 1;
      last = afterLine;
    }

    // Until the re-render arrives, track the edited nodes as one group.
    const group = { start, end: last, html: null, nodes: newNodes, snapshot: newNodes.map((node) => node.outerHTML) };
    entries = entries.slice(0, prefix).concat(newNodes.length || ranged.length ? [group] : [], entries.slice(entries.length - suffix));
    awaitingRender = true;
    awaitingSince = Date.now();
    post(message);
  }

  function scheduleEdit() {
    if (editTimer !== null) clearTimeout(editTimer);
    editTimer = setTimeout(sendEdit, EDIT_DELAY_MS);
  }

  content.addEventListener("input", () => { if (editable) scheduleEdit(); });
  content.addEventListener("compositionstart", () => { composing = true; });
  content.addEventListener("compositionend", () => { composing = false; scheduleEdit(); });

  // An emptied pane still needs a paragraph to type into.
  content.addEventListener("focus", () => {
    if (editable && !content.firstElementChild) {
      const paragraph = document.createElement("p");
      paragraph.appendChild(document.createElement("br"));
      content.appendChild(paragraph);
      window.getSelection().collapse(paragraph, 0);
    }
  });

  // MARK: Links, task boxes and focus

  /** Scrolls to the element a `#fragment` names, if any. */
  function scrollToFragment(fragment) {
    const id = decodeURIComponent(fragment.replace(/^#/, ""));
    const target = document.getElementById(id);
    if (target) target.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  document.addEventListener("click", (event) => {
    const target = event.target;
    if (target instanceof HTMLInputElement && target.type === "checkbox" && editable) {
      // Reflect the toggle in the markup so it reaches the Markdown.
      if (target.checked) target.setAttribute("checked", ""); else target.removeAttribute("checked");
      scheduleEdit();
      return;
    }
    const link = target.closest && target.closest("a[href]");
    if (!link) return;
    // While editing, a plain click places the caret; ⌘-click opens.
    if (editable && !event.metaKey) return;
    event.preventDefault();
    const href = link.getAttribute("href");
    if (href.startsWith("#")) scrollToFragment(href);
    else post({ type: "openLink", href: link.href });
  });

  document.addEventListener("focusin", () => post({ type: "focus" }));

  // MARK: Formatting commands (REQ-015)

  function escapeHTML(text) {
    return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  }

  /** Applies a quick-insert command to the selection in the rendered pane. */
  function format(command) {
    if (!editable) return;
    content.focus();
    const selected = window.getSelection().toString();
    const exec = (name, value) => document.execCommand(name, false, value);
    switch (command) {
      case "bold": exec("bold"); break;
      case "italic": exec("italic"); break;
      case "strikethrough": exec("strikeThrough"); break;
      case "inlineCode": exec("insertHTML", "<code>" + escapeHTML(selected || "code") + "</code>"); break;
      case "link":
        if (selected) exec("createLink", "https://");
        else exec("insertHTML", '<a href="https://">link text</a>');
        break;
      case "image": exec("insertHTML", '<img src="image.png" alt="' + escapeHTML(selected || "alt text") + '">'); break;
      case "bulletList": exec("insertUnorderedList"); break;
      case "numberedList": exec("insertOrderedList"); break;
      case "blockquote": exec("formatBlock", "blockquote"); break;
      default: {
        const heading = command.match(/^heading([1-6])$/);
        if (heading) exec("formatBlock", "h" + heading[1]);
      }
    }
    scheduleEdit();
  }

  /** The last source line of the block containing the caret (0 if none). */
  function caretLine() {
    const selection = window.getSelection();
    if (selection.rangeCount && content.contains(selection.focusNode)) {
      let node = selection.focusNode;
      while (node && node.parentNode !== content) node = node.parentNode;
      const entry = entries.find((candidate) => candidate.nodes.includes(node));
      if (entry) return Math.max(entry.end, entry.start - 1);
    }
    return entries.length ? entries.at(-1).end : 0;
  }

  // MARK: Scroll sync (REQ-020)

  /** Reported instead of a line when the pane is scrolled to the very end. */
  const END_OF_DOCUMENT = 2147483647;

  /** The source line at the top of the visible area. */
  function topVisibleLine() {
    const scroller = document.scrollingElement;
    if (scroller.scrollTop > 0 && scroller.scrollTop + window.innerHeight >= scroller.scrollHeight - 2) return END_OF_DOCUMENT;
    for (const entry of entries) {
      const rect = entry.nodes[0] && entry.nodes[0].getBoundingClientRect();
      if (rect && rect.bottom > 0) {
        if (rect.top >= 0 || rect.height === 0) return entry.start;
        // Interpolate within a tall block.
        const fraction = Math.min(1, -rect.top / rect.height);
        return entry.start + Math.floor(fraction * (entry.end - entry.start + 1));
      }
    }
    return entries.length ? entries.at(-1).end : 1;
  }

  /** Scrolls so the given source line is at the top (past the last block: to the end). */
  function scrollToLine(line) {
    const lastEnd = entries.length ? entries.at(-1).end : 0;
    const firstStart = entries.length ? entries[0].start : 1;
    if (line > lastEnd || line <= firstStart) {
      // Past the end: go to the end. At or before the first block: go to
      // the very top (including the page's top padding).
      suppressScrollReport = true;
      window.scrollTo({ top: line > lastEnd ? document.scrollingElement.scrollHeight : 0 });
      requestAnimationFrame(() => { suppressScrollReport = false; });
      return;
    }
    const entry = entries.find((candidate) => candidate.end >= line && candidate.start <= Math.max(line, candidate.start)) || entries.at(-1);
    if (!entry || !entry.nodes[0]) return;
    const rect = entry.nodes[0].getBoundingClientRect();
    const span = Math.max(1, entry.end - entry.start + 1);
    const fraction = Math.max(0, Math.min(1, (line - entry.start) / span));
    suppressScrollReport = true;
    window.scrollTo({ top: window.scrollY + rect.top + fraction * rect.height - 8 });
    requestAnimationFrame(() => { suppressScrollReport = false; });
  }

  let scrollFrame = null;
  window.addEventListener("scroll", () => {
    if (suppressScrollReport || scrollFrame !== null) return;
    scrollFrame = requestAnimationFrame(() => {
      scrollFrame = null;
      post({ type: "scroll", line: topVisibleLine() });
    });
  }, { passive: true });

  // MARK: Find (REQ-025)

  /** The active search: query, matches (Ranges, in order) and the current match (-1 = none). */
  const find = { query: "", matches: [], current: -1 };

  // Matches are painted with the CSS Custom Highlight API, which doesn't
  // touch the DOM. Wrapping matches in elements would look like an edit to
  // the edit-back code and corrupt the Markdown.
  const highlights = window.CSS && CSS.highlights && typeof Highlight === "function" ? CSS.highlights : null;

  function escapeRegExp(text) {
    return text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  }

  /**
   * Every case-insensitive match of `query` in the pane, as Ranges. A match
   * can cross inline elements (e.g. "bold" in "**bo**ld", or a highlighted
   * code span) but not the boundary between top-level blocks.
   */
  function findRanges(query) {
    if (!query) return [];
    const pattern = new RegExp(escapeRegExp(query), "giu");
    const ranges = [];
    for (const block of content.childNodes) {
      const nodes = [];
      const starts = [];
      let text = "";
      const add = (node) => { nodes.push(node); starts.push(text.length); text += node.data; };
      if (block.nodeType === Node.TEXT_NODE) add(block);
      else if (block.nodeType === Node.ELEMENT_NODE) {
        const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
        for (let node = walker.nextNode(); node; node = walker.nextNode()) add(node);
      }
      if (!text) continue;
      // Maps an offset in `text` to a (node, offset) pair. A start offset
      // on a node boundary belongs to the next node, an end offset to the
      // previous one, so ranges don't include empty edges.
      let index = 0;
      const locate = (offset, isEnd) => {
        while (index < nodes.length - 1 &&
               (isEnd ? starts[index] + nodes[index].data.length < offset : starts[index + 1] <= offset)) index++;
        return [nodes[index], offset - starts[index]];
      };
      for (const match of text.matchAll(pattern)) {
        if (!match[0].length) continue;
        const range = document.createRange();
        range.setStart(...locate(match.index, false));
        range.setEnd(...locate(match.index + match[0].length, true));
        ranges.push(range);
      }
    }
    return ranges;
  }

  /** Paints all matches, and the current one more strongly. */
  function paintFind() {
    if (!highlights) return;
    highlights.delete("viewmd-find");
    highlights.delete("viewmd-find-current");
    if (!find.matches.length) return;
    const all = new Highlight();
    find.matches.forEach((range) => all.add(range));
    highlights.set("viewmd-find", all);
    const current = find.matches[find.current];
    if (current) highlights.set("viewmd-find-current", new Highlight(current));
  }

  /** Index of the first match at or below the top of the view (0 if none). */
  function firstVisibleMatch() {
    const index = find.matches.findIndex((range) => range.getBoundingClientRect().bottom >= 0);
    return index < 0 ? 0 : index;
  }

  /** Scrolls a match into view (a third of the way down) if it's off screen. */
  function revealMatch(range) {
    const rect = range.getBoundingClientRect();
    if (rect.top >= 0 && rect.bottom <= window.innerHeight) return;
    window.scrollTo({ top: window.scrollY + rect.top - window.innerHeight / 3 });
  }

  /**
   * Searches the pane and moves to a match.
   *   step "update"    query typed or bar reopened: first match in view
   *   step "next"      next match, wrapping
   *   step "previous"  previous match, wrapping
   *   step "refresh"   after a render: recount, keep position, don't scroll
   * Returns {count, current}.
   */
  function findInPane(query, step) {
    const changed = query !== find.query;
    find.query = query;
    find.matches = findRanges(query);
    const count = find.matches.length;
    if (!count) find.current = -1;
    else if (changed || find.current < 0) find.current = firstVisibleMatch();
    else if (step === "next") find.current = (find.current + 1) % count;
    else if (step === "previous") find.current = (find.current - 1 + count) % count;
    else find.current = Math.min(find.current, count - 1);
    paintFind();
    if (find.current >= 0 && step !== "refresh") revealMatch(find.matches[find.current]);
    return { count, current: find.current };
  }

  /** Ends the search; if `select`, the current match becomes the selection. */
  function endFind(select) {
    const current = find.matches[find.current];
    find.query = "";
    find.matches = [];
    find.current = -1;
    paintFind();
    if (select && current && !current.collapsed && content.contains(current.startContainer)) {
      content.focus();
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(current);
    }
  }

  const selectionText = () => window.getSelection().toString();

  window.viewmd = { render, format, caretLine, scrollToLine, find: findInPane, endFind, selectionText };

  post({ type: "ready" });
})();
