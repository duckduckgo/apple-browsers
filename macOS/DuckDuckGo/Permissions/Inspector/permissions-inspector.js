"use strict";
var state = { rows: [], filter: "", typeFilter: "", sort: { key: "domain", dir: 1 } };

function el(tag, text) {
    var e = document.createElement(tag);
    if (text !== undefined) { e.textContent = text; }
    return e;
}

function syncHeaderOffset() {
    var header = document.querySelector("header");
    if (header) { document.documentElement.style.setProperty("--header-h", header.offsetHeight + "px"); }
}

function cmp(a, b) { return a < b ? -1 : a > b ? 1 : 0; }

function sortRows(rows) {
    var k = state.sort.key, d = state.sort.dir;
    var arr = rows.slice();
    arr.sort(function(a, b) {
        var r;
        if (k === "type") { r = cmp(a.permissionType, b.permissionType); }
        else if (k === "allow") { r = cmp(a.allow ? 0 : 1, b.allow ? 0 : 1); }
        else if (k === "isRemoved") { r = cmp(a.isRemoved ? 0 : 1, b.isRemoved ? 0 : 1); }
        else if (k === "effective") { r = cmp(a.effective, b.effective); }
        else if (k === "fireproof") { r = cmp(a.isFireproof ? 0 : 1, b.isFireproof ? 0 : 1); }
        else { r = a.domainEncrypted.localeCompare(b.domainEncrypted); }
        // Domain then type as the tie-break, so rows for one domain stay grouped and stable.
        if (r === 0) { r = a.domainEncrypted.localeCompare(b.domainEncrypted); }
        if (r === 0) { r = cmp(a.permissionType, b.permissionType); }
        return d * r;
    });
    return arr;
}

function filtered() {
    var f = state.filter.trim().toLowerCase();
    var rows = state.rows.filter(function(r) {
        if (state.typeFilter && r.permissionType !== state.typeFilter) { return false; }
        if (!f) { return true; }
        return (r.domainEncrypted + " " + r.permissionType).toLowerCase().indexOf(f) !== -1;
    });
    return sortRows(rows);
}

// Options come from the rows actually stored, so a type this build can't parse (or a new
// external_<scheme> one) is still selectable. The current choice survives a reload when it's
// still present.
function renderTypeFilterOptions() {
    var select = document.getElementById("typeFilter");
    var types = [];
    state.rows.forEach(function(r) {
        if (types.indexOf(r.permissionType) === -1) { types.push(r.permissionType); }
    });
    types.sort();
    if (state.typeFilter && types.indexOf(state.typeFilter) === -1) { state.typeFilter = ""; }
    select.textContent = "";
    var all = el("option", "All types");
    all.value = "";
    select.appendChild(all);
    types.forEach(function(t) {
        var option = el("option", t);
        option.value = t;
        select.appendChild(option);
    });
    select.value = state.typeFilter;
}

function setSort(key) {
    if (state.sort.key === key) {
        state.sort.dir = -state.sort.dir;
    } else {
        state.sort = { key: key, dir: 1 };
    }
    render();
}

function updateSortHeaders() {
    var els = document.querySelectorAll("[data-sort]");
    Array.prototype.forEach.call(els, function(e) {
        var base = e.getAttribute("data-label");
        if (base === null) { base = e.textContent; e.setAttribute("data-label", base); }
        var active = state.sort.key === e.getAttribute("data-sort");
        e.textContent = base + (active ? (state.sort.dir > 0 ? " ▲" : " ▼") : "");
    });
}

function setCount() {
    var n = filtered().length;
    var overridden = state.rows.filter(function(r) { return r.isOverridden; }).length;
    var text = n + " / " + state.rows.length + " permissions";
    if (overridden) { text += " · " + overridden + " overridden"; }
    document.getElementById("count").textContent = text;
}

function selectedKeys() {
    var boxes = document.querySelectorAll("tbody input[type=checkbox]:checked");
    return Array.prototype.map.call(boxes, function(b) { return b.getAttribute("data-key"); });
}

function updateButtons() {
    var n = selectedKeys().length;
    var btn = document.getElementById("deleteSelected");
    btn.disabled = n === 0;
    btn.textContent = n > 0 ? ("Delete selected (" + n + ")") : "Delete selected";
}

