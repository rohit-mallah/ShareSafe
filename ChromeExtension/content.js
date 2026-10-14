(() => {
  "use strict";
  const KEY = "__shareSafeCompanion";
  if (window[KEY]) { window[KEY].activate(); return; }

  // Visual thesis: quiet charcoal controls, readable type, one mint action.
  // Content: current tool, concise instruction, reversible cover controls.
  // Interaction: immediate blur with solid fallback; crisp selection; no reveal animation.
  const host = document.createElement("div");
  host.id = "sharesafe-companion-root";
  host.popover = "manual";
  for (const [property, value] of Object.entries({
    all: "initial", position: "fixed", inset: "0", width: "100%", height: "100%",
    display: "block", "pointer-events": "none", "z-index": "2147483647",
    opacity: "1", transform: "none", filter: "none", visibility: "visible",
    "color-scheme": "dark", isolation: "isolate", transition: "none", animation: "none"
  })) host.style.setProperty(property, value, "important");
  const shadow = host.attachShadow({ mode: "open" });
  shadow.innerHTML = `
    <style>
      :host { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      :host::backdrop { background: transparent !important; pointer-events: none !important; }
      * { box-sizing: border-box; }
      .mask { position: fixed; background: #14221d; opacity: 1; border: 0; border-radius: 0; pointer-events: none; }
      .mask[data-style="blur"][data-kind="area"] { background: transparent; backdrop-filter: blur(18px); }
      .mask[data-style="blur"][data-kind="element"] { background: transparent; }
      .mask[data-fallback="true"] { background: #14221d !important; backdrop-filter: none !important; }
      .outline { position: fixed; outline: 2px solid #a2e9ca; outline-offset: 1px; pointer-events: none; }
      .outline[hidden], .mask[hidden] { display: none; }
      .drag { position: fixed; background: #14221d; outline: 2px solid #a2e9ca; pointer-events: none; }
      .selector { position: fixed; inset: 0; background: transparent; pointer-events: auto; cursor: crosshair; touch-action: none; }
      .selector[hidden] { display: none; }
      .toolbar { position: fixed; top: 16px; left: 50%; transform: translateX(-50%); max-width: calc(100vw - 24px); padding: 9px; color: #ebf2ee; background: #17231f; border: 1px solid #3a4b42; border-radius: 12px; box-shadow: 0 8px 30px #0005; pointer-events: auto; font: 12px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
      .row { display: flex; align-items: center; gap: 4px; flex-wrap: wrap; }
      .brand { font-size: 11px; font-weight: 700; letter-spacing: .02em; margin: 0 9px 0 4px; white-space: nowrap; }
      .brand svg { vertical-align: -3px; margin-right: 5px; }
      button { font: inherit; font-weight: 600; border: 0; border-radius: 6px; padding: 8px 10px; color: #d4e1d9; background: transparent; cursor: pointer; white-space: nowrap; transition: background-color 100ms; }
      button:hover { background: #304238; }
      button[aria-pressed="true"] { background: #a2e9ca; color: #14251d; }
      button:disabled { opacity: .38; cursor: default; }
      button:focus-visible { outline: 2px solid #c3ffe1; outline-offset: 1px; }
      button[data-action="done"] { border-left: 1px solid #415247; border-radius: 0 6px 6px 0; margin-left: 4px; }
      .status { padding: 5px 5px 1px; color: #afc3b7; font-size: 11px; }
      @media (max-width: 480px) { .toolbar { left: 12px; transform: none; } .brand { width: 100%; } button { padding: 8px; } }
      @media (prefers-reduced-motion: reduce) { button { transition: none; } }
    </style>
    <div class="covers" aria-hidden="true"></div>
    <div class="selector" hidden aria-hidden="true"></div>
    <div class="outline" hidden aria-hidden="true"></div>
    <div class="toolbar" role="region" aria-label="ShareSafe controls">
      <div class="row">
        <span class="brand"><svg width="15" height="17" viewBox="0 0 15 17" aria-hidden="true"><path fill="none" stroke="#a2e9ca" stroke-width="1.5" d="M7.5 1.5 13.5 4v5c0 3-3 5.2-6 6.5C4.5 14.2 1.5 12 1.5 9V4Z"/></svg>ShareSafe</span>
        <button type="button" data-action="element" aria-pressed="false">Hide element</button>
        <button type="button" data-action="area" aria-pressed="false">Hide area</button>
        <button type="button" data-action="style" aria-pressed="false">Style: Blur</button>
        <button type="button" data-action="undo" disabled>Undo</button>
        <button type="button" data-action="clear" disabled>Clear</button>
        <button type="button" data-action="done">Done</button>
      </div>
      <div class="status" data-status role="status" aria-live="polite"></div>
    </div>`;
  const covers = shadow.querySelector(".covers");
  const selector = shadow.querySelector(".selector");
  const toolbar = shadow.querySelector(".toolbar");
  const outline = shadow.querySelector(".outline");
  const status = shadow.querySelector("[data-status]");
  const masks = [];
  let mode = null, hovered = null, drag = null, frame = 0, observer = null;
  let fullscreenGuard = null;
  let maskStyle = "blur";
  let observedRoots = new WeakSet();
  const buttons = Object.fromEntries([...shadow.querySelectorAll("button")].map(button => [button.dataset.action, button]));

  function mount(promote = false) {
    // The control surface must never descend from protected content or a
    // replaced fullscreen video/iframe. A manual popover gives it an independent
    // top-layer box while its DOM parent remains the document root.
    if (host.parentNode !== document.documentElement) document.documentElement.append(host);
    if (promote && host.matches(":popover-open")) host.hidePopover();
    if (!host.matches(":popover-open")) host.showPopover();
  }
  function inSubtree(element, ancestor) {
    for (let node = element; node; node = node.parentNode || node.host) if (node === ancestor) return true;
    return false;
  }
  function isControl(event) { return event.composedPath().includes(toolbar); }
  function candidate(event) {
    const element = event.composedPath().find(node => node instanceof Element);
    if (!element || inSubtree(element, host) || ["HTML", "BODY", "HEAD", "SCRIPT", "STYLE", "LINK", "META"].includes(element.tagName)) return null;
    return element;
  }
  function rectStyle(node, rect) {
    node.style.left = `${rect.left}px`;
    node.style.top = `${rect.top}px`;
    node.style.width = `${Math.max(0, rect.width)}px`;
    node.style.height = `${Math.max(0, rect.height)}px`;
  }
  function viewportRect(start, end) {
    const x1 = Math.max(0, Math.min(innerWidth, start.x));
    const y1 = Math.max(0, Math.min(innerHeight, start.y));
    const x2 = Math.max(0, Math.min(innerWidth, end.x));
    const y2 = Math.max(0, Math.min(innerHeight, end.y));
    return { left: Math.min(x1, x2), top: Math.min(y1, y2), width: Math.abs(x2 - x1), height: Math.abs(y2 - y1) };
  }
  function resizeAreas() {
    for (const mask of masks) if (mask.kind === "area") {
      rectStyle(mask.cover, viewportRect(
        { x: mask.rect.left, y: mask.rect.top },
        { x: mask.rect.left + mask.rect.width, y: mask.rect.top + mask.rect.height }
      ));
    }
  }
  function setStatus(message) { status.textContent = message; }
  function updateControls(message) {
    buttons.element.setAttribute("aria-pressed", String(mode === "element"));
    buttons.area.setAttribute("aria-pressed", String(mode === "area"));
    buttons.undo.disabled = buttons.clear.disabled = masks.length === 0;
    const count = `${masks.length} ${masks.length === 1 ? "cover" : "covers"}`;
    setStatus(message || (mode === "element" ? `Click an element to cover it · Esc finishes · ${count}` : mode === "area" ? `Drag an area to cover it · Esc finishes · ${count}` : `${count} stay covered · Select more, Undo, or Clear`));
  }
  function conceal(mask, element, deep = true) {
    if (!(element instanceof Element) || inSubtree(element, host)) return;
    if (!mask.originals.has(element)) mask.originals.set(element, element.getAttribute("style"));
    // Blur the complete source composite, retaining its real pixels and overflow.
    // Independent top-layer descendants escape ancestor filters: suppress those
    // until closed, with the overlay providing solid coverage at their bounds.
    const independent = element.matches(":modal, :popover-open");
    const solid = mask.style === "solid" || independent;
    if (element === mask.target || solid) {
      const rules = solid ? { transition: "none", animation: "none", opacity: "0" }
        : { transition: "none", animation: "none", filter: "blur(18px)" };
      for (const [property, value] of Object.entries(rules)) {
        if (element.style.getPropertyValue(property) !== value || element.style.getPropertyPriority(property) !== "important") element.style.setProperty(property, value, "important");
      }
    }
    if (deep && element.shadowRoot) {
      observeRoot(element.shadowRoot);
      for (const child of element.shadowRoot.children) conceal(mask, child);
    }
    if (deep) for (const child of element.children) conceal(mask, child);
  }
  function observeRoot(root) {
    if (!observer || observedRoots.has(root)) return;
    observer.observe(root, { childList: true, subtree: true, attributes: true, attributeFilter: ["style"] });
    observedRoots.add(root);
  }
  function ensureObserver() {
    if (observer) return;
    observer = new MutationObserver(records => {
      for (const record of records) {
        if (inSubtree(record.target, host)) continue;
        for (const mask of masks) {
          if (mask.kind !== "element" || !inSubtree(record.target, mask.target)) continue;
          if (record.type === "attributes") conceal(mask, record.target, false);
          else for (const node of record.addedNodes) if (node instanceof Element) conceal(mask, node);
        }
      }
    });
    observeRoot(document.documentElement);
  }
  function tick() {
    frame = 0;
    mount();
    for (const mask of masks) {
      if (mask.kind === "element") {
        mask.cover.hidden = !mask.target.isConnected;
        if (mask.target.isConnected) rectStyle(mask.cover, mask.target.getBoundingClientRect());
      }
    }
    if (mode === "element" && hovered && hovered.isConnected) rectStyle(outline, hovered.getBoundingClientRect());
    if (masks.some(mask => mask.kind === "element")) frame = requestAnimationFrame(tick);
  }
  function ensureFrame() { if (!frame) frame = requestAnimationFrame(tick); }
  function createCover(kind) {
    const cover = document.createElement("div");
    cover.className = "mask";
    cover.dataset.kind = kind;
    cover.dataset.style = kind === "transition" ? "solid" : maskStyle;
    covers.append(cover);
    return cover;
  }
  function addElement(target) {
    if (masks.some(mask => mask.kind === "element" && (inSubtree(target, mask.target) || inSubtree(mask.target, target)))) {
      updateControls("Already covered here · Select a separate element, or Undo first"); return;
    }
    const mask = { kind: "element", style: maskStyle, target, originals: new Map(), cover: createCover("element") };
    rectStyle(mask.cover, target.getBoundingClientRect());
    masks.push(mask);
    ensureObserver();
    conceal(mask, target);
    ensureFrame();
    updateControls();
  }
  function restore(mask) {
    mask.cover.remove();
    if (mask.kind === "element") for (const [element, original] of mask.originals) {
      restoreInline(element, original);
    }
  }
  function restoreInline(element, original) {
    if (original === null) {
      // Materialize an empty declaration before removal. Chromium can otherwise
      // lazily synchronize a dirty CSSStyleDeclaration into a new empty attr.
      element.setAttribute("style", "");
      element.removeAttribute("style");
    } else element.setAttribute("style", original);
  }
  function releaseTracking() {
    if (!masks.some(mask => mask.kind === "element")) {
      observer?.disconnect(); observer = null; observedRoots = new WeakSet();
      if (frame) cancelAnimationFrame(frame);
      frame = 0;
    }
    if (!masks.length) window.removeEventListener("resize", resizeAreas);
  }
  function undo() {
    const mask = masks.pop();
    if (mask) restore(mask);
    releaseTracking(); updateControls();
  }
  function clear() {
    observer?.disconnect(); observer = null; observedRoots = new WeakSet();
    while (masks.length) restore(masks.pop());
    releaseTracking(); setMode(null);
  }
  function swallow(event) { event.preventDefault(); event.stopImmediatePropagation(); }
  function move(event) {
    if (isControl(event)) { outline.hidden = true; return; }
    if (mode === "element") {
      hovered = candidate(event); outline.hidden = !hovered;
      if (hovered) rectStyle(outline, hovered.getBoundingClientRect());
    } else if (drag) {
      swallow(event);
      drag.end = { x: event.clientX, y: event.clientY };
      rectStyle(drag.cover, viewportRect(drag.start, drag.end));
    }
  }
  function down(event) {
    if (isControl(event)) return;
    swallow(event);
    if (event.button !== 0) return;
    if (event.type !== "pointerdown") return;
    if (mode === "area") {
      drag?.cover.remove();
      const start = { x: event.clientX, y: event.clientY };
      const cover = document.createElement("div"); cover.className = "drag"; covers.append(cover);
      drag = { start, end: start, cover, pointerId: event.pointerId };
      selector.setPointerCapture(event.pointerId);
      rectStyle(cover, viewportRect(start, start));
    }
  }
  function up(event) {
    if (isControl(event) && !drag) return;
    swallow(event);
    if (event.button !== 0) return;
    if (mode === "area" && drag) {
      const selection = drag; drag = null; selection.cover.remove();
      const rect = viewportRect(selection.start, { x: event.clientX, y: event.clientY });
      if (rect.width >= 4 && rect.height >= 4) {
        const cover = createCover("area"); rectStyle(cover, rect);
        masks.push({ kind: "area", style: maskStyle, cover, rect });
        window.addEventListener("resize", resizeAreas);
        updateControls();
      }
    }
  }
  function click(event) {
    if (isControl(event)) return;
    swallow(event);
    if (mode === "element" && event.type === "click" && event.button === 0) { const target = candidate(event); if (target) addElement(target); }
  }
  function cancelDrag() {
    if (drag && selector.hasPointerCapture(drag.pointerId)) selector.releasePointerCapture(drag.pointerId);
    drag?.cover.remove(); drag = null;
  }
  function key(event) {
    if (event.key === "Escape") { swallow(event); setMode(null); }
    else if ((event.key === "Enter" || event.key === " ") && !isControl(event)) swallow(event);
  }
  const selectionEvents = [
    ["pointermove", move], ["pointerdown", down], ["pointerup", up],
    ["click", click], ["auxclick", click], ["dblclick", click], ["contextmenu", click],
    ["mousedown", down], ["mouseup", event => { if (!isControl(event)) swallow(event); }],
    ["keydown", key], ["pointercancel", cancelDrag], ["blur", cancelDrag]
  ];
  function setMode(next) {
    for (const [name, handler] of selectionEvents) window.removeEventListener(name, handler, true);
    cancelDrag(); hovered = null; outline.hidden = true; mode = next;
    selector.hidden = mode !== "area";
    if (mode) for (const [name, handler] of selectionEvents) window.addEventListener(name, handler, { capture: true, passive: false });
    updateControls();
  }
  buttons.element.addEventListener("click", () => setMode("element"));
  buttons.area.addEventListener("click", () => setMode("area"));
  buttons.style.addEventListener("click", () => {
    maskStyle = maskStyle === "blur" ? "solid" : "blur";
    buttons.style.textContent = `Style: ${maskStyle === "blur" ? "Blur" : "Solid"}`;
    buttons.style.setAttribute("aria-pressed", String(maskStyle === "solid"));
    updateControls(`New selections use ${maskStyle} · Existing covers stay unchanged`);
  });
  buttons.undo.addEventListener("click", undo);
  buttons.clear.addEventListener("click", clear);
  buttons.done.addEventListener("click", () => setMode(null));
  function toolbarReachable() {
    const rect = buttons.clear.getBoundingClientRect();
    const hit = document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2);
    return hit === host || (hit && inSubtree(hit, host));
  }
  const fullscreen = () => {
    mount(true); resizeAreas(); ensureFrame();
    const source = document.fullscreenElement;
    if (!source && fullscreenGuard) {
      const guard = fullscreenGuard; fullscreenGuard = null;
      restoreInline(guard.source, guard.original);
      guard.cover.remove();
      updateControls("Page fullscreen ended to keep controls available · Covers remain");
    } else if (source && (masks.length || mode) && !toolbarReachable() && !fullscreenGuard) {
      // Chrome can paint a root popover above fullscreen while routing input only
      // inside the fullscreen subtree. Keep source pixels suppressed while leaving
      // that unsupported mode, rather than stranding an inert Clear control.
      const original = source.getAttribute("style");
      const cover = createCover("transition");
      rectStyle(cover, { left: 0, top: 0, width: innerWidth, height: innerHeight });
      fullscreenGuard = { source, original, cover };
      source.style.setProperty("transition", "none", "important");
      source.style.setProperty("opacity", "0", "important");
      setMode(null);
      setStatus("Leaving page fullscreen to keep controls available · Content stays covered");
      document.exitFullscreen().catch(() => setStatus("Press Esc to leave page fullscreen · Content stays covered"));
    }
  };
  document.addEventListener("fullscreenchange", fullscreen);
  // Other page top-layer surfaces can be added after ours. Promotion happens in
  // the same task after their opening algorithm, before the next rendering step.
  window.addEventListener("beforetoggle", event => {
    if (event.target !== host && event.newState === "open") queueMicrotask(() => {
      mount(true);
      for (const mask of masks) {
        if (mask.kind === "area") mask.cover.dataset.fallback = "true";
        else if (inSubtree(event.target, mask.target)) conceal(mask, event.target);
      }
      if (event.target instanceof HTMLDialogElement && event.target.matches(":modal")) {
        setMode(null);
        setStatus("Close the page dialog to use ShareSafe controls · Covers remain");
      }
    });
  }, true);
  window[KEY] = Object.freeze({
    activate() { mount(true); setMode("element"); },
    inspect() { return { mode, maskStyle, maskCount: masks.length, elementMasks: masks.filter(mask => mask.kind === "element").length, areaMasks: masks.filter(mask => mask.kind === "area").length }; }
  });
  window[KEY].activate();
})();
