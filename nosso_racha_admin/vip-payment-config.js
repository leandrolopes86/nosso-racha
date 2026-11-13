import {
  collection,
  doc,
  onSnapshot,
  orderBy,
  query,
  runTransaction,
  serverTimestamp,
  Timestamp,
  where,
} from "https://www.gstatic.com/firebasejs/10.12.5/firebase-firestore.js";
import {
  getFunctions,
  httpsCallable,
} from "https://www.gstatic.com/firebasejs/10.12.5/firebase-functions.js";

const PLAN_LABELS = {
  bronze: "Bronze",
  silver: "Silver",
  gold: "Gold",
  platinum: "Platinum",
};
const PLAN_IDS = Object.keys(PLAN_LABELS);

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

function toDate(value) {
  if (value instanceof Timestamp) return value.toDate();
  if (value instanceof Date) return value;
  return null;
}

function formatDate(value) {
  const date = toDate(value);
  return date ? new Intl.DateTimeFormat("pt-BR").format(date) : "Sem vencimento";
}

function parsePositiveInteger(input, label, max = 3660) {
  const value = Number(input.value);
  if (!Number.isSafeInteger(value) || value < 1 || value > max) {
    throw new Error(`${label} deve ser um inteiro entre 1 e ${max}.`);
  }
  return value;
}