function boolCell(value) {
    var td = el("td", value ? "true" : "false");
    td.className = "bool";
    return td;
}

function effectiveCell(row) {
    var td = el("td");
    td.className = "effective derived";
    td.appendChild(el("span", row.effective));
    if (row.isOverridden) {
        var badge = el("span", "override");
        badge.className = "badge override";
        badge.title = "A PermissionDecisionOverriding returns " + row.effective + " for this row; nothing is written to storage.";
        td.appendChild(document.createTextNode(" "));
        td.appendChild(badge);
    }
    return td;
}

function render() {
    var rows = filtered();
    setCount();
    updateSortHeaders();
    var body = document.getElementById("rows");
    body.textContent = "";
    rows.forEach(function(row) {
        var tr = document.createElement("tr");
        if (row.isOverridden) { tr.className = "overridden"; }

        var cbCell = el("td");
        var box = document.createElement("input");
        box.type = "checkbox";
        box.setAttribute("data-key", row.key);
        box.addEventListener("change", updateButtons);
        cbCell.appendChild(box);
        tr.appendChild(cbCell);

        var domainCell = el("td", row.domainEncrypted);
        domainCell.className = "domain";
        tr.appendChild(domainCell);

        var typeCell = el("td", row.permissionType);
        typeCell.className = "type";
        tr.appendChild(typeCell);

        tr.appendChild(boolCell(row.allow));
        tr.appendChild(boolCell(row.isRemoved));

        tr.appendChild(effectiveCell(row));

        var fireproofCell = el("td");
        fireproofCell.className = "derived";
        if (row.isFireproof) {
            var badge = el("span", "fireproof");
            badge.className = "badge";
            fireproofCell.appendChild(badge);
        }
        tr.appendChild(fireproofCell);

        body.appendChild(tr);
    });
    var selectAll = document.getElementById("selectAll");
    if (selectAll) { selectAll.checked = false; }
    updateButtons();
    syncHeaderOffset();
}

function load() {
    return fetch("/api/list").then(function(r) { return r.json(); }).then(function(rows) {
        state.rows = Array.isArray(rows) ? rows : [];
        renderTypeFilterOptions();
        render();
    }).catch(function() {
        state.rows = [];
        render();
    });
}

function removeKeys(keys) {
    if (!keys.length) { return Promise.resolve(); }
    return fetch("/api/remove?keys=" + encodeURIComponent(keys.join(","))).then(function(r) { return r.json(); });
}

document.addEventListener("DOMContentLoaded", function() {
    syncHeaderOffset();
    window.addEventListener("resize", syncHeaderOffset);
    document.getElementById("search").addEventListener("input", function(e) {
        state.filter = e.target.value;
        render();
    });
    document.getElementById("typeFilter").addEventListener("change", function(e) {
        state.typeFilter = e.target.value;
        render();
    });
    document.getElementById("reload").addEventListener("click", load);
    document.querySelector("thead").addEventListener("click", function(e) {
        var t = e.target.closest("[data-sort]");
        if (t) { setSort(t.getAttribute("data-sort")); }
    });
    document.getElementById("selectAll").addEventListener("change", function(e) {
        var boxes = document.querySelectorAll("tbody input[type=checkbox]");
        Array.prototype.forEach.call(boxes, function(b) { b.checked = e.target.checked; });
        updateButtons();
    });
    document.getElementById("deleteSelected").addEventListener("click", function() {
        var keys = selectedKeys();
        if (!keys.length) { return; }
        removeKeys(keys).then(load);
    });
    // Two-click confirm (avoids relying on window.confirm in the special page).
    var armed = false;
    var allBtn = document.getElementById("deleteAll");
    allBtn.addEventListener("click", function() {
        if (!armed) {
            armed = true;
            allBtn.textContent = "Click again to delete ALL";
            setTimeout(function() { armed = false; allBtn.textContent = "Delete all"; }, 3000);
            return;
        }
        armed = false;
        allBtn.textContent = "Delete all";
        fetch("/api/removeAll").then(function(r) { return r.json(); }).then(load);
    });
    load();
});
