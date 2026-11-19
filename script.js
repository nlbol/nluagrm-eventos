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

  /* --- Paleta derivada del afiche --- */
  function hexToRgb(hex) {
    var value = String(hex).replace("#", "");
    if (!/^[0-9a-f]{6}$/i.test(value)) return null;
    return [parseInt(value.slice(0, 2), 16), parseInt(value.slice(2, 4), 16), parseInt(value.slice(4, 6), 16)];
  }
  function rgbToHex(r, g, b) {
    var part = function (n) { return Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, "0"); };
    return "#" + part(r) + part(g) + part(b);
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
  function mix(a, b, amount) {
    var x = hexToRgb(a) || [80, 120, 255];
    var y = hexToRgb(b) || [10, 15, 30];
    return rgbToHex(x[0] + (y[0] - x[0]) * amount, x[1] + (y[1] - x[1]) * amount, x[2] + (y[2] - x[2]) * amount);
  }
  function saturation(hex) {
    var rgb = hexToRgb(hex);
    if (!rgb) return 0;
    var max = Math.max(rgb[0], rgb[1], rgb[2]);
    var min = Math.min(rgb[0], rgb[1], rgb[2]);
    return max ? (max - min) / max : 0;
  }
  function rgbToHsl(rgb) {
    var r = rgb[0] / 255, g = rgb[1] / 255, b = rgb[2] / 255;
    var max = Math.max(r, g, b), min = Math.min(r, g, b), delta = max - min;
    var l = (max + min) / 2, h = 0, s = 0;
    if (delta) {
      s = l > 0.5 ? delta / (2 - max - min) : delta / (max + min);
      if (max === r) h = ((g - b) / delta + (g < b ? 6 : 0)) / 6;
      else if (max === g) h = ((b - r) / delta + 2) / 6;
      else h = ((r - g) / delta + 4) / 6;
    }
    return [h, s, l];
  }
  function hslToHex(h, s, l) {
    function channel(n) {
      var k = (n + h * 12) % 12;
      return l - s * Math.min(l, 1 - l) * Math.max(-1, Math.min(k - 3, 9 - k, 1));
    }
    return rgbToHex(channel(0) * 255, channel(8) * 255, channel(4) * 255);
  }
  // Aclara manteniendo tono y saturación hasta lograr contraste legible.
  function readable(color, background, target) {
    var rgb = hexToRgb(color);
    if (!rgb) return color;
    var hsl = rgbToHsl(rgb);
    var sat = Math.max(0.45, hsl[1]);
    var candidate = color;
    for (var l = hsl[2]; l <= 0.95; l += 0.04) {
      candidate = hslToHex(hsl[0], sat, l);
      if (contrast(candidate, background) >= target) return candidate;
    }
    return candidate;
  }
  function applyPalette(p) {
    var background = p.background;
    var text = contrast("#ffffff", background) >= contrast("#101525", background) ? "#ffffff" : "#101525";
    var accent = readable(p.accent, background, 4.5);
    var onAccent = contrast(accent, "#08110a") >= 4.5 ? "#08110a" : "#ffffff";
    var secondary = readable(p.secondary, background, 2.2);
    for (var i = 0; i < 12 && contrast("#ffffff", secondary) < 4.5; i++) {
      secondary = mix(secondary, "#000000", 0.08);
    }
    var values = {
      "--accent": accent,
      "--on-accent": onAccent,
      "--accent-secondary": secondary,
      "--background": background,
      "--surface": mix(background, p.secondary, 0.12),
      "--text": text,
      "--muted": mix(text, background, 0.38),
      "--border": text === "#ffffff" ? "rgba(255,255,255,0.14)" : "rgba(16,26,52,0.14)",
      "--glass": text === "#ffffff" ? "rgba(255,255,255,0.07)" : "rgba(255,255,255,0.62)",
      "--shadow": text === "#ffffff" ? "rgba(2,6,18,0.55)" : "rgba(31,45,84,0.16)"
    };
    Object.keys(values).forEach(function (key) { root.style.setProperty(key, values[key]); });
  }
  function fallbackPalette() {
    return { accent: "#a3e635", secondary: "#4f7cff", background: "#0a0f1d" };
  }
  function sampleImage(image) {
    return new Promise(function (resolve) {
      try {
        var canvas = document.createElement("canvas");
        canvas.width = 40; canvas.height = 40;
        var ctx = canvas.getContext("2d", { willReadFrequently: true });
        if (!ctx) return resolve([]);
        ctx.drawImage(image, 0, 0, 40, 40);
        var data = ctx.getImageData(0, 0, 40, 40).data;
        var buckets = new Map();
        for (var i = 0; i < data.length; i += 16) {
          if (data[i + 3] < 200) continue;
          var key = Math.round(data[i] / 32) + "," + Math.round(data[i + 1] / 32) + "," + Math.round(data[i + 2] / 32);
          var entry = buckets.get(key);
          if (entry) { entry.n++; entry.r += data[i]; entry.g += data[i + 1]; entry.b += data[i + 2]; }
          else buckets.set(key, { n: 1, r: data[i], g: data[i + 1], b: data[i + 2] });
        }
        resolve(Array.from(buckets.values()).sort(function (a, b) { return b.n - a.n; })
          .map(function (e) { return { hex: rgbToHex(e.r / e.n, e.g / e.n, e.b / e.n), n: e.n }; }));
      } catch (error) { resolve([]); }
    });
  }
  function loadTheme() {
    var base = fallbackPalette();
    if (manual.accent || manual.secondary || manual.background) {
      applyPalette({
        accent: manual.accent || base.accent,
        secondary: manual.secondary || base.secondary,
        background: manual.background || base.background
      });
      return Promise.resolve();
    }
    applyPalette(base);
    var image = document.getElementById("poster-image");
    if (!image) return Promise.resolve();
    function derive() {
      return sampleImage(image).then(function (colors) {
        if (!colors.length) return;
        var primary = colors[0].hex;
        var candidates = colors.slice(0, 14).filter(function (c) { return c.n >= 2; });
        var vivid = candidates.slice().sort(function (a, b) {
          return saturation(b.hex) * Math.sqrt(b.n) - saturation(a.hex) * Math.sqrt(a.n);
        })[0];
        var secondary = (colors.slice(0, 10).find(function (c) {
          return c.hex !== primary && contrast(c.hex, primary) > 1.3;
        }) || {}).hex || base.secondary;
        applyPalette({
          accent: vivid ? vivid.hex : base.accent,
          secondary: secondary,
          background: mix(primary, "#070b16", 0.9)
        });
      });
    }
    if (image.complete && image.naturalWidth) return derive();
    return new Promise(function (resolve) {
      image.addEventListener("load", function () { derive().then(resolve); }, { once: true });
      image.addEventListener("error", resolve, { once: true });
    });
  }

  /* --- Countdown --- */
  function zonedNow(tz) {
    var now = new Date();
    if (!tz) return now;
    try {
      var parts = new Intl.DateTimeFormat("en-US", {
        timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit",
        hour: "2-digit", minute: "2-digit", second: "2-digit", hour12: false
      }).formatToParts(now).reduce(function (acc, p) { acc[p.type] = p.value; return acc; }, {});
      return new Date(parts.year + "-" + parts.month + "-" + parts.day + "T" + parts.hour + ":" + parts.minute + ":" + parts.second + "Z");
    } catch (error) { return now; }
  }
  function countdown() {
    var holder = document.querySelector("[data-countdown]");
    if (!holder) return;
    var raw = body.dataset.date + "T" + body.dataset.time + ":00";
    var target = new Date(body.dataset.tz ? raw + "Z" : raw).getTime();
    if (!isFinite(target)) return;
    function tick() {
      var diff = Math.floor((target - zonedNow(body.dataset.tz).getTime()) / 1000);
      if (diff <= 0) {
        holder.textContent = "";
        var done = document.createElement("span");
        done.className = "count__done";
        done.textContent = "El evento ya comenzó";
        holder.appendChild(done);
        return;
      }
      var units = [["días", Math.floor(diff / 86400)], ["horas", Math.floor(diff % 86400 / 3600)],
                   ["min", Math.floor(diff % 3600 / 60)], ["seg", diff % 60]];
      if (holder.children.length !== units.length) {
        holder.textContent = "";
        units.forEach(function (unit) {
          var box = document.createElement("div");
          box.className = "count";
          var value = document.createElement("strong");
          var label = document.createElement("span");
          label.textContent = unit[0];
          box.appendChild(value); box.appendChild(label); holder.appendChild(box);
        });
      }
      units.forEach(function (unit, index) { holder.children[index].firstChild.textContent = unit[1]; });
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
      return { src: img.src, alt: img.alt || "Imagen " + (i + 1), caption: caption ? caption.textContent : "" };
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
      openLightbox([{ src: posterImage.src, alt: posterImage.alt, caption: "" }], 0);
    });
  }

  loadTheme();
  countdown();
  slider();
})();
