// Downix: collects the links inside the text the user highlighted, so the context
// menu can offer "Download N links" (like IDM's "Download all links").
(function () {
  if (window.__downixSelection) return;
  window.__downixSelection = true;
  var MAX_LINKS = 3000;
  var decided = null;   // what the last right-click offered, so the click uses the same list

  function collect() {
    var sel = window.getSelection && window.getSelection();
    if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return [];
    var out = [], seen = Object.create(null);
    function add(href, text) {
      if (!href || out.length >= MAX_LINKS) return;
      if (!/^https?:\/\//i.test(href)) return;
      if (seen[href]) return;
      seen[href] = true;
      out.push({ url: href, text: String(text || '').replace(/\s+/g, ' ').trim().slice(0, 160) });
    }
    function anchorText(a) {
      var t = a.textContent;
      if (!t || !t.trim()) {
        var img = a.querySelector && a.querySelector('img[alt]');
        t = (img && img.alt) || a.title || '';
      }
      return t;
    }
    var here = location.href.split('#')[0];
    for (var i = 0; i < sel.rangeCount; i++) {
      var range = sel.getRangeAt(i);
      var node = range.commonAncestorContainer;
      var scope = node.nodeType === 1 ? node : node.parentElement;
      if (!scope) continue;
      var closest = scope.closest && scope.closest('a[href]');
      if (closest) add(closest.href, anchorText(closest));
      var anchors = scope.querySelectorAll ? scope.querySelectorAll('a[href]') : [];
      for (var j = 0; j < anchors.length; j++) {
        var a = anchors[j];
        var raw = a.getAttribute('href') || '';
        if (raw.charAt(0) === '#' || a.href.split('#')[0] === here && raw.indexOf('#') !== -1) continue;
        var inside = false;
        try {
          var nr = document.createRange();
          nr.selectNodeContents(a);
          // the highlight must really overlap the link, not merely touch it
          inside = range.compareBoundaryPoints(Range.END_TO_START, nr) < 0 &&
                   range.compareBoundaryPoints(Range.START_TO_END, nr) > 0;
        } catch (e) { inside = false; }
        if (inside) add(a.href, anchorText(a));
      }
    }
    // Plain-text addresses inside the highlighted text count too.
    var text = sel.toString();
    var urls = text.match(/https?:\/\/[^\s<>"'`]+/gi) || [];
    for (var k = 0; k < urls.length; k++) add(urls[k].replace(/[).,;:!?\]]+$/, ''), '');
    return out;
  }

  document.addEventListener('contextmenu', function (event) {
    var count = 0, onLink = false;
    try {
      var target = event.target;
      var anchor = target && target.closest ? target.closest('a[href]') : null;
      onLink = !!anchor;
      var links = collect();
      // Right-clicking a link that is not part of the highlight means "this link only".
      if (anchor && links.length > 1) {
        var inList = links.some(function (l) { return l.url === anchor.href; });
        if (!inList) links = [];
      }
      decided = links;
      count = links.length;
    } catch (e) { decided = []; }
    try {
      chrome.runtime.sendMessage({ type: 'downixSelectionInfo', count: count, onLink: onLink });
    } catch (e) { /* extension was reloaded */ }
  }, true);

  try {
    chrome.runtime.onMessage.addListener(function (message, sender, sendResponse) {
      if (message && message.type === 'downixCollectSelection') {
        sendResponse({ links: decided && decided.length ? decided : collect() });
      }
      return false;
    });
  } catch (e) { /* extension context invalidated */ }
})();
