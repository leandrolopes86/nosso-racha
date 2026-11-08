import {
  doc,
  onSnapshot,
  runTransaction,
  serverTimestamp,
} from "https://www.gstatic.com/firebasejs/10.12.5/firebase-firestore.js";

const FEATURES = ["settings", "finance", "reports", "athleteManagement"];
const LIMIT_FIELDS = {
  maxGroupMemberships: "#limitMemberships",
  maxOwnedOrganizations: "#limitOwnedGroups",
  maxOpenEvents: "#limitOpenEvents",
  maxAthletesPerGroup: "#limitAthletes",
  maxCoOrganizersPerGroup: "#limitCoOrganizers",
};
const PLAN_ORDER = ["free", "bronze", "silver", "gold", "platinum"];
const LEGACY_PLAN_IDS = { prata: "silver", ouro: "gold" };
const DEFAULT_PLANS = {
  free: {
    id: "free",
    displayName: "Free",
    appPlan: "free",
    color: "#64748b",
    active: true,
    defaultLimit: 50,
    limits: {
      maxGroupMemberships: 2,
      maxOwnedOrganizations: 0,
      maxOpenEvents: 3,
      maxAthletesPerGroup: 40,
      maxCoOrganizersPerGroup: 3,
    },
    featureLimits: { reports: 50 },
    features: [],
  },
  bronze: {
    id: "bronze",
    displayName: "Bronze",
    appPlan: "athlete_vip",
    color: "#b77945",
    active: true,
    defaultLimit: 50,
    limits: {
      maxGroupMemberships: 10,
      maxOwnedOrganizations: 0,
      maxOpenEvents: 3,
      maxAthletesPerGroup: 40,
      maxCoOrganizersPerGroup: 3,
    },
    featureLimits: { reports: 50 },
    features: [],
  },
  silver: {
    id: "silver",
    displayName: "Silver",
    appPlan: "athlete_vip",
    color: "#8795a1",
    active: true,
    defaultLimit: 50,
    limits: {
      maxGroupMemberships: 10,
      maxOwnedOrganizations: 0,
      maxOpenEvents: 3,
      maxAthletesPerGroup: 40,
      maxCoOrganizersPerGroup: 3,
    },
    featureLimits: { reports: 50 },
    features: [],
  },
  gold: {
    id: "gold",
    displayName: "Gold",
    appPlan: "athlete_vip",
    color: "#d6a52d",
    active: true,
    defaultLimit: 50,
    limits: {
      maxGroupMemberships: 10,
      maxOwnedOrganizations: 0,
      maxOpenEvents: 3,
      maxAthletesPerGroup: 40,
      maxCoOrganizersPerGroup: 3,
    },
    featureLimits: { reports: 50 },
    features: [],
  },
  platinum: {
    id: "platinum",
    displayName: "Platinum",
    appPlan: "organizer_vip",
    color: "#18764f",
    active: true,
    defaultLimit: 50,
    limits: {
      maxGroupMemberships: 10,
      maxOwnedOrganizations: null,
      maxOpenEvents: null,
      maxAthletesPerGroup: null,
      maxCoOrganizersPerGroup: null,
    },
    featureLimits: { reports: null },
    features: [...FEATURES],
  },
};

let planCatalog = structuredClone(DEFAULT_PLANS);

export function getVipPlanCatalog() {
  return planCatalog;
}

export function normalizeVipPlanId(value) {
  if (typeof value !== "string") return "";
  const id = value.trim().toLocaleLowerCase("en-US").replaceAll(" ", "_");
  return LEGACY_PLAN_IDS[id] ?? id;
}

export function isPaidVipPlan(value) {
  const planId = normalizeVipPlanId(value);
  const plan = planCatalog[planId];
  if (plan) return plan.appPlan !== "free";
  return PLAN_ORDER.includes(planId) && planId !== "free";
}

