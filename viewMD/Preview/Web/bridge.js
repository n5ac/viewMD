// bridge.js: the preview page's side of the Swift <-> page bridge.
//
// Swift calls window.viewmd.render(payload) with the rendered blocks; the
// page posts messages back through window.webkit.messageHandlers.viewmd:
//   {type: "ready"}                     page loaded, send the first render
//   {type: "focus"}                     the rendered pane gained focus
//   {type: "openLink", href}            the user opened a link
//
// Rendering patches the DOM instead of replacing it: blocks that didn't
// change keep their DOM nodes (and so the scroll position and any
// selection), and only the changed run in the middle is rebuilt.
(() => {
  "use strict";

  const content = document.getElementById("content");

  /** Sends a message to Swift. */
  function post(message) {
    window.webkit.messageHandlers.viewmd.postMessage(message);
  }

  /** Builds DOM nodes from an HTML string (one top-level element per block). */
  function nodesFromHTML(html) {
    const template = document.createElement("template");
    template.innerHTML = html;
    return Array.from(template.content.children);
  }

  /** Applies highlight.js to code blocks inside `root` that name a language. */
  function highlightCode(root) {
    if (!window.hljs) return;
    root.querySelectorAll("pre code[class*='language-']").forEach((code) => {
      const language = code.className.replace(/^.*language-(\S+).*$/, "$1");
      if (hljs.getLanguage(language)) hljs.highlightElement(code);
    });
  }

  /** Creates the DOM node for one rendered block and records its source. */
  function makeBlockNode(block) {
    const node = nodesFromHTML(block.html)[0] || document.createElement("div");
    node.__viewmdHTML = block.html;
    highlightCode(node);
    return node;
  }

  /**
   * Patches #content to show `blocks`.
   *
   * Existing nodes are matched to new blocks by their rendered HTML,
   * ignoring the data-src line numbers (they shift when lines are added
   * above), from the front and from the back. Matched nodes are kept and get
   * updated data-src values; the unmatched run in the middle is replaced.
   */
  function patch(blocks) {
    const nodes = Array.from(content.children);
    const strip = (html) => (html || "").replace(/ data-src="\d+-\d+"/, "");
    const same = (node, block) => node.__viewmdHTML !== undefined && strip(node.__viewmdHTML) === strip(block.html);

    let prefix = 0;
    while (prefix < nodes.length && prefix < blocks.length && same(nodes[prefix], blocks[prefix])) prefix++;
    let suffix = 0;
    while (suffix < nodes.length - prefix && suffix < blocks.length - prefix &&
           same(nodes[nodes.length - 1 - suffix], blocks[blocks.length - 1 - suffix])) suffix++;

    // Update line tags on kept nodes.
    const keep = (node, block) => {
      node.setAttribute("data-src", block.src);
      node.__viewmdHTML = block.html;
    };
    for (let i = 0; i < prefix; i++) keep(nodes[i], blocks[i]);
    for (let i = 0; i < suffix; i++) keep(nodes[nodes.length - 1 - i], blocks[blocks.length - 1 - i]);

    // Replace the middle.
    const anchor = suffix > 0 ? nodes[nodes.length - suffix] : null;
    for (let i = prefix; i < nodes.length - suffix; i++) nodes[i].remove();
    for (let i = prefix; i < blocks.length - suffix; i++) content.insertBefore(makeBlockNode(blocks[i]), anchor);
  }

  /** Scrolls to the element a `#fragment` names, if any. */
  function scrollToFragment(fragment) {
    const id = decodeURIComponent(fragment.replace(/^#/, ""));
    const target = document.getElementById(id);
    if (target) target.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  // Links: open through Swift (which routes them to the browser, viewMD or
  // the file's app). Fragment links scroll within the page.
  document.addEventListener("click", (event) => {
    const link = event.target.closest && event.target.closest("a[href]");
    if (!link) return;
    event.preventDefault();
    const href = link.getAttribute("href");
    if (href.startsWith("#")) {
      scrollToFragment(href);
    } else {
      post({ type: "openLink", href: link.href });
    }
  });

  document.addEventListener("focusin", () => post({ type: "focus" }));

  window.viewmd = {
    /**
     * Shows a rendered document.
     * @param {{blocks: {src: string, html: string}[], placeholder?: string}} payload
     */
    render(payload) {
      patch(payload.blocks);
      content.setAttribute("data-placeholder", payload.placeholder || "");
    },
  };

  post({ type: "ready" });
})();
