const { initializeApp } = require("firebase-admin/app");
const { FieldValue, Timestamp, getFirestore } = require("firebase-admin/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const { HttpsError, onCall, onRequest } = require("firebase-functions/v2/https");
const {
  calculateCouponDiscount,
  normalizeCouponCode,
  VIP_PLAN_IDS,
  validateCouponSettings,
} = require("./vip-coupon-utils");

initializeApp();
setGlobalOptions({ region: "southamerica-east1", maxInstances: 10 });

const db = getFirestore();
const PUBLIC_CONFIG = db.doc("settings/payment_config");
const PRIVATE_CONFIG = db.doc("settings/private_vip_payment_config");
const PAYMENT_API = "https://api.mercadopago.com/v1/payments";
const PLAN_IDS = new Set(["bronze", "silver", "gold", "platinum"]);
const COUPONS = db.collection("vip_coupons");

function requireAdmin(request) {
  if (!request.auth || request.auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "Apenas administradores podem alterar a configuração.");
  }
}

function requireSignedIn(request) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Entre na sua conta para continuar.");
}

function getVipPricing(config, plan) {
  const pricing = config?.prices?.[plan];
  if (
    !pricing ||
    !Number.isSafeInteger(pricing.amountCents) ||
    pricing.amountCents <= 0 ||
    !Number.isSafeInteger(pricing.durationDays) ||
    pricing.durationDays < 1
  ) {
    throw new HttpsError("failed-precondition", "O preço deste plano ainda não foi configurado.");
  }
  return pricing;
}

function couponCodeFromRequest(value) {
  if (value == null || value === "") return null;
  try {
    return normalizeCouponCode(value);
  } catch (error) {
    throw new HttpsError("invalid-argument", error.message);
  }
}

function calculateCoupon(coupon, amountCents, plan) {
  try {
    return calculateCouponDiscount(coupon, amountCents, plan);
  } catch (error) {
    throw new HttpsError("failed-precondition", error.message);
  }
}

function parseCouponSettings(data) {
  const { discountType, discountValue } = data;
  const maxUses = data.maxUses == null || data.maxUses === "" ? null : data.maxUses;
  const planIds = data.planIds ?? VIP_PLAN_IDS;
  const expiresAtMillis =
    data.expiresAtMillis == null || data.expiresAtMillis === ""
      ? null
      : data.expiresAtMillis;
  try {
    validateCouponSettings(discountType, discountValue, maxUses, planIds, expiresAtMillis);
  } catch (error) {
    throw new HttpsError("invalid-argument", error.message);
  }
  return {
    discountType,
    discountValue,
    maxUses,
    planIds,
    expiresAt: expiresAtMillis == null ? null : Timestamp.fromMillis(expiresAtMillis),
  };
}

