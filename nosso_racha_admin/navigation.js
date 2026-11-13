const sections = new Set([
  "overview",
  "records",
  "vip-plans",
  "vip-payments",
  "vip-coupons",
  "venues",
  "finance",
]);

export function initializeNavigation() {
  const sidebar = document.querySelector("#adminSidebar");
  const toggle = document.querySelector("#sidebarToggle");
  const backdrop = document.querySelector("#sidebarBackdrop");
  const links = [...document.querySelectorAll("[data-nav-target]")];
  const pageSections = [...document.querySelectorAll("[data-page-section]")];

  function closeSidebar() {
    sidebar.classList.remove("is-open");
    backdrop.classList.remove("is-visible");
    toggle.setAttribute("aria-expanded", "false");
    toggle.setAttribute("aria-label", "Abrir menu");
  }

  function navigate(section, updateHistory = true) {
    if (!sections.has(section)) section = "overview";
    for (const page of pageSections) {
      page.classList.toggle("hidden", page.dataset.pageSection !== section);
    }
    for (const link of links) {
      const active = link.dataset.navTarget === section;
      link.classList.toggle("is-active", active);
      if (active && link.matches(".sidebar-link")) {
        link.setAttribute("aria-current", "page");
      } else {
        link.removeAttribute("aria-current");
      }
    }
    if (updateHistory && window.location.hash !== `#${section}`) {
      window.history.pushState(null, "", `#${section}`);
    }
    closeSidebar();
  }

  toggle.addEventListener("click", () => {
    const isOpen = sidebar.classList.toggle("is-open");
    backdrop.classList.toggle("is-visible", isOpen);
    toggle.setAttribute("aria-expanded", String(isOpen));
    toggle.setAttribute("aria-label", isOpen ? "Fechar menu" : "Abrir menu");
  });

  backdrop.addEventListener("click", closeSidebar);
  for (const link of links) {
    link.addEventListener("click", (event) => {
      event.preventDefault();
      navigate(link.dataset.navTarget);
    });
  }

  window.addEventListener("popstate", () => {
    navigate(window.location.hash.slice(1), false);
  });

  navigate(window.location.hash.slice(1) || "overview", false);
}
