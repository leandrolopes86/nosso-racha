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
const REFUND_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;

function formatPrice(cents) {
  if (!Number.isSafeInteger(cents)) return "—";
  return new Intl.NumberFormat("pt-BR", {
    style: "currency",
    currency: "BRL",
  }).format(cents / 100);
}

function formatDate(value) {
  if (!Number.isFinite(value)) return "Data indisponível";
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(value));
}

function statusLabel(status, refundStatus) {
  if (refundStatus === "refunded") return "Devolvido";
  if (refundStatus === "partial") return "Devolução parcial";
  if (refundStatus === "pending" || refundStatus === "processing") {
    return "Devolução em processamento";
  }
  const labels = {
    pending: "Pendente",
    approved: "Aprovado",
    rejected: "Recusado",
    cancelled: "Cancelado",
    canceled: "Cancelado",
    expired: "Expirado",
    refunded: "Devolvido",
  };
  return labels[status] ?? status ?? "Sem situação";
}

function paymentProviderLabel(payment) {
  if (payment.kind === "manual") return "Pix manual";
  return payment.provider === "mercadopago_checkout"
    ? "Mercado Pago · Checkout Pro"
    : "Mercado Pago · Pix";
}

function isRefundEligible(payment) {
  const approvalMillis = payment.approvedAtMillis;
  return (
    payment.kind === "automatic" &&
    payment.status === "approved" &&
    payment.refundStatus !== "partial" &&
    Number.isFinite(approvalMillis) &&
    approvalMillis <= Date.now() &&
    Date.now() - approvalMillis <= REFUND_WINDOW_MS
  );
}

function createTextElement(tagName, className, text) {
  const element = document.createElement(tagName);
  if (className) element.className = className;
  element.textContent = text;
  return element;
}

