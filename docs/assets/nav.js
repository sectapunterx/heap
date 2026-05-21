/* heap. — site nav
   Wires scrollspy for both the top tabs and the brand-page sub-nav.
   Also handles the landing's screenshot tab group.
*/

(function () {
    "use strict";

    /* ---------- scrollspy ---------- */
    function setupScrollspy(tabsSelector) {
        var tabs = document.querySelectorAll(tabsSelector);
        if (!tabs.length) return;

        var targets = [];
        tabs.forEach(function (t) {
            var href = t.getAttribute("href") || "";
            if (href.charAt(0) !== "#") return;
            var el = document.getElementById(href.slice(1));
            if (el) targets.push({tab: t, el: el});
        });
        if (!targets.length) return;

        function onScroll() {
            var nav = document.querySelector(".topbar");
            var sub = document.querySelector(".subnav");
            var offset = (nav ? nav.offsetHeight : 0) + (sub ? sub.offsetHeight : 0) + 40;
            var y = window.scrollY + offset;

            var current = targets[0];
            for (var i = 0; i < targets.length; i++) {
                var top = targets[i].el.getBoundingClientRect().top + window.scrollY;
                if (top <= y) current = targets[i];
            }
            // edge: if we're near bottom, prefer last
            if (window.innerHeight + window.scrollY >= document.body.offsetHeight - 8) {
                current = targets[targets.length - 1];
            }

            targets.forEach(function (t) {
                if (t === current) t.tab.classList.add("active");
                else t.tab.classList.remove("active");
            });
        }

        window.addEventListener("scroll", onScroll, {passive: true});
        window.addEventListener("resize", onScroll);
        onScroll();
    }

    /* ---------- screenshot tab group ---------- */
    function setupScreenTabs() {
        var groups = document.querySelectorAll("[data-screens]");
        groups.forEach(function (group) {
            var tabs = group.querySelectorAll(".screen-tab");
            var panels = group.querySelectorAll(".screen-panel");

            tabs.forEach(function (tab) {
                tab.addEventListener("click", function () {
                    var target = tab.getAttribute("data-target");
                    tabs.forEach(function (t) {
                        t.setAttribute("aria-selected", t === tab ? "true" : "false");
                    });
                    panels.forEach(function (p) {
                        p.setAttribute("data-active", p.getAttribute("data-name") === target ? "true" : "false");
                    });
                });
            });
        });
    }

    /* ---------- year stamp ---------- */
    function setupYear() {
        var nodes = document.querySelectorAll("[data-year]");
        var y = new Date().getFullYear();
        nodes.forEach(function (n) {
            n.textContent = y;
        });
    }

    document.addEventListener("DOMContentLoaded", function () {
        setupScrollspy(".topbar-tabs .tab[href^='#'], .subnav .sub-tab[href^='#']");
        setupScreenTabs();
        setupYear();
    });
})();
