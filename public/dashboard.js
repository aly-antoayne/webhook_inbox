document.addEventListener("DOMContentLoaded", () => {
  const dialog = document.getElementById("demo-dialog");
  document.querySelectorAll("[data-open-demo]").forEach(button => button.addEventListener("click", () => dialog?.showModal()));
  document.querySelectorAll("[data-close-dialog]").forEach(button => button.addEventListener("click", () => dialog?.close()));
  dialog?.addEventListener("click", event => { if (event.target === dialog) dialog.close(); });
  const menu = document.querySelector("[data-toggle-menu]");
  const sidebar = document.getElementById("sidebar");
  menu?.addEventListener("click", () => {
    const open = sidebar.classList.toggle("open");
    menu.setAttribute("aria-expanded", String(open));
  });
  document.addEventListener("keydown", event => {
    if (event.key === "Escape") { sidebar?.classList.remove("open"); menu?.setAttribute("aria-expanded", "false"); }
  });
  document.addEventListener("click", event => {
    if (sidebar?.classList.contains("open") && !sidebar.contains(event.target) && !menu?.contains(event.target)) {
      sidebar.classList.remove("open"); menu?.setAttribute("aria-expanded", "false");
    }
  });
  document.querySelectorAll("[data-copy-target]").forEach(button => button.addEventListener("click", async () => {
    const target = document.getElementById(button.dataset.copyTarget);
    const feedback = document.getElementById("copy-feedback");
    try {
      await navigator.clipboard.writeText(target.textContent);
      if (feedback) feedback.textContent = "JSON copiado.";
    } catch {
      const range = document.createRange(); range.selectNodeContents(target);
      const selection = window.getSelection(); selection.removeAllRanges(); selection.addRange(range);
      if (feedback) feedback.textContent = "JSON selecionado. Use Ctrl+C para copiar.";
    }
  }));
  document.querySelectorAll("[data-refresh]").forEach(button => button.addEventListener("click", () => location.reload()));
  const scenario = document.getElementById("scenario");
  const preview = document.getElementById("demo-preview");
  scenario?.addEventListener("change", () => {
    const data = { id: "evt_gerado_automaticamente", type: scenario.value === "refund" ? "payment.refunded" : "payment.approved", data: { order_id: "demo_gerado_automaticamente", amount_cents: scenario.value === "invalid" ? -1 : 15990, currency: "BRL" } };
    if (scenario.value === "retry") data.simulate_failure = true;
    preview.textContent = JSON.stringify(data, null, 2);
  });
  document.querySelectorAll("form[data-submission]").forEach(form => form.addEventListener("submit", () => {
    const button = form.querySelector('button[type="submit"]');
    if (button) { button.disabled = true; button.textContent = "Enfileirando…"; }
  }));
});
