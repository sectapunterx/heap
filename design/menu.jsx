// Reusable Menu / Context Menu component
const { useEffect: mUseEffect, useState: mUseState, useRef: mUseRef, useLayoutEffect: mUseLayout } = React;

/**
 * <Menu> — generic floating menu used for context menus, dropdowns, profile selectors.
 *
 * Props:
 *   x, y                – preferred top-left in viewport coordinates
 *   anchor              – { rect, side: 'bottom-end' | 'bottom-start' | 'top-end' | 'top-start' }
 *                         alternative to x/y — positions relative to a DOM rect
 *   onClose             – called when user dismisses (outside click, Esc, item activation)
 *   items               – array of menu items (see below)
 *   width               – default 220
 *   minWidth            – default = width
 *
 * Item shapes:
 *   { separator: true }
 *   { header: "STRING" }
 *   { icon, label, hint, shortcut, action, danger, checked, disabled, submenu, keepOpen }
 */
function Menu({ x, y, anchor, items, onClose, width = 220, minWidth }) {
  const ref = mUseRef(null);
  const [openSubIdx, setOpenSubIdx] = mUseState(null);
  const [hoverIdx, setHoverIdx] = mUseState(-1);
  const [pos, setPos] = mUseState({ left: x ?? 0, top: y ?? 0 });

  // Position calc — anchor-based or x/y, clamped to viewport
  mUseLayout(() => {
    if (!ref.current) return;
    const w = ref.current.offsetWidth || width;
    const h = ref.current.offsetHeight || 0;
    const margin = 8;
    let left = x ?? 0;
    let top = y ?? 0;
    if (anchor && anchor.rect) {
      const r = anchor.rect;
      const side = anchor.side || "bottom-start";
      if (side === "bottom-end") { left = r.right - w; top = r.bottom + 6; }
      else if (side === "bottom-start") { left = r.left; top = r.bottom + 6; }
      else if (side === "top-end") { left = r.right - w; top = r.top - h - 6; }
      else if (side === "top-start") { left = r.left; top = r.top - h - 6; }
    }
    if (left + w > window.innerWidth - margin) left = window.innerWidth - w - margin;
    if (top + h > window.innerHeight - margin) top = window.innerHeight - h - margin;
    if (left < margin) left = margin;
    if (top < margin) top = margin;
    setPos({ left, top });
  }, [x, y, anchor, items]);

  mUseEffect(() => {
    const onDown = (e) => {
      if (ref.current && !ref.current.contains(e.target)) onClose();
    };
    const onKey = (e) => {
      if (e.key === "Escape") { e.stopPropagation(); onClose(); }
      else if (e.key === "ArrowDown") {
        e.preventDefault();
        const valid = items.map((it, i) => (it.separator || it.header || it.disabled) ? -1 : i).filter(i => i >= 0);
        const cur = valid.indexOf(hoverIdx);
        setHoverIdx(valid[(cur + 1) % valid.length] ?? valid[0]);
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        const valid = items.map((it, i) => (it.separator || it.header || it.disabled) ? -1 : i).filter(i => i >= 0);
        const cur = valid.indexOf(hoverIdx);
        setHoverIdx(valid[(cur - 1 + valid.length) % valid.length] ?? valid[valid.length - 1]);
      } else if (e.key === "Enter" && hoverIdx >= 0) {
        e.preventDefault();
        const it = items[hoverIdx];
        if (it && it.action) { it.action(); onClose(); }
      }
    };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [onClose, items, hoverIdx]);

  return ReactDOM.createPortal(
    <div
      className="cmenu"
      ref={ref}
      style={{
        left: pos.left + "px",
        top: pos.top + "px",
        width: width + "px",
        minWidth: (minWidth || width) + "px",
      }}
      onContextMenu={(e) => e.preventDefault()}
    >
      {items.map((it, i) => {
        if (it.separator) return <div key={i} className="cmenu-sep" />;
        if (it.header)    return <div key={i} className="cmenu-header">{it.header}</div>;
        const hasSub = Array.isArray(it.submenu) && it.submenu.length > 0;
        const isOpen = openSubIdx === i;
        const isHover = hoverIdx === i;
        return (
          <div
            key={i}
            className={
              "cmenu-item" +
              (it.danger ? " danger" : "") +
              (it.checked ? " checked" : "") +
              (it.disabled ? " disabled" : "") +
              (isHover ? " hover" : "") +
              (hasSub && isOpen ? " open" : "")
            }
            onMouseEnter={() => {
              if (it.disabled) return;
              setHoverIdx(i);
              setOpenSubIdx(hasSub ? i : null);
            }}
            onMouseLeave={() => { if (hasSub) {/* keep open on submenu hover */} }}
            onClick={(e) => {
              if (it.disabled) return;
              if (hasSub) { e.stopPropagation(); setOpenSubIdx(isOpen ? null : i); return; }
              if (it.action) it.action();
              if (!it.keepOpen) onClose();
            }}
          >
            <span className="cmenu-icon">
              {it.checked ? "✓" : (it.icon || "")}
            </span>
            <span className="cmenu-label">
              {it.label}
              {it.hint && <span className="cmenu-hint">{it.hint}</span>}
            </span>
            {it.shortcut && <span className="cmenu-shortcut mono">{it.shortcut}</span>}
            {hasSub && <span className="cmenu-arrow">›</span>}
            {hasSub && isOpen && (
              <div className="cmenu-submenu">
                {it.submenu.map((sub, j) => {
                  if (sub.separator) return <div key={j} className="cmenu-sep" />;
                  if (sub.header) return <div key={j} className="cmenu-header">{sub.header}</div>;
                  return (
                    <div
                      key={j}
                      className={
                        "cmenu-item" +
                        (sub.danger ? " danger" : "") +
                        (sub.checked ? " checked" : "") +
                        (sub.disabled ? " disabled" : "")
                      }
                      onClick={(e) => {
                        e.stopPropagation();
                        if (sub.disabled) return;
                        if (sub.action) sub.action();
                        onClose();
                      }}
                    >
                      <span className="cmenu-icon" style={sub.swatch ? {background: sub.swatch, borderRadius: "3px", width:"10px", height:"10px"} : null}>
                        {!sub.swatch && (sub.checked ? "✓" : (sub.icon || ""))}
                      </span>
                      <span className="cmenu-label">
                        {sub.label}
                        {sub.hint && <span className="cmenu-hint">{sub.hint}</span>}
                      </span>
                      {sub.shortcut && <span className="cmenu-shortcut mono">{sub.shortcut}</span>}
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        );
      })}
    </div>,
    document.body
  );
}

Object.assign(window, { Menu });