async function releaseVipCouponReservation(orderRef, status, extraFields = {}) {
  await db.runTransaction(async (transaction) => {
    const orderSnapshot = await transaction.get(orderRef);
    if (!orderSnapshot.exists || orderSnapshot.data().status !== "pending") return;
    const order = orderSnapshot.data();
    const couponRef = order.couponCode ? COUPONS.doc(order.couponCode) : null;
    const couponSnapshot = couponRef ? await transaction.get(couponRef) : null;
    if (couponSnapshot?.exists && !order.couponReservationReleased) {
      transaction.update(couponRef, {
        usedCount: Math.max(0, (couponSnapshot.data().usedCount ?? 0) - 1),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.update(orderRef, {
      status,
      couponReservationReleased: true,
      updatedAt: FieldValue.serverTimestamp(),
      ...extraFields,
    });
  });
}

async function reconcileVipPaymentCancellation(
  orderRef,
  order,
  payment,
  requestedCancelReason,
) {
  if (payment.status === "approved") {
    await activatePaidOrder(String(payment.id));
    return false;
  }
  if (["cancelled", "canceled", "rejected", "refunded", "charged_back", "expired"].includes(payment.status)) {
    const expiresAt = order.expiresAt?.toDate?.();
    const paymentWasExpired =
      payment.status === "expired" ||
      (expiresAt && expiresAt.getTime() <= Date.now());
    const cancelReason = ["cancelled", "canceled", "expired"].includes(payment.status)
      ? paymentWasExpired
        ? "expired"
        : requestedCancelReason ?? null
      : null;
    await releaseVipCouponReservation(
      orderRef,
      payment.status,
      cancelReason ? { cancelReason } : {},
    );
    return ["cancelled", "canceled", "expired"].includes(payment.status);
  }
  return false;
}

function validatePrices(prices) {
  if (!prices || typeof prices !== "object" || Array.isArray(prices)) {
    throw new HttpsError("invalid-argument", "Informe os preços e a duração dos planos.");
  }
  const normalized = {};
  for (const plan of PLAN_IDS) {
    const value = prices[plan];
    if (!value || !Number.isSafeInteger(value.amountCents) || value.amountCents <= 0 || value.amountCents > 10000000) {
      throw new HttpsError("invalid-argument", `Preço inválido para o plano ${plan}.`);
    }
    if (!Number.isSafeInteger(value.durationDays) || value.durationDays < 1 || value.durationDays > 3660) {
      throw new HttpsError("invalid-argument", `Duração inválida para o plano ${plan}.`);
    }
    normalized[plan] = {
      amountCents: value.amountCents,
      durationDays: value.durationDays,
    };
  }
  return normalized;
}

exports.saveVipCoupon = onCall(async (request) => {
  requireAdmin(request);
  const data = request.data ?? {};
  let code;
  try {
    code = normalizeCouponCode(data.code);
  } catch (error) {
    throw new HttpsError("invalid-argument", error.message);
  }
  const { discountType, discountValue, maxUses, planIds, expiresAt } = parseCouponSettings(data);
  if (data.active != null && typeof data.active !== "boolean") {
    throw new HttpsError("invalid-argument", "Estado do cupom inválido.");
  }
  const couponRef = COUPONS.doc(code);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(couponRef);
    const previous = snapshot.data();
    const usedCount = previous?.usedCount ?? 0;
    if (!Number.isSafeInteger(usedCount) || usedCount < 0) {
      throw new HttpsError("failed-precondition", "A contagem de usos deste cupom está inválida.");
    }
    if (maxUses != null && maxUses < usedCount) {
      throw new HttpsError("failed-precondition", "O limite não pode ser menor que os usos já registrados.");
    }
    transaction.set(couponRef, {
      code,
      discountType,
      discountValue,
      maxUses,
      planIds,
      expiresAt,
      usedCount,
      active: data.active ?? previous?.active ?? true,
      createdAt: previous?.createdAt ?? FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: request.auth.uid,
    });
  });
  return { code };
});

exports.validateVipCoupon = onCall(async (request) => {
  requireSignedIn(request);
  const plan = String(request.data?.plan ?? "").toLowerCase();
  if (!PLAN_IDS.has(plan)) throw new HttpsError("invalid-argument", "Plano VIP inválido.");
  const code = couponCodeFromRequest(request.data?.code);
  if (!code) throw new HttpsError("invalid-argument", "Informe o código do cupom.");

  const [configSnapshot, couponSnapshot] = await Promise.all([
    PUBLIC_CONFIG.get(),
    COUPONS.doc(code).get(),
  ]);
  const pricing = getVipPricing(configSnapshot.data(), plan);
  if (!couponSnapshot.exists) {
    throw new HttpsError("not-found", "Cupom não encontrado.");
  }
  const coupon = couponSnapshot.data();
  const discountCents = calculateCoupon(coupon, pricing.amountCents, plan);
  return {
    code,
    discountType: coupon.discountType,
    discountValue: coupon.discountValue,
    planIds: coupon.planIds ?? VIP_PLAN_IDS,
    baseAmountCents: pricing.amountCents,
    discountCents,
    finalAmountCents: pricing.amountCents - discountCents,
  };
});

exports.saveVipPaymentConfig = onCall(async (request) => {
  requireAdmin(request);
  const data = request.data ?? {};
  const provider = data.provider;
  if (!new Set(["pix_manual", "mercadopago"]).has(provider)) {
    throw new HttpsError("invalid-argument", "Método de pagamento inválido.");
  }
  const suppliedPrices = data.prices == null ? null : validatePrices(data.prices);
  const accessToken = typeof data.accessToken === "string" ? data.accessToken.trim() : "";
  if (accessToken && !/^(TEST-|APP_USR-)/.test(accessToken)) {
    throw new HttpsError("invalid-argument", "O Access Token informado não tem o formato esperado.");
  }

  let hasToken;
  await db.runTransaction(async (transaction) => {
    const [privateSnapshot, publicSnapshot] = await Promise.all([
      transaction.get(PRIVATE_CONFIG),
      transaction.get(PUBLIC_CONFIG),
    ]);
    const previousPrivate = privateSnapshot.data() ?? {};
    hasToken = accessToken.length > 0 || previousPrivate.accessToken?.length > 0;
    if (provider === "mercadopago" && !hasToken) {
      throw new HttpsError("failed-precondition", "Configure o Access Token do Mercado Pago antes de ativar esse método.");
    }

    transaction.set(PUBLIC_CONFIG, {
      schemaVersion: 1,
      provider,
      manualPixKey: typeof data.manualPixKey === "string" ? data.manualPixKey.trim().slice(0, 200) : "",
      manualBeneficiary: typeof data.manualBeneficiary === "string" ? data.manualBeneficiary.trim().slice(0, 120) : "",
      manualInstructions: typeof data.manualInstructions === "string" ? data.manualInstructions.trim().slice(0, 1000) : "",
      prices: suppliedPrices ?? publicSnapshot.data()?.prices ?? {},
      hasMercadoPagoToken: hasToken,
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: request.auth.uid,
    });
    if (accessToken) {
      transaction.set(PRIVATE_CONFIG, {
        accessToken,
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: request.auth.uid,
      }, { merge: true });
    }
  });
  return { hasMercadoPagoToken: hasToken };
});

exports.saveVipPlanPrice = onCall(async (request) => {
  requireAdmin(request);
  const { plan, amountCents, durationDays } = request.data ?? {};
  if (!PLAN_IDS.has(plan)) {
    throw new HttpsError("invalid-argument", "Plano VIP inválido.");
  }
  if (!Number.isSafeInteger(amountCents) || amountCents < 1 || amountCents > 10000000) {
    throw new HttpsError("invalid-argument", "O preço deve estar entre R$ 0,01 e R$ 100.000,00.");
  }
  if (!Number.isSafeInteger(durationDays) || durationDays < 1 || durationDays > 3660) {
    throw new HttpsError("invalid-argument", "A duração deve ser de 1 a 3.660 dias.");
  }

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(PUBLIC_CONFIG);
    const currentConfig = snapshot.data() ?? {};
    transaction.set(PUBLIC_CONFIG, {
      ...currentConfig,
      prices: {
        ...(currentConfig.prices ?? {}),
        [plan]: { amountCents, durationDays },
      },
      updatedAt: FieldValue.serverTimestamp(),
      updatedBy: request.auth.uid,
    }, { merge: true });
  });
  return { plan, amountCents, durationDays };
});