export function vipPlanDisplayName(value) {
  const id = normalizeVipPlanId(value);
  return planCatalog[id]?.displayName ?? "Free";
}

function show(element, message, kind = "error") {
  element.textContent = message;
  element.classList.remove("hidden", "is-success", "is-info");
  if (kind === "success") element.classList.add("is-success");
  if (kind === "info") element.classList.add("is-info");
}

function hide(element) {
  element.textContent = "";
  element.classList.add("hidden");
  element.classList.remove("is-success", "is-info");
}

function makeElement(tag, className, text) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  if (text !== undefined) element.textContent = text;
  return element;
}

function formatLimit(value) {
  return value == null ? "Ilimitado" : new Intl.NumberFormat("pt-BR").format(value);
}

function createLimitChip(label, value) {
  const chip = makeElement("span", "plan-limit-chip");
  chip.append(
    makeElement("strong", "", formatLimit(value)),
    document.createTextNode(` ${label}`),
  );
  return chip;
}

function renderPlans(container, onEdit) {
  container.replaceChildren();
  const plans = PLAN_ORDER.map((id) => planCatalog[id]);
  if (!plans.length) {
    container.append(makeElement("p", "empty-state", "Nenhum plano cadastrado."));
    return;
  }

  for (const plan of plans) {
    const card = makeElement("article", "vip-plan-card");
    card.style.setProperty("--plan-color", plan.color);
    const heading = makeElement("div", "vip-plan-card-heading");
    const identity = makeElement("div", "vip-plan-identity");
    identity.append(
      makeElement("span", "vip-plan-color-dot"),
      makeElement("h2", "vip-plan-name", plan.displayName),
    );
    const status = makeElement(
      "span",
      `plan-status${plan.active ? " is-active" : ""}`,
      plan.active ? "Ativo" : "Desativado",
    );
    heading.append(identity, status);
    const typeLabel =
      plan.appPlan === "organizer_vip"
        ? "VIP organizador"
        : plan.appPlan === "athlete_vip"
          ? "VIP atleta"
          : "Plano gratuito";
    const id = makeElement("p", "vip-plan-id", plan.id);
    const type = makeElement("span", "vip-plan-type", typeLabel);
    const limits = makeElement("div", "vip-plan-limits");
    limits.append(
      createLimitChip("padrão", plan.defaultLimit),
      createLimitChip("organizações", plan.limits.maxGroupMemberships),
      createLimitChip("grupos criados", plan.limits.maxOwnedOrganizations),
      createLimitChip("atletas/grupo", plan.limits.maxAthletesPerGroup),
      createLimitChip("relatórios", plan.featureLimits.reports ?? plan.defaultLimit),
    );
    const footer = makeElement("div", "vip-plan-card-footer");
    const edit = makeElement("button", "button button-outline button-small", "Editar plano");
    edit.type = "button";
    edit.addEventListener("click", () => onEdit(plan));
    footer.append(type, edit);
    card.append(heading, id, limits, footer);
    container.append(card);
  }
}

function readOptionalLimit(selector) {
  const value = document.querySelector(selector).value.trim();
  if (!value) return null;
  const number = Number(value);
  if (!Number.isSafeInteger(number) || number < 0 || number > 1_000_000) {
    throw new Error("Os limites devem ser números inteiros entre 0 e 1.000.000.");
  }
  return number;
}

function fillForm(plan) {
  document.querySelector("#vipPlanColor").value = plan?.color ?? "#18764f";
  document.querySelector("#vipPlanActive").checked = plan?.active ?? true;
  document.querySelector("#vipPlanActive").disabled = plan?.id === "free";
  document.querySelector("#limitDefault").value = String(plan?.defaultLimit ?? 50);
  for (const [field, selector] of Object.entries(LIMIT_FIELDS)) {
    const value = plan?.limits?.[field];
    document.querySelector(selector).value = value == null ? "" : String(value);
  }
  const reportLimit = plan?.featureLimits?.reports;
  document.querySelector("#limitReports").value =
    reportLimit == null ? "" : String(reportLimit);
  const features = new Set(plan?.features ?? []);
  for (const checkbox of document.querySelectorAll('[name="vipPlanFeature"]')) {
    checkbox.checked = features.has(checkbox.value);
  }
  document.querySelector("#vipPlanDialogTitle").textContent =
    `Editar plano ${plan.displayName}`;
  hide(document.querySelector("#vipPlanFormMessage"));
}

