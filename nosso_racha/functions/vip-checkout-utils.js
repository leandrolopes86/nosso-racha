function checkoutUrlForPreference(accessToken, preference) {
  const checkoutUrl = accessToken.startsWith("TEST-")
    ? preference.sandbox_init_point
    : preference.init_point;
  if (typeof checkoutUrl !== "string" || !URL.canParse(checkoutUrl)) {
    return null;
  }
  const url = new URL(checkoutUrl);
  const allowedHost =
    url.hostname === "mercadopago.com.br" ||
    url.hostname.endsWith(".mercadopago.com.br") ||
    url.hostname === "mercadopago.com" ||
    url.hostname.endsWith(".mercadopago.com");
  return url.protocol === "https:" &&
      allowedHost &&
      url.username === "" &&
      url.password === ""
    ? checkoutUrl
    : null;
}

function isApprovedVipCheckoutPayment(orderId, order, payment) {
  const validOrder = order.provider === "mercadopago_checkout" &&
    (order.status === "pending" ||
      ["cancelled", "expired"].includes(order.status));
  const validMetadata =
    (payment.metadata?.type == null ||
      payment.metadata.type === "vip_subscription") &&
    (payment.metadata?.uid == null || payment.metadata.uid === order.uid) &&
    (payment.metadata?.plan == null || payment.metadata.plan === order.plan);
  return validOrder &&
    payment.status === "approved" &&
    payment.external_reference === orderId &&
    payment.currency_id === "BRL" &&
    Math.round(Number(payment.transaction_amount) * 100) === order.amountCents &&
    validMetadata;
}

function validateVipRefundPayment(orderId, order, payment) {
  const isSupportedOrder = order.provider === "mercadopago" ||
    order.provider === "mercadopago_checkout";
  const paymentMatchesOrder =
    payment.status === "approved" &&
    String(payment.id) === String(order.providerPaymentId) &&
    payment.external_reference === orderId &&
    payment.currency_id === "BRL" &&
    Math.round(Number(payment.transaction_amount) * 100) === order.amountCents;
  const checkoutMetadataMatches = order.provider !== "mercadopago_checkout" ||
    (payment.metadata?.type == null ||
      payment.metadata.type === "vip_subscription") &&
    (payment.metadata?.uid == null || payment.metadata.uid === order.uid) &&
    (payment.metadata?.plan == null || payment.metadata.plan === order.plan);
  return isSupportedOrder && paymentMatchesOrder && checkoutMetadataMatches;
}

function isVipRefundWithinWindow(approvalMillis, nowMillis = Date.now()) {
  const windowMillis = 7 * 24 * 60 * 60 * 1000;
  return Number.isFinite(approvalMillis) &&
    approvalMillis <= nowMillis &&
    nowMillis - approvalMillis <= windowMillis;
}

function summarizeVipRefunds(refunds, paymentId, amountCents) {
  const matchingRefunds = refunds.filter(
    (refund) => String(refund.payment_id) === String(paymentId),
  );
  const approvedRefunds = matchingRefunds.filter(
    (refund) => refund.status === "approved",
  );
  const approvedAmountCents = approvedRefunds.reduce(
    (total, refund) => {
      const amount = Number(refund.amount);
      return Number.isFinite(amount) && amount > 0
        ? total + Math.round(amount * 100)
        : total;
    },
    0,
  );
  const pendingRefunds = matchingRefunds.filter(
    (refund) => refund.status === "pending" || refund.status === "in_process",
  );

  return {
    approvedAmountCents,
    approvedRefundIds: approvedRefunds.map((refund) => String(refund.id)),
    hasPendingRefund: pendingRefunds.length > 0,
    pendingRefundIds: pendingRefunds.map((refund) => String(refund.id)),
    rejectedRefundIds: matchingRefunds
      .filter((refund) => refund.status === "rejected")
      .map((refund) => String(refund.id)),
    status:
      approvedAmountCents >= amountCents
        ? "refunded"
        : pendingRefunds.length > 0
          ? "pending"
          : approvedAmountCents > 0
            ? "partial"
            : "none",
  };
}

module.exports = {
  checkoutUrlForPreference,
  isApprovedVipCheckoutPayment,
  isVipRefundWithinWindow,
  summarizeVipRefunds,
  validateVipRefundPayment,
};