export function initializeVipPaymentHistory({
  showDashboardMessage,
  hideDashboardMessage,
}) {
  const list = document.querySelector("#vipPaymentHistoryList");
  const message = document.querySelector("#vipPaymentHistoryMessage");
  const summary = document.querySelector("#vipPaymentHistorySummary");
  const refreshButton = document.querySelector("#refreshVipPaymentHistory");
  const searchInput = document.querySelector("#vipPaymentHistorySearch");
  const statusSelect = document.querySelector("#vipPaymentHistoryStatus");
  const functions = getFunctions(undefined, "southamerica-east1");
  const listPaymentsCallable = httpsCallable(functions, "listVipPaymentHistory");
  const refundPaymentCallable = httpsCallable(
    functions,
    "refundVipMercadoPagoPayment",
  );
  let payments = [];
  let isLoading = false;
  let isStarted = false;
  let loadGeneration = 0;
  const busyPaymentIds = new Set();

  const showMessage = (text, kind = "error") => {
    message.textContent = text;
    message.classList.remove("hidden", "is-success", "is-info");
    if (kind === "success") message.classList.add("is-success");
    if (kind === "info") message.classList.add("is-info");
  };

  const hideMessage = () => {
    message.textContent = "";
    message.classList.add("hidden");
    message.classList.remove("is-success", "is-info");
  };

  const matchesFilters = (payment) => {
    const search = searchInput.value.trim().toLocaleLowerCase("pt-BR");
    const selectedStatus = statusSelect.value;
    const effectiveStatus =
      payment.refundStatus === "refunded"
        ? "refunded"
        : payment.refundStatus === "partial"
          ? "partial"
        : payment.refundStatus === "pending" ||
            payment.refundStatus === "processing"
          ? "pending"
          : payment.status;
    const text = [
      payment.id,
      payment.uid,
      payment.userName,
      payment.email,
      payment.plan,
      payment.provider,
      paymentProviderLabel(payment),
    ]
      .filter(Boolean)
      .join(" ")
      .toLocaleLowerCase("pt-BR");
    return (
      (!search || text.includes(search)) &&
      (selectedStatus === "all" || effectiveStatus === selectedStatus)
    );
  };

  const render = () => {
    list.replaceChildren();
    const filteredPayments = payments.filter(matchesFilters);
    const eligibleCount = payments.filter(
      (payment) =>
        isRefundEligible(payment) &&
        (!payment.refundStatus || payment.refundStatus === "failed"),
    ).length;
    summary.textContent =
      `${filteredPayments.length} pagamento(s) exibido(s) · ` +
      `${eligibleCount} elegível(is) para devolução`;

    if (filteredPayments.length === 0) {
      list.append(
        createTextElement(
          "p",
          "empty-state",
          payments.length === 0
            ? "Nenhum pagamento VIP encontrado."
            : "Nenhum pagamento corresponde aos filtros.",
        ),
      );
      return;
    }

    for (const payment of filteredPayments) {
      const card = document.createElement("article");
      card.className = "venue-request-card vip-payment-history-card";

      const header = document.createElement("div");
      header.className = "venue-request-header";
      const identity = document.createElement("div");
      identity.append(
        createTextElement(
          "h2",
          "venue-request-name",
          payment.userName || "Usuário",
        ),
        createTextElement(
          "p",
          "muted mt-1",
          payment.email || `UID: ${payment.uid || "indisponível"}`,
        ),
      );
      const status = createTextElement(
        "span",
        `payment-status-badge ${payment.refundStatus === "refunded" ? "is-refunded" : ""}`,
        statusLabel(payment.status, payment.refundStatus),
      );
      header.append(identity, status);

      const details = document.createElement("div");
      details.className = "vip-payment-history-details";
      const planLabel = PLAN_LABELS[payment.plan] ?? payment.plan ?? "—";
      details.append(
        createTextElement(
          "p",
          "venue-request-address",
          `${paymentProviderLabel(payment)} · Plano ${planLabel}`,
        ),
        createTextElement(
          "p",
          "venue-request-address",
          `Valor: ${formatPrice(payment.amountCents)} · Criado: ${formatDate(payment.createdAtMillis)}`,
        ),
        createTextElement(
          "p",
          "venue-request-address",
          payment.approvedAtMillis
            ? `Aprovado: ${formatDate(payment.approvedAtMillis)}`
            : `Identificador: ${payment.id}`,
        ),
      );
      if (payment.refundStatus === "refunded") {
        details.append(
          createTextElement(
            "p",
            "venue-request-address",
            `Devolvido: ${formatDate(payment.refundAtMillis)} · ${formatPrice(payment.refundAmountCents)}`,
          ),
        );
        if (payment.refundEntitlementAdjustmentRequired) {
          details.append(
            createTextElement(
              "p",
              "notice is-info",
              "A devolução foi confirmada, mas o acesso VIP precisa de revisão manual.",
            ),
          );
        }
      } else if (payment.refundStatus === "partial") {
        details.append(
          createTextElement(
            "p",
            "venue-request-address",
            `Devolução parcial registrada: ${formatPrice(payment.refundAmountCents)}. Confira o restante diretamente no Mercado Pago.`,
          ),
        );
      } else if (
        (payment.refundStatus === "pending" ||
          payment.refundStatus === "processing") &&
        payment.refundAmountCents > 0
      ) {
        details.append(
          createTextElement(
            "p",
            "venue-request-address",
            `Devolução em processamento · valor já aprovado: ${formatPrice(payment.refundAmountCents)}`,
          ),
        );
      }

      const footer = document.createElement("div");
      footer.className = "venue-request-footer";
      footer.append(
        createTextElement(
          "small",
          "muted",
          `ID: ${payment.id}`,
        ),
      );
      if (payment.kind === "manual" && payment.status === "approved") {
        footer.append(
          createTextElement(
            "small",
            "muted",
            "Devolução manual fora do Mercado Pago",
          ),
        );
      } else if (payment.kind === "automatic") {
        const isRefundInProgress =
          payment.refundStatus === "pending" ||
          payment.refundStatus === "processing";
        const eligible = isRefundEligible(payment);
        if (
          payment.refundStatus !== "refunded" &&
          (eligible || isRefundInProgress)
        ) {
          const button = document.createElement("button");
          button.type = "button";
          button.className = "button button-outline button-small";
          button.textContent = isRefundInProgress
            ? "Verificar devolução"
            : payment.refundStatus === "failed"
              ? "Tentar devolução novamente"
              : "Solicitar devolução integral";
          button.disabled = busyPaymentIds.has(payment.id);
          button.addEventListener("click", () => requestRefund(payment, button));
          footer.append(button);
        }
      }

      card.append(header, details, footer);
      list.append(card);
    }
  };

  const loadPayments = async () => {
    if (isLoading) return;
    isLoading = true;
    refreshButton.disabled = true;
    hideMessage();
    const generation = ++loadGeneration;
    try {
      const result = await listPaymentsCallable();
      if (!isStarted || generation !== loadGeneration) return;
      const data = result.data;
      payments = Array.isArray(data?.payments) ? data.payments : [];
      render();
      if (data?.truncated === true) {
        showMessage(
          "Exibindo os 200 pagamentos mais recentes por tipo. Use a busca para localizar os registros carregados.",
          "info",
        );
      }
    } catch (error) {
      if (!isStarted || generation !== loadGeneration) return;
      showMessage(`Não foi possível carregar os pagamentos: ${error.message}`);
      if (payments.length === 0) {
        list.replaceChildren(
          createTextElement("p", "empty-state", "Falha ao carregar pagamentos."),
        );
      }
    } finally {
      if (generation === loadGeneration) {
        isLoading = false;
        refreshButton.disabled = false;
      }
    }
  };

  async function requestRefund(payment, button) {
    const isRetry =
      payment.refundStatus === "pending" ||
      payment.refundStatus === "processing" ||
      payment.refundStatus === "failed";
    if (
      !isRetry &&
      !window.confirm(
        `Confirmar devolução INTEGRAL de ${formatPrice(payment.amountCents)} para ${payment.userName || payment.email || payment.uid}? O Mercado Pago processará o estorno e o acesso VIP relacionado será ajustado.`,
      )
    ) {
      return;
    }

    busyPaymentIds.add(payment.id);
    button.disabled = true;
    hideMessage();
    try {
      const result = await refundPaymentCallable({ orderId: payment.id });
      if (result.data?.status === "refunded") {
        showMessage(
          `Devolução de ${formatPrice(result.data.refundAmountCents)} confirmada pelo Mercado Pago.`,
          "success",
        );
      } else if (result.data?.status === "partial") {
        showMessage(
          "Foi identificada uma devolução parcial. Verifique o pagamento diretamente no Mercado Pago antes de tomar outra ação.",
          "info",
        );
      } else {
        showMessage(
          "O Mercado Pago recebeu a solicitação. Atualize o status para confirmar a conclusão.",
          "info",
        );
      }
      await loadPayments();
      showDashboardMessage(
        result.data?.status === "refunded"
          ? "Devolução VIP confirmada pelo Mercado Pago."
          : result.data?.status === "partial"
            ? "Uma devolução parcial foi identificada; confira o Mercado Pago."
            : "Solicitação de devolução enviada ao Mercado Pago.",
        "success",
      );
    } catch (error) {
      showMessage(`Não foi possível concluir a devolução: ${error.message}`);
      showDashboardMessage(
        `Não foi possível concluir a devolução: ${error.message}`,
      );
    } finally {
      busyPaymentIds.delete(payment.id);
      render();
    }
  }

  const handleSearch = () => render();

  return {
    start() {
      if (isStarted) return;
      isStarted = true;
      refreshButton.addEventListener("click", loadPayments);
      searchInput.addEventListener("input", handleSearch);
      statusSelect.addEventListener("change", handleSearch);
      void loadPayments();
    },
    stop() {
      isStarted = false;
      loadGeneration++;
      isLoading = false;
      refreshButton.removeEventListener("click", loadPayments);
      searchInput.removeEventListener("input", handleSearch);
      statusSelect.removeEventListener("change", handleSearch);
      busyPaymentIds.clear();
    },
  };
}
