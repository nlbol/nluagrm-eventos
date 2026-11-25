/* Comportamiento: paleta, countdown, slider y lightbox. Sin dependencias. */
(function () {
  "use strict";

  var root = document.documentElement;
  var body = document.body;
  var manual = {
    accent: body.dataset.accent || "",
    secondary: body.dataset.secondary || "",
    background: body.dataset.background || ""
  };

  /* --- Paleta fija: nunca se extraen colores del afiche --- */
  function hexToRgb(hex) {
    var value = String(hex).replace("#", "");
    if (!/^[0-9a-f]{6}$/i.test(value)) return null;
    return [parseInt(value.slice(0, 2), 16), parseInt(value.slice(2, 4), 16), parseInt(value.slice(4, 6), 16)];
  }
  function luminance(hex) {
    var rgb = hexToRgb(hex);
    if (!rgb) return 0;
    var f = function (v) {
      v /= 255;
      return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
    };
    return 0.2126 * f(rgb[0]) + 0.7152 * f(rgb[1]) + 0.0722 * f(rgb[2]);
  }
  function contrast(a, b) {
    var x = luminance(a), y = luminance(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
  }
  function applyTheme() {
    if (!manual.accent && !manual.secondary && !manual.background) return;
    var accent = manual.accent || "#00FFA3";
    var secondary = manual.secondary || "#915DF0";
    var background = manual.background || "#080D12";
    var values = {
      "--color-primary": accent,
      "--color-secondary": secondary,
      "--color-background": background,
      "--on-accent": contrast(accent, "#000000") >= contrast(accent, "#FFFFFF") ? "#000000" : "#FFFFFF"
    };
    if (contrast("#FFFFFF", background) < 4.5) {
      values["--color-text"] = "#0B1020";
      values["--color-muted"] = "rgba(11, 16, 32, 0.75)";
      values["--color-glass"] = "rgba(11, 16, 32, 0.05)";
      values["--color-glass-border"] = "rgba(11, 16, 32, 0.22)";
    }
    Object.keys(values).forEach(function (key) { root.style.setProperty(key, values[key]); });
  }

  /* --- Countdown --- */
  function zonedNow(tz) {
    var now = new Date();
    if (!tz) return now;
    try {
      var parts = new Intl.DateTimeFormat("en-US", {
        timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit",
        hour: "2-digit", minute: "2-digit", second: "2-digit", hourCycle: "h23"
      }).formatToParts(now).reduce(function (acc, p) { acc[p.type] = p.value; return acc; }, {});
      var hour = parts.hour === "24" ? "00" : parts.hour;
      return new Date(parts.year + "-" + parts.month + "-" + parts.day + "T" + hour + ":" + parts.minute + ":" + parts.second + "Z");
    } catch (error) { return now; }
  }
  function countdown() {
    var holder = document.querySelector("[data-countdown]");
    if (!holder) return;
    var live = document.getElementById("countdown-live");
    var tz = body.dataset.tz;
    var startRaw = body.dataset.date + "T" + body.dataset.time + ":00";
    var start = new Date(tz ? startRaw + "Z" : startRaw).getTime();
    if (!isFinite(start)) return;

    var end = 0;
    if (body.dataset.endDate && body.dataset.endTime) {
      var endRaw = body.dataset.endDate + "T" + body.dataset.endTime + ":00";
      var parsedEnd = new Date(tz ? endRaw + "Z" : endRaw).getTime();
      if (isFinite(parsedEnd) && parsedEnd > start) end = parsedEnd;
    }
    var starting = Number(body.dataset.startingDuration);
    if (!isFinite(starting) || starting < 0) starting = 0;
    var lastAnnouncement = "";

    function announce(text) {
      if (!live || text === lastAnnouncement) return;
      lastAnnouncement = text;
      live.textContent = text;
    }
    function setBoxes(diff) {
      holder.textContent = "";
      var lead = document.createElement("span");
      lead.className = "count__lead";
      lead.textContent = "Faltan";
      holder.appendChild(lead);
      var units = [["días", Math.floor(diff / 86400)], ["horas", Math.floor(diff % 86400 / 3600)],
                   ["min", Math.floor(diff % 3600 / 60)], ["seg", diff % 60]];
      units.forEach(function (unit) {
        var box = document.createElement("div");
        box.className = "count";
        var value = document.createElement("strong");
        var label = document.createElement("span");
        value.textContent = unit[1];
        label.textContent = unit[0];
        box.appendChild(value); box.appendChild(label); holder.appendChild(box);
      });
      announce("Faltan " + units[0][1] + " días, " + units[1][1] + " horas, " + units[2][1] + " minutos");
    }
    function setState(text, modifier) {
      if (holder.firstChild && holder.firstChild.className === "count__done" &&
          holder.firstChild.textContent === text) return;
      holder.textContent = "";
      var done = document.createElement("span");
      done.className = "count__done" + (modifier ? " count__done--" + modifier : "");
      done.textContent = text;
      holder.appendChild(done);
      announce(text);
    }
    function tick() {
      var now = zonedNow(tz).getTime();
      if (!isFinite(now)) return;
      if (end && now >= end) { setState("FIN DEL EVENTO", "finished"); return; }
      if (now < start) { setBoxes(Math.floor((start - now) / 1000)); return; }
      if (now < start + starting * 1000) { setState("INICIANDO"); return; }
      setState("EVENTO EN CURSO", "running");
    }
    tick();
    window.setInterval(tick, 1000);
  }

  /* --- Lightbox --- */
  var lightbox = document.getElementById("lightbox");
  var lbImage = document.getElementById("lightbox-image");
  var lbCaption = document.getElementById("lightbox-caption");
  var lbClose = document.getElementById("lightbox-close");
  var lbPrev = document.getElementById("lightbox-prev");
  var lbNext = document.getElementById("lightbox-next");
  var items = [];
  var current = 0;
  var lastFocus = null;

  function showItem() {
    if (!items.length) return;
    var item = items[current];
    lbImage.src = item.src;
    lbImage.alt = item.alt || "";
    lbCaption.textContent = item.caption || "";
    var multiple = items.length > 1;
    lbPrev.hidden = !multiple;
    lbNext.hidden = !multiple;
  }
  function openLightbox(images, index) {
    items = images.filter(function (item) { return item && item.src; });
    if (!items.length || !lightbox) return;
    current = Math.max(0, Math.min(index || 0, items.length - 1));
    lastFocus = document.activeElement;
    lightbox.hidden = false;
    body.classList.add("is-locked");
    showItem();
    lbClose.focus();
  }
  function closeLightbox() {
    if (!lightbox || lightbox.hidden) return;
    lightbox.hidden = true;
    lbImage.removeAttribute("src");
    lbImage.alt = "";
    lbCaption.textContent = "";
    body.classList.remove("is-locked");
    if (lastFocus && lastFocus.focus) lastFocus.focus();
    lastFocus = null;
  }
  function step(delta) {
    if (!items.length) return;
    current = (current + delta + items.length) % items.length;
    showItem();
  }

  /* --- Slider --- */
  function slider() {
    var rootEl = document.getElementById("slider");
    var track = document.getElementById("slider-track");
    if (!rootEl || !track || !track.children.length) return;
    var slides = Array.prototype.slice.call(track.children);
    var dots = document.getElementById("slider-dots");
    var live = document.getElementById("slider-live");
    var toggle = document.getElementById("slider-toggle");
    var interval = Math.max(1000, Number(body.dataset.interval) || 5000);
    var reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    var index = 0;
    var timer = null;
    var pausedByUser = false;
    var pausedByHover = false;
    var drag = null;

    var images = slides.map(function (slide, i) {
      var img = slide.querySelector("img");
      if (!img) return { src: "", alt: "", caption: "" };
      var caption = slide.querySelector("figcaption");
      return { src: img.currentSrc || img.src, alt: img.alt || "Imagen " + (i + 1), caption: caption ? caption.textContent : "" };
    }).filter(function (item) { return item.src; });

    slides.forEach(function (slide, i) {
      var button = slide.querySelector("button");
      if (button) button.addEventListener("click", function () {
        if (!drag) openLightbox(images, i);
      });
      var img = slide.querySelector("img");
      if (img) img.addEventListener("error", function () { slide.hidden = true; });
      if (dots) {
        var dot = document.createElement("button");
        dot.type = "button";
        dot.setAttribute("aria-label", "Ir a la imagen " + (i + 1));
        dot.addEventListener("click", function () { go(i, true); });
        dots.appendChild(dot);
      }
    });
    if (slides.length < 2) {
      ["slider-prev", "slider-next", "slider-toggle", "slider-dots"].forEach(function (id) {
        var node = document.getElementById(id);
        if (node) node.hidden = true;
      });
    }

    function canPlay() {
      return !reduced && slides.length > 1 && !pausedByUser && !pausedByHover && !document.hidden;
    }
    function stop() { if (timer !== null) { clearInterval(timer); timer = null; } }
    function start() {
      stop();
      if (canPlay()) timer = setInterval(function () { go(index + 1, false); }, interval);
    }
    function go(position, manual) {
      index = (position + slides.length) % slides.length;
      track.style.transform = "translateX(" + (-index * 100) + "%)";
      if (dots) Array.prototype.forEach.call(dots.children, function (dot, i) {
        if (i === index) dot.setAttribute("aria-current", "true");
        else dot.removeAttribute("aria-current");
      });
      if (live) live.textContent = "Imagen " + (index + 1) + " de " + slides.length;
      if (toggle) {
        toggle.textContent = pausedByUser ? "Reanudar" : "Pausar";
        toggle.setAttribute("aria-pressed", pausedByUser ? "true" : "false");
        toggle.setAttribute("aria-label", pausedByUser ? "Reanudar reproducción automática" : "Pausar reproducción automática");
      }
      if (manual) start();
    }

    var prev = document.getElementById("slider-prev");
    var next = document.getElementById("slider-next");
    if (prev) prev.addEventListener("click", function () { go(index - 1, true); });
    if (next) next.addEventListener("click", function () { go(index + 1, true); });
    if (toggle) toggle.addEventListener("click", function () { pausedByUser = !pausedByUser; start(); go(index, false); });
    rootEl.addEventListener("mouseenter", function () { pausedByHover = true; start(); });
    rootEl.addEventListener("mouseleave", function () { pausedByHover = false; start(); });
    rootEl.addEventListener("focusin", function () { pausedByHover = true; start(); });
    rootEl.addEventListener("focusout", function (event) {
      if (!rootEl.contains(event.relatedTarget)) { pausedByHover = false; start(); }
    });
    rootEl.addEventListener("keydown", function (event) {
      if (event.key === "ArrowLeft") { event.preventDefault(); go(index - 1, true); }
      else if (event.key === "ArrowRight") { event.preventDefault(); go(index + 1, true); }
      else if (event.key === "Home") { event.preventDefault(); go(0, true); }
      else if (event.key === "End") { event.preventDefault(); go(slides.length - 1, true); }
    });
    document.addEventListener("visibilitychange", start);

    var viewport = track.parentElement;
    viewport.addEventListener("pointerdown", function (event) {
      if (event.pointerType === "mouse" && event.button !== 0) return;
      drag = { x: event.clientX };
      track.classList.add("is-dragging");
    });
    window.addEventListener("pointermove", function (event) {
      if (!drag) return;
      var dx = event.clientX - drag.x;
      if (Math.abs(dx) > 6) track.style.transform = "translateX(calc(" + (-index * 100) + "% + " + dx + "px))";
    });
    window.addEventListener("pointerup", function (event) {
      if (!drag) return;
      var dx = event.clientX - drag.x;
      drag = null;
      track.classList.remove("is-dragging");
      if (Math.abs(dx) > 45) go(index + (dx < 0 ? 1 : -1), true);
      else go(index, false);
    });
    window.addEventListener("pointercancel", function () {
      drag = null;
      track.classList.remove("is-dragging");
      go(index, false);
    });
    go(0, false);
    start();
  }

  /* --- Cableado --- */
  if (lbClose) lbClose.addEventListener("click", closeLightbox);
  if (lbPrev) lbPrev.addEventListener("click", function () { step(-1); });
  if (lbNext) lbNext.addEventListener("click", function () { step(1); });
  if (lightbox) lightbox.addEventListener("click", function (event) {
    if (event.target.hasAttribute("data-close")) closeLightbox();
  });
  document.addEventListener("keydown", function (event) {
    if (!lightbox || lightbox.hidden) return;
    if (event.key === "Escape") { event.preventDefault(); closeLightbox(); }
    else if (event.key === "ArrowLeft") { event.preventDefault(); step(-1); }
    else if (event.key === "ArrowRight") { event.preventDefault(); step(1); }
    else if (event.key === "Tab") {
      var focusables = [lbClose, lbPrev, lbNext].filter(function (node) { return node && !node.hidden; });
      if (!focusables.length) return;
      var first = focusables[0], last = focusables[focusables.length - 1];
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
    }
  });

  var posterButton = document.querySelector(".poster__open");
  if (posterButton) {
    var posterImage = document.getElementById("poster-image");
    posterButton.addEventListener("click", function () {
      openLightbox([{ src: posterImage.currentSrc || posterImage.src, alt: posterImage.alt, caption: "" }], 0);
    });
  }

  applyTheme();
  countdown();
  slider();
})();
