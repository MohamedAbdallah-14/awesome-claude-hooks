// awesome-claude-hooks browser
// Vanilla JS, no deps. Loads hooks.registry.json (copied to ./registry.json by
// the Pages workflow / `make pages-serve`) and renders a filterable card grid.

(function () {
  "use strict";

  var GH_BASE = "https://github.com/MohamedAbdallah-14/awesome-claude-hooks/blob/main/";
  var DOC_BASE = "https://github.com/MohamedAbdallah-14/awesome-claude-hooks/blob/main/docs/hooks/";

  // Hooks that have a hero doc under docs/hooks/<id>.md. Hard-coded so we
  // don't need a second fetch. Keep in sync with docs/hooks/.
  var HERO_DOCS = {
    "ai-code-review": 1, "ai-migration-safety": 1, "ai-security-scan": 1,
    "auto-approve-readonly": 1, "auto-format-on-save": 1, "aws-prod-guard": 1,
    "block-dangerous-bash": 1, "block-secrets": 1, "block-system-paths": 1,
    "check-npm-audit": 1, "db-migration-guard": 1, "eslint-gate": 1,
    "kubernetes-prod-guard": 1, "protect-dotenv": 1, "protect-main-branch": 1,
    "scan-sql-injection": 1, "terraform-destroy-guard": 1, "tsc-check": 1,
    "validate-commit-message": 1, "validate-json-yaml": 1
  };

  var RISK_ORDER = ["passive", "contextual", "modifying", "blocking", "networked", "privileged"];

  var state = {
    hooks: [],
    profilesMap: {},     // hookId -> [profileName]
    filters: {
      q: "",
      sort: "id",
      cat: new Set(),
      event: new Set(),
      risk: new Set(),
      profile: new Set(),
      tests: false,
      blocks: false,
      network: false,
      writes: false
    }
  };

  var $ = function (sel) { return document.querySelector(sel); };

  function escapeHTML(s) {
    if (s == null) return "";
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function fetchRegistry() {
    return fetch("registry.json", { cache: "no-cache" })
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        return r.json();
      });
  }

  function buildProfilesMap(profiles) {
    var map = {};
    Object.keys(profiles || {}).forEach(function (name) {
      (profiles[name] || []).forEach(function (id) {
        if (!map[id]) map[id] = [];
        if (map[id].indexOf(name) === -1) map[id].push(name);
      });
    });
    return map;
  }

  function uniqueSorted(arr) {
    var seen = {};
    var out = [];
    arr.forEach(function (v) {
      if (v == null || v === "") return;
      if (!seen[v]) { seen[v] = 1; out.push(v); }
    });
    out.sort();
    return out;
  }

  function countBy(hooks, key) {
    var counts = {};
    hooks.forEach(function (h) {
      var v = h[key];
      if (v == null || v === "") return;
      counts[v] = (counts[v] || 0) + 1;
    });
    return counts;
  }

  function renderCheckList(containerSel, name, values, counts) {
    var c = document.querySelector(containerSel);
    while (c.firstChild) c.removeChild(c.firstChild);
    values.forEach(function (v) {
      var id = "f-" + name + "-" + v.replace(/[^a-z0-9]/gi, "_");
      var label = document.createElement("label");
      label.className = "check";
      label.setAttribute("for", id);
      var input = document.createElement("input");
      input.type = "checkbox";
      input.name = name;
      input.value = v;
      input.id = id;
      var span = document.createElement("span");
      span.textContent = v;
      var count = document.createElement("span");
      count.className = "count";
      count.textContent = counts[v] != null ? counts[v] : 0;
      label.appendChild(input);
      label.appendChild(span);
      label.appendChild(count);
      c.appendChild(label);
    });
  }

  function buildFilters() {
    var hooks = state.hooks;

    var cats = uniqueSorted(hooks.map(function (h) { return h.category; }));
    var events = uniqueSorted(hooks.map(function (h) { return h.event; }));
    var risks = RISK_ORDER.filter(function (r) {
      return hooks.some(function (h) { return h.risk_level === r; });
    });
    var profiles = Object.keys(state.profilesMap).reduce(function (acc, hookId) {
      state.profilesMap[hookId].forEach(function (p) {
        if (acc.indexOf(p) === -1) acc.push(p);
      });
      return acc;
    }, []);
    profiles.sort();

    var catCounts = countBy(hooks, "category");
    var eventCounts = countBy(hooks, "event");
    var riskCounts = countBy(hooks, "risk_level");

    var profileCounts = {};
    Object.keys(state.profilesMap).forEach(function (id) {
      state.profilesMap[id].forEach(function (p) {
        profileCounts[p] = (profileCounts[p] || 0) + 1;
      });
    });

    renderCheckList("#cat-options", "cat", cats, catCounts);
    renderCheckList("#event-options", "event", events, eventCounts);
    renderCheckList("#risk-options", "risk", risks, riskCounts);
    renderCheckList("#profile-options", "profile", profiles, profileCounts);
  }

  function readFiltersFromForm() {
    var f = $("#filters");
    state.filters.q = (f.q.value || "").trim().toLowerCase();
    state.filters.sort = f.sort.value;

    function collect(name) {
      var s = new Set();
      var nodes = f.querySelectorAll('input[name="' + name + '"]:checked');
      nodes.forEach(function (n) { s.add(n.value); });
      return s;
    }
    state.filters.cat = collect("cat");
    state.filters.event = collect("event");
    state.filters.risk = collect("risk");
    state.filters.profile = collect("profile");

    var toggles = {};
    f.querySelectorAll('input[name="t"]:checked').forEach(function (n) {
      toggles[n.value] = true;
    });
    state.filters.tests = !!toggles.tests;
    state.filters.blocks = !!toggles.blocks;
    state.filters.network = !!toggles.network;
    state.filters.writes = !!toggles.writes;
  }

  function matches(h) {
    var f = state.filters;
    if (f.q) {
      var hay = (h.id + " " + (h.description || "")).toLowerCase();
      if (hay.indexOf(f.q) === -1) return false;
    }
    if (f.cat.size && !f.cat.has(h.category)) return false;
    if (f.event.size && !f.event.has(h.event)) return false;
    if (f.risk.size && !f.risk.has(h.risk_level)) return false;
    if (f.profile.size) {
      var profs = state.profilesMap[h.id] || [];
      var hit = false;
      for (var i = 0; i < profs.length; i++) {
        if (f.profile.has(profs[i])) { hit = true; break; }
      }
      if (!hit) return false;
    }
    if (f.tests && !h.tests) return false;
    if (f.blocks && !h.blocks_actions) return false;
    if (f.network && !h.network_access) return false;
    if (f.writes && !h.writes_files) return false;
    return true;
  }

  function compare(a, b) {
    var s = state.filters.sort;
    if (s === "category") {
      var c = (a.category || "").localeCompare(b.category || "");
      if (c !== 0) return c;
    } else if (s === "risk") {
      var ai = RISK_ORDER.indexOf(a.risk_level);
      var bi = RISK_ORDER.indexOf(b.risk_level);
      if (ai !== bi) return ai - bi;
    } else if (s === "event") {
      var e = (a.event || "").localeCompare(b.event || "");
      if (e !== 0) return e;
    }
    return a.id.localeCompare(b.id);
  }

  // Build a card via DOM APIs (no innerHTML) so untrusted-string warnings
  // are moot and CSP-strict environments are fine.
  function buildCard(h) {
    var li = document.createElement("li");
    li.className = "card";

    var head = document.createElement("div");
    head.className = "card-head";

    var idSpan = document.createElement("span");
    idSpan.className = "card-id";
    var idLink = document.createElement("a");
    idLink.href = GH_BASE + (h.path || "");
    idLink.rel = "noopener";
    idLink.textContent = h.id;
    idSpan.appendChild(idLink);
    head.appendChild(idSpan);

    var risk = h.risk_level || "passive";
    var riskBadge = document.createElement("span");
    riskBadge.className = "risk risk-" + risk;
    riskBadge.title = "risk: " + risk;
    riskBadge.textContent = risk;
    head.appendChild(riskBadge);

    li.appendChild(head);

    var meta = document.createElement("div");
    meta.className = "card-meta";

    var ev = document.createElement("span");
    ev.textContent = h.event || "";
    meta.appendChild(ev);

    var matcherSpan = document.createElement("span");
    if (h.matcher) {
      var code = document.createElement("code");
      code.textContent = h.matcher;
      matcherSpan.appendChild(code);
    } else {
      var anyTool = document.createElement("span");
      anyTool.className = "chip flag";
      anyTool.textContent = "any tool";
      matcherSpan.appendChild(anyTool);
    }
    meta.appendChild(matcherSpan);

    var cat = document.createElement("span");
    cat.textContent = "category: " + (h.category || "");
    meta.appendChild(cat);

    li.appendChild(meta);

    var desc = document.createElement("p");
    desc.className = "card-desc";
    desc.textContent = h.description || "";
    li.appendChild(desc);

    var footer = document.createElement("div");
    footer.className = "card-footer";

    var profs = state.profilesMap[h.id] || [];
    profs.forEach(function (p) {
      var chip = document.createElement("span");
      chip.className = "chip profile";
      chip.textContent = p;
      footer.appendChild(chip);
    });

    function flagChip(text, title) {
      var c = document.createElement("span");
      c.className = "chip flag";
      c.title = title;
      c.textContent = text;
      footer.appendChild(c);
    }
    if (h.tests) flagChip("tests", "Has bats tests");
    if (h.blocks_actions) flagChip("blocks", "Can block actions");
    if (h.network_access) flagChip("network", "Makes network calls");
    if (h.writes_files) flagChip("writes", "Writes files");

    if (HERO_DOCS[h.id]) {
      var heroA = document.createElement("a");
      heroA.className = "hero-link";
      heroA.rel = "noopener";
      heroA.href = DOC_BASE + encodeURIComponent(h.id) + ".md";
      heroA.textContent = "view hero doc →";
      footer.appendChild(heroA);
    }

    li.appendChild(footer);
    return li;
  }

  function render() {
    readFiltersFromForm();
    var filtered = state.hooks.filter(matches).sort(compare);
    var ul = $("#cards");
    var empty = $("#empty");
    var status = $("#status");

    while (ul.firstChild) ul.removeChild(ul.firstChild);

    if (filtered.length === 0) {
      empty.hidden = false;
    } else {
      empty.hidden = true;
      var frag = document.createDocumentFragment();
      filtered.forEach(function (h) { frag.appendChild(buildCard(h)); });
      ul.appendChild(frag);
    }

    var total = state.hooks.length;
    status.textContent = "Showing " + filtered.length + " of " + total + " hooks";
    var hc = document.getElementById("hook-count-display");
    if (hc) hc.textContent = total + " hooks across " +
      uniqueSorted(state.hooks.map(function (h) { return h.category; })).length +
      " categories";
    document.getElementById("results").setAttribute("aria-busy", "false");
  }

  function bindEvents() {
    var f = $("#filters");
    f.addEventListener("input", render);
    f.addEventListener("change", render);
    f.addEventListener("reset", function () { setTimeout(render, 0); });
  }

  function fail(msg) {
    $("#status").textContent = "Failed to load registry: " + msg;
    document.getElementById("results").setAttribute("aria-busy", "false");
  }

  // Stop the unused-var linter from yelling about escapeHTML in case we ever
  // need it again; keep it exported for debugging.
  window.__achEscape = escapeHTML;

  fetchRegistry()
    .then(function (data) {
      state.hooks = (data.hooks || []).slice();
      state.profilesMap = buildProfilesMap(data.profiles || {});
      buildFilters();
      bindEvents();
      render();
    })
    .catch(function (err) {
      fail(err.message || String(err));
    });
})();