export function initializeVipPlans({ db, auth, showDashboardMessage, hideDashboardMessage }) {
  const list = document.querySelector("#vipPlansList");
  const dialog = document.querySelector("#vipPlanDialog");
  const form = document.querySelector("#vipPlanForm");
  const formMessage = document.querySelector("#vipPlanFormMessage");
  const message = document.querySelector("#vipPlanMessage");
  const saveButton = document.querySelector("#saveVipPlanButton");
  const configRef = doc(db, "settings", "vip_plans");
  let unsubscribe;
  let editingPlanId = null;

  const openForm = (plan = null) => {
    if (!plan || !PLAN_ORDER.includes(plan.id)) return;
    editingPlanId = plan?.id ?? null;
    fillForm(plan);
    dialog.showModal();
  };

  document.querySelector("#closeVipPlanDialogButton").addEventListener("click", () => dialog.close());
  document.querySelector("#cancelVipPlanDialogButton").addEventListener("click", () => dialog.close());
  dialog.addEventListener("click", (event) => {
    if (event.target === dialog) dialog.close();
  });

  const handleSnapshot = (snapshot) => {
    if (!snapshot.exists()) {
      planCatalog = structuredClone(DEFAULT_PLANS);
      renderPlans(list, openForm);
      return;
    }
    const configuredPlans = snapshot.data().plans;
    if (!configuredPlans || typeof configuredPlans !== "object" || Array.isArray(configuredPlans)) {
      show(message, "O documento settings/vip_plans tem um formato inválido.", "error");
      return;
    }
    const nextCatalog = structuredClone(DEFAULT_PLANS);
    for (const [id, value] of Object.entries(configuredPlans)) {
      const canonicalId = LEGACY_PLAN_IDS[id] ?? id;
      if (!PLAN_ORDER.includes(canonicalId)) continue;
      if (
        !value ||
        typeof value !== "object" ||
        !/^#[0-9a-f]{6}$/i.test(value.color)
      ) {
        show(message, `A definição do plano "${id}" está inválida. Corrija o documento antes de continuar.`);
        return;
      }
      if (id in LEGACY_PLAN_IDS && configuredPlans[canonicalId]) continue;
      const defaults = nextCatalog[canonicalId];
      nextCatalog[canonicalId] = {
        ...defaults,
        ...value,
        id: canonicalId,
        displayName: defaults.displayName,
        appPlan: defaults.appPlan,
        active: canonicalId === "free" || value.active === true,
        defaultLimit: Number.isSafeInteger(value.defaultLimit) ? value.defaultLimit : defaults.defaultLimit,
        limits: { ...defaults.limits, ...(value.limits ?? {}) },
        featureLimits: { ...defaults.featureLimits, ...(value.featureLimits ?? {}) },
        features: canonicalId === "platinum" && Array.isArray(value.features)
          ? value.features.filter((feature) => FEATURES.includes(feature))
          : defaults.features,
      };
    }
    planCatalog = nextCatalog;
    hide(message);
    renderPlans(list, openForm);
  };
  const handleError = (error) => {
    renderPlans(list, openForm);
    show(
      message,
      error.code === "permission-denied"
        ? "A leitura do catálogo de planos foi negada. Publique as regras do Firestore atualizadas."
        : `Não foi possível carregar os planos VIP: ${error.message}`,
    );
  };

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    hide(formMessage);
    hideDashboardMessage();
    const id = editingPlanId;
    const currentPlan = planCatalog[id];
    if (!currentPlan || !PLAN_ORDER.includes(id)) {
      show(formMessage, "Selecione um dos planos disponíveis para editar.");
      return;
    }
    const color = document.querySelector("#vipPlanColor").value;

    saveButton.disabled = true;
    try {
      const limits = {};
      for (const [field, selector] of Object.entries(LIMIT_FIELDS)) {
        limits[field] = readOptionalLimit(selector);
      }
      const defaultLimit = Number(document.querySelector("#limitDefault").value);
      if (!Number.isSafeInteger(defaultLimit) || defaultLimit < 0 || defaultLimit > 1_000_000) {
        throw new Error("O limite padrão deve ser um inteiro entre 0 e 1.000.000.");
      }
      const features = [...document.querySelectorAll('[name="vipPlanFeature"]:checked')]
        .map((checkbox) => checkbox.value);
      const plan = {
        id,
        displayName: currentPlan.displayName,
        appPlan: currentPlan.appPlan,
        color,
        active: document.querySelector("#vipPlanActive").checked || id === "free",
        defaultLimit,
        limits,
        featureLimits: { reports: readOptionalLimit("#limitReports") },
        features: id === "platinum" ? features : [],
      };

      await runTransaction(db, async (transaction) => {
        const snapshot = await transaction.get(configRef);
        const existing = snapshot.exists() ? snapshot.data().plans : {};
        if (
          existing &&
          (typeof existing !== "object" || Array.isArray(existing))
        ) {
          throw new Error("O catálogo atual do Firestore está malformado.");
        }
        if (!Object.hasOwn(DEFAULT_PLANS, id)) {
          throw new Error("Apenas os planos padrões podem ser editados.");
        }
        const plans = Object.fromEntries(
          PLAN_ORDER.map((planId) => {
            const legacyId = Object.keys(LEGACY_PLAN_IDS).find(
              (oldId) => LEGACY_PLAN_IDS[oldId] === planId,
            );
            const configured =
              existing?.[planId] ?? (legacyId ? existing?.[legacyId] : null);
            if (
              configured != null &&
              (typeof configured !== "object" || Array.isArray(configured))
            ) {
              throw new Error(`A definição do plano ${planId} está malformada.`);
            }
            const defaults = DEFAULT_PLANS[planId];
            return [
              planId,
              {
                ...defaults,
                ...(configured ?? {}),
                id: planId,
                displayName: defaults.displayName,
                appPlan: defaults.appPlan,
                active: planId === "free" || configured?.active === true,
                limits: { ...defaults.limits, ...(configured?.limits ?? {}) },
                featureLimits: {
                  ...defaults.featureLimits,
                  ...(configured?.featureLimits ?? {}),
                },
                features:
                  planId === "platinum" && Array.isArray(configured?.features)
                    ? configured.features.filter((feature) => FEATURES.includes(feature))
                    : defaults.features,
              },
            ];
          }),
        );
        plans[id] = plan;
        transaction.set(
          configRef,
          {
            schemaVersion: 1,
            plans,
            updatedAt: serverTimestamp(),
            updatedBy: auth.currentUser.uid,
          },
        );
      });
      dialog.close();
      show(message, `O plano ${currentPlan.displayName} foi salvo.`, "success");
      showDashboardMessage(`Catálogo atualizado. O app receberá os limites na próxima inicialização.`, "success");
    } catch (error) {
      console.error("VIP plan save failed:", error);
      show(
        formMessage,
        error.code === "permission-denied"
          ? "A gravação foi negada. Verifique a permissão de administrador e publique as regras atualizadas."
          : `Não foi possível salvar o plano: ${error.message}`,
      );
    } finally {
      saveButton.disabled = false;
    }
  });

  return {
    start() {
      if (!unsubscribe) unsubscribe = onSnapshot(configRef, handleSnapshot, handleError);
    },
    stop() {
      unsubscribe?.();
      unsubscribe = undefined;
    },
  };
}