exports.createVipManualPixRequest = onCall(async (request) => {
  requireSignedIn(request);
  const uid = request.auth.uid;
  const plan = String(request.data?.plan ?? "").toLowerCase();
  if (!PLAN_IDS.has(plan)) throw new HttpsError("invalid-argument", "Plano VIP inválido.");
  const couponCode = couponCodeFromRequest(request.data?.couponCode);
  const couponRef = couponCode ? COUPONS.doc(couponCode) : null;
  const userRef = db.doc(`users/${uid}`);
  const requestRef = db.collection("vip_payment_requests").doc();
  const expectedAmountCents = request.data?.expectedAmountCents;

  const result = await db.runTransaction(async (transaction) => {
    const configSnapshot = await transaction.get(PUBLIC_CONFIG);
    const userSnapshot = await transaction.get(userRef);
    const couponSnapshot = couponRef ? await transaction.get(couponRef) : null;
    const config = configSnapshot.data();
    if (config?.provider !== "pix_manual" || !config.manualPixKey) {
      throw new HttpsError("failed-precondition", "O pagamento por Pix manual não está disponível.");
    }
    if (!userSnapshot.exists) {
      throw new HttpsError("failed-precondition", "O perfil do usuário não existe.");
    }
    const pricing = getVipPricing(config, plan);
    if (couponCode && !couponSnapshot?.exists) {
      throw new HttpsError("not-found", "Cupom não encontrado.");
    }
    const coupon = couponSnapshot?.data();
    const discountCents = coupon
      ? calculateCoupon(coupon, pricing.amountCents, plan)
      : 0;
    const amountCents = pricing.amountCents - discountCents;
    if (expectedAmountCents !== amountCents) {
      throw new HttpsError("failed-precondition", "O preço mudou. Valide o cupom novamente antes de continuar.");
    }
    const user = userSnapshot.data();
    transaction.set(requestRef, {
      uid,
      userName: user.name ?? "Atleta",
      email: user.email ?? "",
      plan,
      amountCents,
      baseAmountCents: pricing.amountCents,
      discountCents,
      ...(couponCode ? { couponCode } : {}),
      durationDays: pricing.durationDays,
      provider: "pix_manual",
      status: "pending",
      createdAt: FieldValue.serverTimestamp(),
    });
    if (couponRef && coupon) {
      transaction.update(couponRef, {
        usedCount: (coupon.usedCount ?? 0) + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    return { amountCents };
  });
  return { requestId: requestRef.id, amountCents: result.amountCents };
});

exports.createVipMercadoPagoPix = onCall(async (request) => {
  requireSignedIn(request);
  const uid = request.auth.uid;
  const plan = String(request.data?.plan ?? "").toLowerCase();
  if (!PLAN_IDS.has(plan)) throw new HttpsError("invalid-argument", "Plano VIP inválido.");
  const couponCode = couponCodeFromRequest(request.data?.couponCode);
  const couponRef = couponCode ? COUPONS.doc(couponCode) : null;
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000);

  const [configSnapshot, privateSnapshot, userSnapshot] = await Promise.all([
    PUBLIC_CONFIG.get(),
    PRIVATE_CONFIG.get(),
    db.doc(`users/${uid}`).get(),
  ]);
  const config = configSnapshot.data();
  const accessToken = privateSnapshot.data()?.accessToken;
  const user = userSnapshot.data();
  if (!config || config.provider !== "mercadopago" || !accessToken) {
    throw new HttpsError("failed-precondition", "O pagamento automático não está disponível.");
  }
  if (!user || typeof user.email !== "string" || !user.email.includes("@")) {
    throw new HttpsError("failed-precondition", "O perfil precisa ter um e-mail válido para pagar.");
  }

  const existingOrders = await db.collection("vip_payment_orders")
    .where("uid", "==", uid)
    .get();
  for (const existingOrderSnapshot of existingOrders.docs) {
    const existingOrder = existingOrderSnapshot.data();
    if (
      existingOrder.provider !== "mercadopago" ||
      existingOrder.status !== "pending"
    ) continue;
    if (vipOrderExpiresAt(existingOrder).getTime() > Date.now()) {
      throw new HttpsError(
        "already-exists",
        "Já existe um Pix VIP pendente. Retome ou cancele esse pagamento antes de criar outro.",
      );
    }
    const cancellation = await cancelVipMercadoPagoOrder(
      existingOrderSnapshot.id,
      uid,
      "expired",
    );
    if (cancellation.status === "approved") {
      throw new HttpsError(
        "failed-precondition",
        "O pagamento anterior foi aprovado e está sendo confirmado.",
      );
    }
    if (cancellation.status === "pending") {
      throw new HttpsError(
        "failed-precondition",
        "O pagamento anterior ainda está sendo encerrado.",
      );
    }
  }

  const orderRef = db.collection("vip_payment_orders").doc();
  let orderAmounts;
  await db.runTransaction(async (transaction) => {
    const currentConfigSnapshot = await transaction.get(PUBLIC_CONFIG);
    const currentConfig = currentConfigSnapshot.data();
    if (currentConfig?.provider !== "mercadopago") {
      throw new HttpsError("failed-precondition", "O pagamento automático não está disponível.");
    }
    const pricing = getVipPricing(currentConfig, plan);
    const couponSnapshot = couponRef ? await transaction.get(couponRef) : null;
    if (couponCode && !couponSnapshot?.exists) {
      throw new HttpsError("not-found", "Cupom não encontrado.");
    }
    const coupon = couponSnapshot?.data();
    const discountCents = coupon
      ? calculateCoupon(coupon, pricing.amountCents, plan)
      : 0;
    const amountCents = pricing.amountCents - discountCents;
    transaction.set(orderRef, {
      uid,
      plan,
      baseAmountCents: pricing.amountCents,
      amountCents,
      discountCents,
      ...(couponCode ? { couponCode } : {}),
      durationDays: pricing.durationDays,
      provider: "mercadopago",
      status: "pending",
      expiresAt: Timestamp.fromDate(expiresAt),
      createdAt: FieldValue.serverTimestamp(),
    });
    if (couponRef && coupon) {
      transaction.update(couponRef, {
        usedCount: (coupon.usedCount ?? 0) + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    orderAmounts = { amountCents, discountCents };
  });
  const amount = orderAmounts.amountCents / 100;
  const paymentPayload = {
    transaction_amount: amount,
    description: `Plano VIP ${plan.toUpperCase()} - Nosso Racha`,
    payment_method_id: "pix",
    date_of_expiration: expiresAt.toISOString(),
    payer: {
      email: user.email,
      first_name: (user.name ?? "Atleta").toString().trim().split(/\s+/)[0],
    },
    external_reference: orderRef.id,
    metadata: { type: "vip_subscription", uid, plan, order_id: orderRef.id },
  };

  let response;
  try {
    response = await fetch(PAYMENT_API, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
      "X-Idempotency-Key": `vip-${orderRef.id}`,
    },
      body: JSON.stringify(paymentPayload),
    });
  } catch (error) {
    await releaseVipCouponReservation(orderRef, "failed");
    throw new HttpsError("internal", "Não foi possível gerar o Pix do Mercado Pago.");
  }
  const payment = await response.json().catch(() => ({}));
  if (!response.ok || !payment.id || !payment.point_of_interaction?.transaction_data?.qr_code) {
    console.error("Mercado Pago VIP payment creation failed", response.status, payment.message ?? payment.error);
    await releaseVipCouponReservation(orderRef, "failed");
    throw new HttpsError("internal", "Não foi possível gerar o Pix do Mercado Pago.");
  }

  const qrCode = payment.point_of_interaction.transaction_data.qr_code;
  const qrCodeBase64 =
    payment.point_of_interaction.transaction_data.qr_code_base64 ?? null;
  const paymentExpiresAt =
    Date.parse(payment.date_of_expiration ?? "") || expiresAt.getTime();
  await orderRef.update({
    providerPaymentId: String(payment.id),
    qrCode,
    qrCodeBase64,
    expiresAt: Timestamp.fromMillis(paymentExpiresAt),
  });
  return {
    orderId: orderRef.id,
    paymentId: String(payment.id),
    qrCode,
    qrCodeBase64,
    expiresAt: new Date(paymentExpiresAt).toISOString(),
  };
});

function validateVipOrderId(orderId) {
  if (
    typeof orderId !== "string" ||
    !orderId.trim() ||
    orderId.length > 128 ||
    orderId.includes("/")
  ) {
    throw new HttpsError("invalid-argument", "Pedido de pagamento inválido.");
  }
}

async function getVipPaymentOrder(orderId, uid) {
  validateVipOrderId(orderId);
  const orderRef = db.doc(`vip_payment_orders/${orderId}`);
  const orderSnapshot = await orderRef.get();
  if (!orderSnapshot.exists || orderSnapshot.data().uid !== uid) {
    throw new HttpsError("not-found", "Pedido de pagamento não encontrado.");
  }
  const order = orderSnapshot.data();
  if (order.provider !== "mercadopago") {
    throw new HttpsError("failed-precondition", "Este pedido não é do Mercado Pago.");
  }
  return { orderRef, order };
}

function vipOrderExpiresAt(order) {
  const expiration = order.expiresAt?.toDate?.();
  if (expiration) return expiration;
  const createdAt = order.createdAt?.toDate?.();
  return createdAt
    ? new Date(createdAt.getTime() + 10 * 60 * 1000)
    : new Date(0);
}

async function getVipProviderPayment(orderId, order, uid) {
  if (!order.providerPaymentId) {
    throw new HttpsError("failed-precondition", "O pagamento ainda está sendo criado.");
  }
  const privateSnapshot = await PRIVATE_CONFIG.get();
  const accessToken = privateSnapshot.data()?.accessToken;
  if (!accessToken) {
    throw new HttpsError("failed-precondition", "A configuração do pagamento não está disponível.");
  }
  const paymentUrl = `${PAYMENT_API}/${encodeURIComponent(order.providerPaymentId)}`;
  let response;
  try {
    response = await fetch(paymentUrl, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
  } catch (error) {
    console.error("Mercado Pago VIP payment lookup failed", error);
    throw new HttpsError("unavailable", "Não foi possível consultar o pagamento.");
  }
  if (!response.ok) {
    console.error("Mercado Pago VIP payment lookup failed", response.status);
    throw new HttpsError("unavailable", "Não foi possível consultar o pagamento.");
  }
  const payment = await response.json().catch(() => null);
  if (
    !payment ||
    String(payment.id) !== String(order.providerPaymentId) ||
    payment.external_reference !== orderId ||
    payment.metadata?.uid !== uid ||
    payment.metadata?.type !== "vip_subscription"
  ) {
    throw new HttpsError("failed-precondition", "O pagamento não corresponde a este pedido.");
  }
  return { payment, paymentUrl, accessToken };
}

async function cancelVipMercadoPagoOrder(orderId, uid, cancelReason) {
  const { orderRef, order } = await getVipPaymentOrder(orderId, uid);
  if (order.status !== "pending") {
    return {
      cancelled: false,
      status: order.status,
      cancelReason: order.cancelReason ?? null,
    };
  }
  const { payment, paymentUrl, accessToken } =
    await getVipProviderPayment(orderId, order, uid);
  if (payment.status !== "pending") {
    const cancelled = await reconcileVipPaymentCancellation(
      orderRef,
      order,
      payment,
      cancelReason,
    );
    const updatedOrder = (await orderRef.get()).data();
    return {
      cancelled,
      status: updatedOrder?.status ?? payment.status,
      cancelReason: updatedOrder?.cancelReason ?? null,
    };
  }

  let response;
  try {
    response = await fetch(paymentUrl, {
      method: "PUT",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ status: "cancelled" }),
    });
  } catch (error) {
    console.error("Mercado Pago VIP payment cancellation failed", error);
    throw new HttpsError("unavailable", "Não foi possível cancelar o Pix no Mercado Pago.");
  }
  const cancelledPayment = await response.json().catch(() => null);
  if (!response.ok) {
    console.error(
      "Mercado Pago VIP payment cancellation failed",
      response.status,
      cancelledPayment?.message ?? cancelledPayment?.error,
    );
    throw new HttpsError("unavailable", "Não foi possível cancelar o Pix no Mercado Pago.");
  }
  if (
    !cancelledPayment ||
    String(cancelledPayment.id) !== String(order.providerPaymentId) ||
    cancelledPayment.external_reference !== orderId
  ) {
    throw new HttpsError("failed-precondition", "A resposta do Mercado Pago não corresponde a este pedido.");
  }
  if (cancelledPayment.status === "pending") {
    throw new HttpsError("unavailable", "O Mercado Pago ainda não confirmou o cancelamento do Pix.");
  }

  const cancelled = await reconcileVipPaymentCancellation(
    orderRef,
    order,
    cancelledPayment,
    cancelReason,
  );
  const updatedOrder = (await orderRef.get()).data();
  return {
    cancelled,
    status: updatedOrder?.status ?? cancelledPayment.status,
    cancelReason: updatedOrder?.cancelReason ?? null,
  };
}

exports.cancelVipMercadoPagoPix = onCall(async (request) => {
  requireSignedIn(request);
  const reason = request.data?.reason ?? "user";
  if (!["user", "expired"].includes(reason)) {
    throw new HttpsError("invalid-argument", "Motivo de cancelamento inválido.");
  }
  return cancelVipMercadoPagoOrder(
    request.data?.orderId,
    request.auth.uid,
    reason,
  );
});

exports.checkVipMercadoPagoPix = onCall(async (request) => {
  requireSignedIn(request);
  const { orderRef, order } = await getVipPaymentOrder(
    request.data?.orderId,
    request.auth.uid,
  );
  if (order.status !== "pending") {
    return {
      status: order.cancelReason === "expired" ? "expired" : order.status,
      cancelReason: order.cancelReason ?? null,
    };
  }
  const { payment } = await getVipProviderPayment(
    request.data.orderId,
    order,
    request.auth.uid,
  );
  if (payment.status === "approved") {
    await activatePaidOrder(String(payment.id));
  } else {
    await reconcileVipPaymentCancellation(orderRef, order, payment);
  }
  const updatedOrder = (await orderRef.get()).data();
  return {
    status: updatedOrder?.cancelReason === "expired"
      ? "expired"
      : updatedOrder?.status ?? payment.status,
    cancelReason: updatedOrder?.cancelReason ?? null,
  };
});

exports.getVipMercadoPagoOrder = onCall(async (request) => {
  requireSignedIn(request);
  const uid = request.auth.uid;
  const ordersSnapshot = await db.collection("vip_payment_orders")
    .where("uid", "==", uid)
    .get();
  const orders = ordersSnapshot.docs
    .map((document) => ({ ...document.data(), id: document.id }))
    .filter((order) => order.provider === "mercadopago")
    .sort((left, right) =>
      (right.createdAt?.toMillis?.() ?? 0) - (left.createdAt?.toMillis?.() ?? 0));
  const pendingOrder = orders.find((order) => order.status === "pending");

  if (pendingOrder) {
    const expiresAt = vipOrderExpiresAt(pendingOrder);
    if (expiresAt.getTime() <= Date.now()) {
      const cancellation = await cancelVipMercadoPagoOrder(
        pendingOrder.id,
        uid,
        "expired",
      );
      if (cancellation.status === "approved") {
        return {
          orderId: pendingOrder.id,
          plan: pendingOrder.plan,
          status: "approved",
        };
      }
      const updatedOrder = (await db.doc(
        `vip_payment_orders/${pendingOrder.id}`,
      ).get()).data();
      if (updatedOrder?.expirationNoticeDismissed === true) {
        return { status: "none" };
      }
      if (cancellation.status === "pending" ||
          cancellation.cancelReason === "expired") {
        return {
          orderId: pendingOrder.id,
          plan: pendingOrder.plan,
          status: "expired",
          expiresAt: expiresAt.toISOString(),
        };
      }
    } else {
      let qrCode = pendingOrder.qrCode;
      let qrCodeBase64 = pendingOrder.qrCodeBase64 ?? null;
      if (typeof qrCode !== "string" || !qrCode) {
        const { payment } = await getVipProviderPayment(
          pendingOrder.id,
          pendingOrder,
          uid,
        );
        if (payment.status === "approved") {
          await activatePaidOrder(String(payment.id));
          return {
            orderId: pendingOrder.id,
            plan: pendingOrder.plan,
            status: "approved",
          };
        }
        if (payment.status !== "pending") {
          const orderRef = db.doc(`vip_payment_orders/${pendingOrder.id}`);
          await reconcileVipPaymentCancellation(
            orderRef,
            pendingOrder,
            payment,
          );
          const updatedOrder = (await orderRef.get()).data();
          return {
            orderId: pendingOrder.id,
            plan: pendingOrder.plan,
            status: updatedOrder?.cancelReason === "expired"
              ? "expired"
              : updatedOrder?.status ?? payment.status,
            cancelReason: updatedOrder?.cancelReason ?? null,
            expiresAt: expiresAt.toISOString(),
          };
        }
        qrCode = payment.point_of_interaction?.transaction_data?.qr_code;
        qrCodeBase64 =
          payment.point_of_interaction?.transaction_data?.qr_code_base64 ?? null;
        if (typeof qrCode !== "string" || !qrCode) {
          throw new HttpsError("unavailable", "O Pix pendente não possui um QR Code disponível.");
        }
        await db.doc(`vip_payment_orders/${pendingOrder.id}`).update({
          qrCode,
          qrCodeBase64,
        });
      }
      return {
        orderId: pendingOrder.id,
        plan: pendingOrder.plan,
        status: "pending",
        qrCode,
        qrCodeBase64,
        expiresAt: expiresAt.toISOString(),
      };
    }
  }

  const expiredOrder = orders.find(
    (order) =>
      order.cancelReason === "expired" &&
      order.expirationNoticeDismissed !== true,
  );
  if (expiredOrder) {
    return {
      orderId: expiredOrder.id,
      plan: expiredOrder.plan,
      status: "expired",
      expiresAt: vipOrderExpiresAt(expiredOrder).toISOString(),
    };
  }
  return { status: "none" };
});

exports.acknowledgeVipPaymentExpiration = onCall(async (request) => {
  requireSignedIn(request);
  const { orderRef } = await getVipPaymentOrder(
    request.data?.orderId,
    request.auth.uid,
  );
  await db.runTransaction(async (transaction) => {
    const orderSnapshot = await transaction.get(orderRef);
    const order = orderSnapshot.data();
    const expiredPendingOrder =
      order?.status === "pending" &&
      vipOrderExpiresAt(order).getTime() <= Date.now();
    if (order?.cancelReason !== "expired" && !expiredPendingOrder) {
      throw new HttpsError("failed-precondition", "Este pagamento não expirou.");
    }
    transaction.update(orderRef, {
      ...(expiredPendingOrder ? { cancelReason: "expired" } : {}),
      expirationNoticeDismissed: true,
      expirationNoticeDismissedAt: FieldValue.serverTimestamp(),
    });
  });
  return { acknowledged: true };
});

async function activatePaidOrder(paymentId) {
  const matchingOrders = await db.collection("vip_payment_orders")
    .where("providerPaymentId", "==", String(paymentId))
    .limit(1)
    .get();
  if (matchingOrders.empty) return;

  const privateSnapshot = await PRIVATE_CONFIG.get();
  const token = privateSnapshot.data()?.accessToken;
  if (!token) throw new Error("VIP payment credential missing.");

  const response = await fetch(`${PAYMENT_API}/${encodeURIComponent(paymentId)}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new Error(`Mercado Pago lookup returned ${response.status}.`);
  const payment = await response.json();

  const orderId = payment.external_reference;
  if (typeof orderId !== "string" || !orderId || matchingOrders.docs[0].id !== orderId) return;
  const orderRef = db.doc(`vip_payment_orders/${orderId}`);
  await db.runTransaction(async (transaction) => {
    const orderSnapshot = await transaction.get(orderRef);
    if (!orderSnapshot.exists || orderSnapshot.data().status !== "pending") return;
    const order = orderSnapshot.data();
    if (
      order.provider !== "mercadopago" ||
      order.providerPaymentId !== String(payment.id) ||
      payment.metadata?.type !== "vip_subscription" ||
      payment.metadata?.uid !== order.uid ||
      payment.metadata?.plan !== order.plan ||
      payment.currency_id !== "BRL" ||
      Math.round(Number(payment.transaction_amount) * 100) !== order.amountCents
    ) return;

    if (payment.status !== "approved") {
      if (!["cancelled", "canceled", "rejected", "refunded", "charged_back", "expired"].includes(payment.status)) {
        return;
      }
      const couponRef = order.couponCode ? COUPONS.doc(order.couponCode) : null;
      const couponSnapshot = couponRef ? await transaction.get(couponRef) : null;
      if (couponSnapshot?.exists && !order.couponReservationReleased) {
        transaction.update(couponRef, {
          usedCount: Math.max(0, (couponSnapshot.data().usedCount ?? 0) - 1),
          updatedAt: FieldValue.serverTimestamp(),
        });
      }
      transaction.update(orderRef, {
        status: payment.status,
        couponReservationReleased: true,
        updatedAt: FieldValue.serverTimestamp(),
        ...(
          ["cancelled", "canceled", "expired"].includes(payment.status) &&
          (payment.status === "expired" ||
            vipOrderExpiresAt(order).getTime() <= Date.now())
            ? { cancelReason: "expired" }
            : {}
        ),
      });
      return;
    }

    const userRef = db.doc(`users/${order.uid}`);
    const userSnapshot = await transaction.get(userRef);
    if (!userSnapshot.exists) throw new Error("VIP payer document not found.");
    const user = userSnapshot.data();
    const now = new Date();
    const currentExpiration = user.vipExpiresAt?.toDate?.() ?? null;
    const startsAt = currentExpiration && currentExpiration > now ? currentExpiration : now;
    startsAt.setDate(startsAt.getDate() + order.durationDays);
    const expiresAt = Timestamp.fromDate(startsAt);

    transaction.update(userRef, {
      vipPlan: order.plan,
      vipExpiresAt: expiresAt,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.set(db.doc(`vip_public_badges/${order.uid}`), {
      uid: order.uid,
      plan: order.plan,
      expiresAt,
      updatedAt: FieldValue.serverTimestamp(),
    });
    transaction.update(orderRef, {
      status: "approved",
      approvedAt: FieldValue.serverTimestamp(),
      expiresAt,
    });
  });
}

exports.rejectVipManualPaymentRequest = onCall(async (request) => {
  requireAdmin(request);
  const requestId = request.data?.requestId;
  if (typeof requestId !== "string" || requestId.trim().length === 0) {
    throw new HttpsError("invalid-argument", "Solicitação de pagamento inválida.");
  }
  const requestRef = db.doc(`vip_payment_requests/${requestId}`);
  await db.runTransaction(async (transaction) => {
    const requestSnapshot = await transaction.get(requestRef);
    if (!requestSnapshot.exists || requestSnapshot.data().status !== "pending") {
      throw new HttpsError("failed-precondition", "Esta solicitação já foi analisada.");
    }
    const paymentRequest = requestSnapshot.data();
    const couponRef = paymentRequest.couponCode
      ? COUPONS.doc(paymentRequest.couponCode)
      : null;
    const couponSnapshot = couponRef ? await transaction.get(couponRef) : null;
    transaction.update(requestRef, {
      status: "rejected",
      reviewedAt: FieldValue.serverTimestamp(),
      reviewedBy: request.auth.uid,
    });
    if (couponSnapshot?.exists) {
      transaction.update(couponRef, {
        usedCount: Math.max(0, (couponSnapshot.data().usedCount ?? 0) - 1),
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
  });
  return { rejected: true };
});

exports.mercadoPagoVipWebhook = onRequest(async (request, response) => {
  if (request.method !== "POST") {
    response.status(405).send("Method not allowed");
    return;
  }
  const paymentId = request.body?.data?.id ?? request.query?.["data.id"];
  if (!paymentId || !/^\d+$/.test(String(paymentId))) {
    response.status(400).send("Invalid payment id");
    return;
  }
  try {
    await activatePaidOrder(String(paymentId));
    response.status(200).send("ok");
  } catch (error) {
    console.error("VIP Mercado Pago webhook failed", error);
    response.status(500).send("Unable to process payment notification");
  }
});