export function initializeVipPayments({ db, auth, showDashboardMessage, hideDashboardMessage }) {
  const configForm = document.querySelector("#vipPaymentConfigForm");
  const configMessage = document.querySelector("#vipPaymentConfigMessage");
  const requestsContainer = document.querySelector("#vipPaymentRequests");
  const providerSelect = document.querySelector("#vipPaymentProvider");
  const manualFields = document.querySelector("#vipManualFields");
  const mercadoPagoFields = document.querySelector("#vipMercadoPagoFields");
  const tokenInput = document.querySelector("#vipMercadoPagoAccessToken");
  const editTokenButton = document.querySelector("#editVipMercadoPagoToken");
  const tokenStatus = document.querySelector("#vipMercadoPagoTokenStatus");
  const saveButton = document.querySelector("#saveVipPaymentConfig");
  const couponForm = document.querySelector("#vipCouponForm");
  const couponMessage = document.querySelector("#vipCouponMessage");
  const couponsContainer = document.querySelector("#vipCouponsList");
  const couponCodeInput = document.querySelector("#vipCouponCode");
  const couponTypeSelect = document.querySelector("#vipCouponDiscountType");
  const couponValueInput = document.querySelector("#vipCouponDiscountValue");
  const couponValueLabel = document.querySelector("#vipCouponDiscountValueLabel");
  const couponExpiresAtInput = document.querySelector("#vipCouponExpiresAt");
  const configRef = doc(db, "settings", "payment_config");
  const functions = getFunctions(undefined, "southamerica-east1");
  const saveConfigCallable = httpsCallable(functions, "saveVipPaymentConfig");
  const saveCouponCallable = httpsCallable(functions, "saveVipCoupon");
  const rejectRequestCallable = httpsCallable(functions, "rejectVipManualPaymentRequest");
  let config = null;
  let hasMercadoPagoToken = false;
  let isEditingToken = false;
  let unsubscribeConfig;
  let unsubscribeRequests;
  let unsubscribeCoupons;
  const markConfigDirty = () => {
    configForm.dataset.dirty = "true";
  };

  const syncProviderFields = () => {
    const isManual = providerSelect.value === "pix_manual";
    manualFields.classList.toggle("hidden", !isManual);
    mercadoPagoFields.classList.toggle("hidden", isManual);
  };

  const syncTokenField = () => {
    tokenInput.disabled = hasMercadoPagoToken && !isEditingToken;
    tokenInput.placeholder = !hasMercadoPagoToken
      ? "Informe o Access Token"
      : isEditingToken
        ? "Informe o novo Access Token"
        : "••••••••••••••••";
    editTokenButton.hidden = !hasMercadoPagoToken;
    editTokenButton.textContent = isEditingToken
      ? "Cancelar edição"
      : "Editar token";
    editTokenButton.setAttribute("aria-expanded", String(isEditingToken));
    tokenStatus.textContent = !hasMercadoPagoToken
      ? "Token não configurado. Informe o Access Token e salve a configuração."
      : isEditingToken
        ? "Informe um novo token para substituí-lo. Se deixar o campo vazio, o token atual será mantido."
        : "Access Token salvo e configurado. Clique em Editar token para substituí-lo.";
  };

  const handleTokenEdit = () => {
    if (!hasMercadoPagoToken) return;
    isEditingToken = !isEditingToken;
    tokenInput.value = "";
    syncTokenField();
    if (isEditingToken) tokenInput.focus();
  };

  const fillForm = (data = {}) => {
    config = data;
    providerSelect.value = data.provider === "mercadopago" ? "mercadopago" : "pix_manual";
    document.querySelector("#vipManualPixKey").value = data.manualPixKey ?? "";
    document.querySelector("#vipManualBeneficiary").value = data.manualBeneficiary ?? "";
    document.querySelector("#vipManualInstructions").value = data.manualInstructions ?? "";
    hasMercadoPagoToken = data.hasMercadoPagoToken === true;
    isEditingToken = false;
    tokenInput.value = "";
    syncTokenField();

    syncProviderFields();
  };

  const renderCoupons = (snapshot) => {
    couponsContainer.replaceChildren();
    if (snapshot.empty) {
      const empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "Nenhum cupom cadastrado.";
      couponsContainer.append(empty);
      return;
    }

    const coupons = snapshot.docs
      .map((document) => document.data())
      .sort((left, right) => left.code.localeCompare(right.code));
    for (const coupon of coupons) {
      const card = document.createElement("article");
      card.className = "venue-request-card";
      const header = document.createElement("div");
      header.className = "venue-request-header";
      const title = document.createElement("h3");
      title.className = "venue-request-name";
      title.textContent = coupon.code;
      const status = document.createElement("span");
      status.className = "muted";
      const expiresAtMillis = coupon.expiresAt?.toMillis?.() ?? null;
      const isExpired = expiresAtMillis !== null && Date.now() >= expiresAtMillis;
      const isExhausted = coupon.maxUses != null &&
        (coupon.usedCount ?? 0) >= coupon.maxUses;
      status.textContent = !coupon.active
        ? "Inativo"
        : isExpired
          ? "Expirado"
          : isExhausted
            ? "Usos esgotados"
            : "Ativo";
      header.append(title, status);

      const discount = coupon.discountType === "percent"
        ? `${coupon.discountValue}% de desconto`
        : coupon.discountType === "final_price"
          ? `Preço final ${new Intl.NumberFormat("pt-BR", {
            style: "currency",
            currency: "BRL",
          }).format(coupon.discountValue / 100)}`
          : `${new Intl.NumberFormat("pt-BR", {
          style: "currency",
          currency: "BRL",
        }).format(coupon.discountValue / 100)} de desconto`;
      const usage = coupon.maxUses == null
        ? `${coupon.usedCount ?? 0} usos · sem limite`
        : `${coupon.usedCount ?? 0} de ${coupon.maxUses} usos`;
      const validPlans = (coupon.planIds ?? PLAN_IDS)
        .map((plan) => PLAN_LABELS[plan] ?? plan)
        .join(", ");
      const expiry = expiresAtMillis === null
        ? "Sem data de encerramento"
        : `Até ${new Intl.DateTimeFormat("pt-BR", {
          dateStyle: "short",
          timeStyle: "short",
        }).format(new Date(expiresAtMillis))}`;
      const details = document.createElement("p");
      details.className = "muted mt-2";
      details.textContent = `${discount} · Planos: ${validPlans} · ${usage} · ${expiry}`;
      const toggle = document.createElement("button");
      toggle.type = "button";
      toggle.className = "button button-quiet button-small mt-4";
      toggle.textContent = coupon.active ? "Desativar cupom" : "Ativar cupom";
      toggle.addEventListener("click", async () => {
        toggle.disabled = true;
        try {
          await saveCouponCallable({
            code: coupon.code,
            discountType: coupon.discountType,
            discountValue: coupon.discountValue,
            maxUses: coupon.maxUses ?? null,
            planIds: coupon.planIds ?? PLAN_IDS,
            expiresAtMillis,
            active: !coupon.active,
          });
          showDashboardMessage(
            coupon.active ? "Cupom desativado." : "Cupom ativado.",
            "success",
          );
        } catch (error) {
          showDashboardMessage(`Não foi possível atualizar o cupom: ${error.message}`);
        } finally {
          toggle.disabled = false;
        }
      });
      card.append(header, details, toggle);
      couponsContainer.append(card);
    }
  };

  const syncCouponValueField = () => {
    if (couponTypeSelect.value === "percent") {
      couponValueLabel.textContent = "Percentual de desconto";
      couponValueInput.min = "1";
      couponValueInput.max = "99";
      couponValueInput.step = "1";
      couponValueInput.placeholder = "Ex.: 15";
      return;
    }
    couponValueLabel.textContent = couponTypeSelect.value === "final_price"
      ? "Preço final do plano · R$"
      : "Valor do desconto · R$";
    couponValueInput.min = "0.01";
    couponValueInput.max = "100000";
    couponValueInput.step = "0.01";
    couponValueInput.placeholder = "Ex.: 10,00";
  };

  const parseCouponDiscount = () => {
    const value = Number(couponValueInput.value.replace(",", "."));
    if (couponTypeSelect.value === "percent") {
      if (!Number.isSafeInteger(value) || value < 1 || value > 99) {
        throw new Error("O percentual deve ser um inteiro entre 1 e 99.");
      }
      return value;
    }
    if (!Number.isFinite(value) || value <= 0 || value > 100000) {
      throw new Error("Informe um valor entre R$ 0,01 e R$ 100.000,00.");
    }
    return Math.round(value * 100);
  };

  const uppercaseCouponCode = () => {
    const code = couponCodeInput.value;
    const selectionStart = couponCodeInput.selectionStart;
    const selectionEnd = couponCodeInput.selectionEnd;
    const uppercaseCode = code.toUpperCase();
    if (uppercaseCode === code) return;

    couponCodeInput.value = uppercaseCode;
    if (selectionStart !== null && selectionEnd !== null) {
      couponCodeInput.setSelectionRange(
        code.slice(0, selectionStart).toUpperCase().length,
        code.slice(0, selectionEnd).toUpperCase().length,
      );
    }
  };

  const handleCouponSubmit = async (event) => {
    event.preventDefault();
    hide(couponMessage);
    hideDashboardMessage();
    const submitButton = couponForm.querySelector('button[type="submit"]');
    submitButton.disabled = true;
    try {
      const code = couponCodeInput.value.trim().toUpperCase();
      const discountType = couponTypeSelect.value;
      const discountValue = parseCouponDiscount();
      const rawMaxUses = document.querySelector("#vipCouponMaxUses").value.trim();
      const maxUses = rawMaxUses
        ? parsePositiveInteger(
          document.querySelector("#vipCouponMaxUses"),
          "Quantidade máxima de usos",
          1000000,
        )
        : null;
      const planIds = [
        ...couponForm.querySelectorAll('input[name="vipCouponPlan"]:checked'),
      ].map((input) => input.value);
      if (planIds.length === 0) {
        throw new Error("Selecione ao menos um plano VIP para o cupom.");
      }
      const expiresAtValue = couponExpiresAtInput.value;
      const expiresAtMillis = expiresAtValue
        ? new Date(expiresAtValue).getTime()
        : null;
      if (
        expiresAtMillis !== null &&
        (!Number.isSafeInteger(expiresAtMillis) || expiresAtMillis <= Date.now())
      ) {
        throw new Error("A data e hora de encerramento devem estar no futuro.");
      }
      await saveCouponCallable({
        code,
        discountType,
        discountValue,
        maxUses,
        planIds,
        expiresAtMillis,
      });
      couponForm.reset();
      couponTypeSelect.value = "percent";
      syncCouponValueField();
      show(couponMessage, `Cupom ${code} salvo.`, "success");
    } catch (error) {
      show(
        couponMessage,
        error.code === "functions/permission-denied"
          ? "Apenas administradores autorizados podem gerenciar cupons."
          : `Não foi possível salvar o cupom: ${error.message}`,
      );
    } finally {
      submitButton.disabled = false;
    }
  };

  const renderRequests = (snapshot) => {
    requestsContainer.replaceChildren();
    if (snapshot.empty) {
      const empty = document.createElement("p");
      empty.className = "empty-state";
      empty.textContent = "Nenhuma solicitação de Pix pendente.";
      requestsContainer.append(empty);
      return;
    }

    const pendingRequests = snapshot.docs
      .filter((document) => document.data().status === 'pending')
      .sort((a, b) => {
        const left = a.data().createdAt?.toMillis?.() ?? 0;
        const right = b.data().createdAt?.toMillis?.() ?? 0;
        return right - left;
      });
    if (pendingRequests.length === 0) {
      const empty = document.createElement('p');
      empty.className = 'empty-state';
      empty.textContent = 'Nenhuma solicitação de Pix pendente.';
      requestsContainer.append(empty);
      return;
    }

    for (const requestSnapshot of pendingRequests) {
      const request = requestSnapshot.data();
      const card = document.createElement("article");
      card.className = "venue-request-card";
      const header = document.createElement("div");
      header.className = "venue-request-header";
      const title = document.createElement("h3");
      title.className = "venue-request-name";
      title.textContent = `${request.userName || request.uid} · ${PLAN_LABELS[request.plan] ?? request.plan}`;
      const date = document.createElement("span");
      date.className = "muted";
      date.textContent = formatDate(request.createdAt);
      header.append(title, date);

      const details = document.createElement("p");
      details.className = "muted mt-2";
      const total = new Intl.NumberFormat("pt-BR", {
        style: "currency",
        currency: "BRL",
      }).format((request.amountCents ?? 0) / 100);
      const discountDetails = request.couponCode
        ? ` · Cupom ${request.couponCode} · desconto ${new Intl.NumberFormat("pt-BR", {
          style: "currency",
          currency: "BRL",
        }).format((request.discountCents ?? 0) / 100)}`
        : "";
      details.textContent = `${request.email || ""} · ${total}${discountDetails}`;
      const actions = document.createElement("div");
      actions.className = "venue-request-actions mt-4";
      const approve = document.createElement("button");
      approve.type = "button";
      approve.className = "button button-primary button-small";
      approve.textContent = "Aprovar e ativar plano";
      approve.addEventListener("click", () => reviewRequest(requestSnapshot.ref, "approved", approve));
      const reject = document.createElement("button");
      reject.type = "button";
      reject.className = "button button-quiet button-small";
      reject.textContent = "Recusar";
      reject.addEventListener("click", () => reviewRequest(requestSnapshot.ref, "rejected", reject));
      actions.append(approve, reject);
      card.append(header, details, actions);
      requestsContainer.append(card);
    }
  };

  const reviewRequest = async (requestRef, status, button) => {
    hideDashboardMessage();
    button.disabled = true;
    try {
      if (status === "rejected") {
        await rejectRequestCallable({ requestId: requestRef.id });
        showDashboardMessage("Solicitação recusada.", "success");
        return;
      }
      await runTransaction(db, async (transaction) => {
        const requestSnapshot = await transaction.get(requestRef);
        if (!requestSnapshot.exists() || requestSnapshot.data().status !== "pending") {
          throw new Error("Esta solicitação já foi analisada.");
        }
        const request = requestSnapshot.data();
        const userRef = doc(db, "users", request.uid);
        const userSnapshot = await transaction.get(userRef);
        if (!userSnapshot.exists()) throw new Error("O usuário da solicitação não existe.");
        const user = userSnapshot.data();
        const days = request.durationDays;
        if (!Number.isSafeInteger(days) || days < 1) {
          throw new Error("Configure a duração do plano antes de aprovar pagamentos.");
        }
        const now = new Date();
        const currentExpiration = toDate(user.vipExpiresAt);
        const renewalStart = currentExpiration && currentExpiration > now
          ? currentExpiration
          : now;
        const expiration = new Date(renewalStart);
        expiration.setDate(expiration.getDate() + days);
        transaction.update(userRef, {
          vipPlan: request.plan,
          vipExpiresAt: Timestamp.fromDate(expiration),
          updatedAt: serverTimestamp(),
          lastManualPayment: {
            method: "pix_manual",
            approvedAt: serverTimestamp(),
            approvedBy: auth.currentUser.uid,
            plan: request.plan,
          },
        });
        transaction.set(doc(db, "vip_public_badges", request.uid), {
          uid: request.uid,
          plan: request.plan,
          expiresAt: Timestamp.fromDate(expiration),
          updatedAt: serverTimestamp(),
        });
        transaction.update(requestRef, {
          status,
          reviewedAt: serverTimestamp(),
          reviewedBy: auth.currentUser.uid,
          expiresAt: Timestamp.fromDate(expiration),
        });
      });
      showDashboardMessage(
        status === "approved" ? "Pagamento aprovado e plano ativado." : "Solicitação recusada.",
        "success",
      );
    } catch (error) {
      showDashboardMessage(`Não foi possível analisar o pagamento: ${error.message}`);
    } finally {
      button.disabled = false;
    }
  };

  const handleConfigSubmit = async (event) => {
    event.preventDefault();
    hide(configMessage);
    hideDashboardMessage();
    saveButton.disabled = true;
    try {
      const payload = {
        provider: providerSelect.value,
        manualPixKey: document.querySelector("#vipManualPixKey").value.trim(),
        manualBeneficiary: document.querySelector("#vipManualBeneficiary").value.trim(),
        manualInstructions: document.querySelector("#vipManualInstructions").value.trim(),
        accessToken: tokenInput.value.trim(),
      };
      const result = await saveConfigCallable(payload);
      configForm.dataset.dirty = "false";
      fillForm({
        provider: payload.provider,
        manualPixKey: payload.manualPixKey,
        manualBeneficiary: payload.manualBeneficiary,
        manualInstructions: payload.manualInstructions,
        prices: config?.prices ?? {},
        hasMercadoPagoToken: result.data.hasMercadoPagoToken,
      });
      show(
        configMessage,
        result.data.hasMercadoPagoToken
          ? "Configuração salva. Access Token do Mercado Pago está configurado."
          : "Configuração de pagamento salva.",
        "success",
      );
    } catch (error) {
      show(
        configMessage,
        error.code === "functions/permission-denied"
          ? "Apenas administradores autorizados podem salvar esta configuração."
          : `Não foi possível salvar a configuração: ${error.message}`,
      );
    } finally {
      saveButton.disabled = false;
    }
  };

  return {
    getConfig() {
      return config;
    },
    start() {
      unsubscribeConfig ??= onSnapshot(
        configRef,
        (snapshot) => {
          if (configForm.dataset.dirty !== "true") {
            fillForm(snapshot.exists() ? snapshot.data() : {});
          }
        },
        (error) => show(configMessage, `Falha ao carregar configuração: ${error.message}`),
      );
      unsubscribeRequests ??= onSnapshot(
        query(
          collection(db, "vip_payment_requests"),
          where("status", "==", "pending"),
          orderBy("createdAt", "desc"),
        ),
        renderRequests,
        (error) => {
          requestsContainer.replaceChildren();
          const message = document.createElement("p");
          message.className = "empty-state";
          message.textContent = `Falha ao carregar solicitações: ${error.message}`;
          requestsContainer.append(message);
        },
      );
      unsubscribeCoupons ??= onSnapshot(
        collection(db, "vip_coupons"),
        renderCoupons,
        (error) => {
          couponsContainer.replaceChildren();
          const message = document.createElement("p");
          message.className = "empty-state";
          message.textContent = `Falha ao carregar cupons: ${error.message}`;
          couponsContainer.append(message);
        },
      );
      providerSelect.addEventListener("change", syncProviderFields);
      editTokenButton.addEventListener("click", handleTokenEdit);
      couponTypeSelect.addEventListener("change", syncCouponValueField);
      couponCodeInput.addEventListener("input", uppercaseCouponCode);
      configForm.addEventListener("input", markConfigDirty);
      configForm.addEventListener("submit", handleConfigSubmit);
      couponForm.addEventListener("submit", handleCouponSubmit);
      syncCouponValueField();
    },
    stop() {
      unsubscribeConfig?.();
      unsubscribeConfig = undefined;
      unsubscribeRequests?.();
      unsubscribeRequests = undefined;
      unsubscribeCoupons?.();
      unsubscribeCoupons = undefined;
      providerSelect.removeEventListener("change", syncProviderFields);
      editTokenButton.removeEventListener("click", handleTokenEdit);
      couponTypeSelect.removeEventListener("change", syncCouponValueField);
      couponCodeInput.removeEventListener("input", uppercaseCouponCode);
      configForm.removeEventListener("input", markConfigDirty);
      configForm.removeEventListener("submit", handleConfigSubmit);
      couponForm.removeEventListener("submit", handleCouponSubmit);
      configForm.dataset.dirty = "false";
    },
  };
}
