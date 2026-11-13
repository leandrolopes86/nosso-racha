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
const {
  checkoutUrlForPreference,
  isApprovedVipCheckoutPayment,
  isVipRefundWithinWindow,
  summarizeVipRefunds,
  validateVipRefundPayment,
} = require("./vip-checkout-utils");

initializeApp();
setGlobalOptions({ region: "southamerica-east1", maxInstances: 10 });

const db = getFirestore();
const PUBLIC_CONFIG = db.doc("settings/payment_config");
const PRIVATE_CONFIG = db.doc("settings/private_vip_payment_config");
const PAYMENT_API = "https://api.mercadopago.com/v1/payments";
const CHECKOUT_PREFERENCES_API = "https://api.mercadopago.com/checkout/preferences";
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
      !["mercadopago", "mercadopago_checkout"].includes(existingOrder.provider) ||
      existingOrder.status !== "pending"
    ) continue;
    if (vipOrderExpiresAt(existingOrder).getTime() > Date.now()) {
      throw new HttpsError(
        "already-exists",
        "Já existe um pagamento VIP pendente. Retome ou cancele esse pagamento antes de criar outro.",
      );
    }
    const cancellation = existingOrder.provider === "mercadopago_checkout"
      ? await cancelVipMercadoPagoCheckoutOrder(
        existingOrderSnapshot.id,
        uid,
        "expired",
      )
      : await cancelVipMercadoPagoOrder(
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

exports.createVipMercadoPagoCheckout = onCall(async (request) => {
  requireSignedIn(request);
  const uid = request.auth.uid;
  const plan = String(request.data?.plan ?? "").toLowerCase();
  if (!PLAN_IDS.has(plan)) {
    throw new HttpsError("invalid-argument", "Plano VIP inválido.");
  }
  const couponCode = couponCodeFromRequest(request.data?.couponCode);
  const couponRef = couponCode ? COUPONS.doc(couponCode) : null;
  const [configSnapshot, privateSnapshot, userSnapshot] = await Promise.all([
    PUBLIC_CONFIG.get(),
    PRIVATE_CONFIG.get(),
    db.doc(`users/${uid}`).get(),
  ]);
  const config = configSnapshot.data();
  const accessToken = privateSnapshot.data()?.accessToken;
  const user = userSnapshot.data();
  if (!config || config.provider !== "mercadopago" || !accessToken) {
    throw new HttpsError(
      "failed-precondition",
      "O pagamento automático não está disponível.",
    );
  }
  if (!user || typeof user.email !== "string" || !user.email.includes("@")) {
    throw new HttpsError(
      "failed-precondition",
      "O perfil precisa ter um e-mail válido para pagar.",
    );
  }

  const existingOrders = await db.collection("vip_payment_orders")
    .where("uid", "==", uid)
    .get();
  for (const existingOrderSnapshot of existingOrders.docs) {
    const existingOrder = existingOrderSnapshot.data();
    if (
      !["mercadopago", "mercadopago_checkout"].includes(existingOrder.provider) ||
      existingOrder.status !== "pending"
    ) continue;
    if (vipOrderExpiresAt(existingOrder).getTime() > Date.now()) {
      throw new HttpsError(
        "already-exists",
        "Já existe um pagamento VIP pendente. Retome ou cancele esse pagamento antes de criar outro.",
      );
    }
    const cancellation = existingOrder.provider === "mercadopago_checkout"
      ? await cancelVipMercadoPagoCheckoutOrder(
        existingOrderSnapshot.id,
        uid,
        "expired",
      )
      : await cancelVipMercadoPagoOrder(
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
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000);
  let orderAmounts;
  await db.runTransaction(async (transaction) => {
    const currentConfigSnapshot = await transaction.get(PUBLIC_CONFIG);
    const currentConfig = currentConfigSnapshot.data();
    if (currentConfig?.provider !== "mercadopago") {
      throw new HttpsError(
        "failed-precondition",
        "O pagamento automático não está disponível.",
      );
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
      provider: "mercadopago_checkout",
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
    orderAmounts = { amountCents };
  });

  const now = new Date();
  const preferencePayload = {
    items: [{
      id: `vip-${plan}`,
      title: `Plano VIP ${plan.toUpperCase()} - Nosso Racha`,
      quantity: 1,
      currency_id: "BRL",
      unit_price: orderAmounts.amountCents / 100,
    }],
    payer: { email: user.email },
    external_reference: orderRef.id,
    notification_url: "https://southamerica-east1-nosso-racha.cloudfunctions.net/mercadoPagoVipWebhook",
    back_urls: {
      success: "nosso-racha:///vip-checkout-return",
      failure: "nosso-racha:///vip-checkout-return",
      pending: "nosso-racha:///vip-checkout-return",
    },
    auto_return: "approved",
    expires: true,
    expiration_date_from: new Date(now.getTime() - 60 * 1000).toISOString(),
    expiration_date_to: expiresAt.toISOString(),
    metadata: {
      type: "vip_subscription",
      uid,
      plan,
      order_id: orderRef.id,
    },
  };

  let response;
  try {
    response = await fetch(CHECKOUT_PREFERENCES_API, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
        "X-Idempotency-Key": `vip-checkout-${orderRef.id}`,
      },
      body: JSON.stringify(preferencePayload),
    });
  } catch (error) {
    console.error("Mercado Pago VIP preference creation failed", error);
    await releaseVipCouponReservation(orderRef, "failed");
    throw new HttpsError(
      "internal",
      "Não foi possível iniciar o checkout do Mercado Pago.",
    );
  }

  const preference = await response.json().catch(() => ({}));
  const checkoutUrl = checkoutUrlForPreference(accessToken, preference);
  if (
    !response.ok ||
    typeof preference.id !== "string" ||
    checkoutUrl == null
  ) {
    console.error(
      "Mercado Pago VIP preference creation failed",
      response.status,
      preference.message ?? preference.error,
    );
    await releaseVipCouponReservation(orderRef, "failed");
    throw new HttpsError(
      "internal",
      "Não foi possível iniciar o checkout do Mercado Pago.",
    );
  }

  await orderRef.update({
    checkoutPreferenceId: preference.id,
    checkoutUrl,
  });
  return {
    orderId: orderRef.id,
    checkoutUrl,
    expiresAt: expiresAt.toISOString(),
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

async function getVipCheckoutPaymentOrder(orderId, uid) {
  validateVipOrderId(orderId);
  const orderRef = db.doc(`vip_payment_orders/${orderId}`);
  const orderSnapshot = await orderRef.get();
  if (
    !orderSnapshot.exists ||
    orderSnapshot.data().uid !== uid ||
    orderSnapshot.data().provider !== "mercadopago_checkout"
  ) {
    throw new HttpsError("not-found", "Pedido de checkout não encontrado.");
  }
  return { orderRef, order: orderSnapshot.data() };
}

async function getVipCheckoutPayments(orderId) {
  const privateSnapshot = await PRIVATE_CONFIG.get();
  const accessToken = privateSnapshot.data()?.accessToken;
  if (!accessToken) {
    throw new HttpsError(
      "failed-precondition",
      "A configuração do pagamento não está disponível.",
    );
  }
  const params = new URLSearchParams({
    external_reference: orderId,
    sort: "date_created",
    criteria: "desc",
    limit: "50",
  });
  let response;
  try {
    response = await fetch(`${PAYMENT_API}/search?${params}`, {
      headers: { Authorization: `Bearer ${accessToken}` },
    });
  } catch (error) {
    console.error("Mercado Pago VIP checkout payment search failed", error);
    throw new HttpsError(
      "unavailable",
      "Não foi possível consultar o pagamento no Mercado Pago.",
    );
  }
  const result = await response.json().catch(() => null);
  if (!response.ok || !Array.isArray(result?.results)) {
    console.error(
      "Mercado Pago VIP checkout payment search failed",
      response.status,
    );
    throw new HttpsError(
      "unavailable",
      "Não foi possível consultar o pagamento no Mercado Pago.",
    );
  }
  return {
    accessToken,
    payments: result.results.filter(
      (payment) => payment?.external_reference === orderId,
    ),
  };
}

async function activateVipCheckoutPayment(orderId, payments) {
  const approvedPayment = payments.find(
    (payment) => payment?.status === "approved" && payment.id != null,
  );
  if (!approvedPayment) return false;
  await activatePaidOrder(String(approvedPayment.id));
  const updatedOrder = (await db.doc(
    `vip_payment_orders/${orderId}`,
  ).get()).data();
  if (updatedOrder?.status !== "approved") {
    throw new HttpsError(
      "failed-precondition",
      "O pagamento aprovado não corresponde ao valor do pedido VIP.",
    );
  }
  return true;
}

async function updateVipCheckoutPreference(order, accessToken, expiresAt) {
  if (!order.checkoutPreferenceId) {
    throw new HttpsError(
      "failed-precondition",
      "O checkout ainda está sendo criado.",
    );
  }
  let response;
  try {
    response = await fetch(
      `${CHECKOUT_PREFERENCES_API}/${encodeURIComponent(order.checkoutPreferenceId)}`,
      {
        method: "PUT",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          expires: true,
          expiration_date_to: expiresAt.toISOString(),
        }),
      },
    );
  } catch (error) {
    console.error("Mercado Pago VIP checkout expiration failed", error);
    throw new HttpsError(
      "unavailable",
      "Não foi possível encerrar o checkout no Mercado Pago.",
    );
  }
  const result = await response.json().catch(() => null);
  if (!response.ok || String(result?.id) !== String(order.checkoutPreferenceId)) {
    console.error(
      "Mercado Pago VIP checkout expiration failed",
      response.status,
      result?.message ?? result?.error,
    );
    throw new HttpsError(
      "unavailable",
      "Não foi possível encerrar o checkout no Mercado Pago.",
    );
  }
}

async function cancelVipCheckoutPayment(orderId, payment, accessToken) {
  if (payment.status === "approved") {
    await activateVipCheckoutPayment(orderId, [payment]);
    return "approved";
  }
  if (payment.status !== "pending") return payment.status;
  let response;
  try {
    response = await fetch(
      `${PAYMENT_API}/${encodeURIComponent(payment.id)}`,
      {
        method: "PUT",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ status: "cancelled" }),
      },
    );
  } catch (error) {
    console.error("Mercado Pago VIP checkout payment cancellation failed", error);
    throw new HttpsError(
      "unavailable",
      "Não foi possível cancelar o pagamento no Mercado Pago.",
    );
  }
  const cancelledPayment = await response.json().catch(() => null);
  if (
    !response.ok ||
    String(cancelledPayment?.id) !== String(payment.id) ||
    cancelledPayment.external_reference !== orderId
  ) {
    console.error(
      "Mercado Pago VIP checkout payment cancellation failed",
      response.status,
      cancelledPayment?.message ?? cancelledPayment?.error,
    );
    throw new HttpsError(
      "unavailable",
      "Não foi possível cancelar o pagamento no Mercado Pago.",
    );
  }
  if (cancelledPayment.status === "approved") {
    await activateVipCheckoutPayment(orderId, [cancelledPayment]);
    return "approved";
  }
  if (cancelledPayment.status === "pending") {
    throw new HttpsError(
      "unavailable",
      "O Mercado Pago ainda não confirmou o cancelamento.",
    );
  }
  return cancelledPayment.status;
}

async function cancelVipMercadoPagoCheckoutOrder(orderId, uid, reason) {
  const { orderRef, order } = await getVipCheckoutPaymentOrder(orderId, uid);
  if (order.status !== "pending") {
    return {
      cancelled: false,
      status: order.status,
      cancelReason: order.cancelReason ?? null,
    };
  }
  const { accessToken, payments } = await getVipCheckoutPayments(orderId);
  if (await activateVipCheckoutPayment(orderId, payments)) {
    return { cancelled: false, status: "approved" };
  }

  if (
    reason !== "expired" ||
    vipOrderExpiresAt(order).getTime() > Date.now()
  ) {
    await updateVipCheckoutPreference(order, accessToken, new Date());
  }

  const latestPayments = await getVipCheckoutPayments(orderId);
  if (await activateVipCheckoutPayment(orderId, latestPayments.payments)) {
    return { cancelled: false, status: "approved" };
  }
  for (const payment of latestPayments.payments) {
    const status = await cancelVipCheckoutPayment(
      orderId,
      payment,
      latestPayments.accessToken,
    );
    if (status === "approved") {
      return { cancelled: false, status: "approved" };
    }
    if (status === "in_process") {
      throw new HttpsError(
        "failed-precondition",
        "O pagamento está sendo processado pelo Mercado Pago. Aguarde a confirmação.",
      );
    }
  }

  const cancelReason = reason === "expired" ? "expired" : "user";
  const finalStatus = reason === "expired" ? "expired" : "cancelled";
  await releaseVipCouponReservation(orderRef, finalStatus, {
    cancelReason,
  });
  const updatedOrder = (await orderRef.get()).data();
  return {
    cancelled: updatedOrder?.status === finalStatus,
    status: updatedOrder?.status ?? finalStatus,
    cancelReason: updatedOrder?.cancelReason ?? cancelReason,
  };
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

exports.cancelVipMercadoPagoCheckout = onCall(async (request) => {
  requireSignedIn(request);
  const reason = request.data?.reason ?? "user";
  if (!["user", "expired"].includes(reason)) {
    throw new HttpsError("invalid-argument", "Motivo de cancelamento inválido.");
  }
  return cancelVipMercadoPagoCheckoutOrder(
    request.data?.orderId,
    request.auth.uid,
    reason,
  );
});

exports.checkVipMercadoPagoCheckout = onCall(async (request) => {
  requireSignedIn(request);
  const { orderRef, order } = await getVipCheckoutPaymentOrder(
    request.data?.orderId,
    request.auth.uid,
  );
  if (order.status !== "pending") {
    return {
      status: order.cancelReason === "expired" ? "expired" : order.status,
      cancelReason: order.cancelReason ?? null,
    };
  }
  if (vipOrderExpiresAt(order).getTime() <= Date.now()) {
    const result = await cancelVipMercadoPagoCheckoutOrder(
      request.data.orderId,
      request.auth.uid,
      "expired",
    );
    return result;
  }

  const { payments } = await getVipCheckoutPayments(request.data.orderId);
  if (await activateVipCheckoutPayment(request.data.orderId, payments)) {
    return { status: "approved" };
  }
  if (vipOrderExpiresAt(order).getTime() <= Date.now()) {
    return cancelVipMercadoPagoCheckoutOrder(
      request.data.orderId,
      request.auth.uid,
      "expired",
    );
  }
  const updatedOrder = (await orderRef.get()).data();
  return {
    status: updatedOrder?.status ?? "pending",
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

      let qrCode = pendingOrder.qrCode;
      let qrCodeBase64 = pendingOrder.qrCodeBase64 ?? null;
      if (typeof qrCode !== "string" || !qrCode) {
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
  const approvedOrder = orders.find((order) => order.status === "approved");
  if (approvedOrder) {
    return {
      orderId: approvedOrder.id,
      plan: approvedOrder.plan,
      status: "approved",
    };
  }
  return { status: "none" };
});

exports.getVipMercadoPagoCheckoutOrder = onCall(async (request) => {
  requireSignedIn(request);
  const uid = request.auth.uid;
  const ordersSnapshot = await db.collection("vip_payment_orders")
    .where("uid", "==", uid)
    .get();
  const orders = ordersSnapshot.docs
    .map((document) => ({ ...document.data(), id: document.id }))
    .filter((order) => order.provider === "mercadopago_checkout")
    .sort((left, right) =>
      (right.createdAt?.toMillis?.() ?? 0) - (left.createdAt?.toMillis?.() ?? 0));
  const pendingOrder = orders.find((order) => order.status === "pending");

  if (pendingOrder) {
    if (vipOrderExpiresAt(pendingOrder).getTime() <= Date.now()) {
      const result = await cancelVipMercadoPagoCheckoutOrder(
        pendingOrder.id,
        uid,
        "expired",
      );
      if (result.status === "approved") {
        return {
          orderId: pendingOrder.id,
          plan: pendingOrder.plan,
          status: "approved",
        };
      }
      if (result.status === "pending") {
        throw new HttpsError(
          "unavailable",
          "O checkout expirado ainda está sendo encerrado.",
        );
      }
      const updatedOrder = (await db.doc(
        `vip_payment_orders/${pendingOrder.id}`,
      ).get()).data();
      if (updatedOrder?.expirationNoticeDismissed === true) {
        return { status: "none" };
      }
      return {
        orderId: pendingOrder.id,
        plan: pendingOrder.plan,
        status: "expired",
        expiresAt: vipOrderExpiresAt(pendingOrder).toISOString(),
      };
    }

    const { payments } = await getVipCheckoutPayments(pendingOrder.id);
    if (await activateVipCheckoutPayment(pendingOrder.id, payments)) {
      return {
        orderId: pendingOrder.id,
        plan: pendingOrder.plan,
        status: "approved",
      };
    }
    const updatedOrder = (await db.doc(
      `vip_payment_orders/${pendingOrder.id}`,
    ).get()).data();
    if (updatedOrder?.status === "pending") {
      if (vipOrderExpiresAt(pendingOrder).getTime() <= Date.now()) {
        const result = await cancelVipMercadoPagoCheckoutOrder(
          pendingOrder.id,
          uid,
          "expired",
        );
        if (result.status === "approved") {
          return {
            orderId: pendingOrder.id,
            plan: pendingOrder.plan,
            status: "approved",
          };
        }
        return {
          orderId: pendingOrder.id,
          plan: pendingOrder.plan,
          status: "expired",
          expiresAt: vipOrderExpiresAt(pendingOrder).toISOString(),
        };
      }
      if (typeof pendingOrder.checkoutUrl !== "string") {
        throw new HttpsError(
          "unavailable",
          "O link de checkout não está disponível.",
        );
      }
      return {
        orderId: pendingOrder.id,
        plan: pendingOrder.plan,
        status: "pending",
        checkoutUrl: pendingOrder.checkoutUrl,
        expiresAt: vipOrderExpiresAt(pendingOrder).toISOString(),
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
  const approvedOrder = orders.find((order) => order.status === "approved");
  if (approvedOrder) {
    return {
      orderId: approvedOrder.id,
      plan: approvedOrder.plan,
      status: "approved",
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

exports.acknowledgeVipMercadoPagoCheckoutExpiration = onCall(async (request) => {
  requireSignedIn(request);
  const { orderRef } = await getVipCheckoutPaymentOrder(
    request.data?.orderId,
    request.auth.uid,
  );
  await db.runTransaction(async (transaction) => {
    const orderSnapshot = await transaction.get(orderRef);
    if (!orderSnapshot.exists) {
      throw new HttpsError("not-found", "Pedido de checkout não encontrado.");
    }
    const order = orderSnapshot.data();
    if (order.status !== "expired" || order.cancelReason !== "expired") {
      throw new HttpsError(
        "failed-precondition",
        "O checkout ainda não expirou.",
      );
    }
    transaction.update(orderRef, {
      expirationNoticeDismissed: true,
      expirationNoticeDismissedAt: FieldValue.serverTimestamp(),
    });
  });
  return { acknowledged: true };
});

function timestampMillis(value) {
  const date = value?.toDate?.();
  return date instanceof Date && Number.isFinite(date.getTime())
    ? date.getTime()
    : null;
}

exports.listVipPaymentHistory = onCall(async (request) => {
  requireAdmin(request);
  const [ordersSnapshot, requestsSnapshot] = await Promise.all([
    db.collection("vip_payment_orders")
      .orderBy("createdAt", "desc")
      .limit(200)
      .get(),
    db.collection("vip_payment_requests")
      .orderBy("createdAt", "desc")
      .limit(200)
      .get(),
  ]);
  const orderRecords = ordersSnapshot.docs.map((document) => ({
    id: document.id,
    uid: document.data().uid,
    provider: document.data().provider,
  }));
  const userIds = [...new Set(
    [...orderRecords, ...requestsSnapshot.docs.map((document) => ({
      uid: document.data().uid,
    }))]
      .map((record) => record.uid)
      .filter((uid) => typeof uid === "string" && uid.length > 0),
  )];
  const userSnapshots = userIds.length > 0
    ? await db.getAll(...userIds.map((uid) => db.doc(`users/${uid}`)))
    : [];
  const usersById = new Map(
    userSnapshots.map((snapshot) => [
      snapshot.id,
      {
        name: snapshot.data()?.name ?? "",
        email: snapshot.data()?.email ?? "",
      },
    ]),
  );
  const orders = ordersSnapshot.docs.map((document) => {
    const data = document.data();
    const user = usersById.get(data.uid) ?? {};
    return {
      id: document.id,
      kind: "automatic",
      uid: data.uid ?? "",
      userName: user.name,
      email: user.email,
      plan: data.plan ?? "",
      provider: data.provider ?? "",
      status: data.status ?? "",
      amountCents: data.amountCents ?? null,
      createdAtMillis: timestampMillis(data.createdAt),
      approvedAtMillis: timestampMillis(
        data.providerApprovedAt ?? data.approvedAt,
      ),
      refundStatus: data.refundStatus ?? null,
      refundAtMillis: timestampMillis(data.refundedAt),
      refundAmountCents: data.refundAmountCents ?? null,
      refundEntitlementAdjustmentRequired:
        data.refundEntitlementAdjustmentRequired === true,
    };
  });
  const manualRequests = requestsSnapshot.docs.map((document) => {
    const data = document.data();
    const user = usersById.get(data.uid) ?? {};
    return {
      id: document.id,
      kind: "manual",
      uid: data.uid ?? "",
      userName: data.userName ?? user.name ?? "",
      email: data.email ?? user.email ?? "",
      plan: data.plan ?? "",
      provider: data.provider ?? "pix_manual",
      status: data.status ?? "",
      amountCents: data.amountCents ?? null,
      createdAtMillis: timestampMillis(data.createdAt),
      approvedAtMillis: timestampMillis(data.reviewedAt),
      refundStatus: null,
      refundAtMillis: null,
      refundAmountCents: null,
    };
  });
  return {
    payments: [...orders, ...manualRequests]
      .sort((left, right) =>
        (right.createdAtMillis ?? 0) - (left.createdAtMillis ?? 0)),
    truncated: ordersSnapshot.size === 200 || requestsSnapshot.size === 200,
  };
});

async function getVipPaymentRefundList(paymentId, accessToken) {
  let response;
  try {
    response = await fetch(
      `${PAYMENT_API}/${encodeURIComponent(paymentId)}/refunds`,
      { headers: { Authorization: `Bearer ${accessToken}` } },
    );
  } catch (error) {
    console.error("Mercado Pago VIP refund lookup failed", error);
    throw new HttpsError(
      "unavailable",
      "Não foi possível consultar a devolução no Mercado Pago.",
    );
  }
  const body = await response.json().catch(() => null);
  const refunds = Array.isArray(body) ? body : body?.refunds;
  if (!response.ok || !Array.isArray(refunds)) {
    console.error("Mercado Pago VIP refund lookup failed", response.status);
    throw new HttpsError(
      "unavailable",
      "Não foi possível consultar a devolução no Mercado Pago.",
    );
  }
  return refunds;
}

async function applyVipRefundEntitlement(orderRef, order) {
  await db.runTransaction(async (transaction) => {
    const orderSnapshot = await transaction.get(orderRef);
    if (
      !orderSnapshot.exists ||
      orderSnapshot.data().refundStatus !== "refunded" ||
      orderSnapshot.data().refundEntitlementAdjusted === true
    ) return;
    const currentOrder = orderSnapshot.data();
    const userRef = db.doc(`users/${currentOrder.uid}`);
    const badgeRef = db.doc(`vip_public_badges/${currentOrder.uid}`);
    const [userSnapshot, badgeSnapshot] = await Promise.all([
      transaction.get(userRef),
      transaction.get(badgeRef),
    ]);
    if (!userSnapshot.exists) {
      transaction.update(orderRef, {
        refundEntitlementAdjusted: true,
        refundEntitlementAdjustmentRequired: true,
      });
      return;
    }

    const user = userSnapshot.data();
    const currentExpiration = user.vipExpiresAt?.toDate?.() ?? null;
    const orderExpiration = currentOrder.expiresAt?.toDate?.() ?? null;
    const currentPlan = user.vipPlan ?? "free";
    if (currentExpiration && orderExpiration) {
      const isRefundedOrderCurrent =
        currentPlan === currentOrder.plan &&
        currentExpiration.getTime() === orderExpiration.getTime();
      let restoredPlan = currentPlan;
      let restoredExpiration;
      let adjustmentRequired = false;
      if (isRefundedOrderCurrent &&
          typeof currentOrder.previousVipPlan === "string") {
        restoredPlan = currentOrder.previousVipPlan;
        restoredExpiration = currentOrder.previousVipExpiresAt?.toDate?.() ?? null;
        if (restoredPlan !== "free" && !restoredExpiration) {
          transaction.update(orderRef, {
            refundEntitlementAdjusted: true,
            refundEntitlementAdjustmentRequired: true,
          });
          return;
        }
      } else if (isRefundedOrderCurrent) {
        if (
          !Number.isSafeInteger(currentOrder.durationDays) ||
          currentOrder.durationDays <= 0
        ) {
          transaction.update(orderRef, {
            refundEntitlementAdjusted: true,
            refundEntitlementAdjustmentRequired: true,
          });
          return;
        }
        restoredExpiration = new Date(currentExpiration);
        restoredExpiration.setDate(
          restoredExpiration.getDate() - currentOrder.durationDays,
        );
        if (restoredExpiration <= new Date()) restoredPlan = "free";
        adjustmentRequired = true;
      } else {
        transaction.update(orderRef, {
          refundEntitlementAdjusted: true,
          refundEntitlementAdjustmentRequired: true,
        });
        return;
      }

      transaction.update(userRef, {
        vipPlan: restoredPlan,
        ...(restoredExpiration
          ? { vipExpiresAt: Timestamp.fromDate(restoredExpiration) }
          : { vipExpiresAt: FieldValue.delete() }),
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (adjustmentRequired) {
        transaction.update(orderRef, {
          refundEntitlementAdjustmentRequired: true,
        });
      }
      if (restoredExpiration && restoredExpiration > new Date()) {
        transaction.set(badgeRef, {
          uid: currentOrder.uid,
          plan: restoredPlan,
          expiresAt: Timestamp.fromDate(restoredExpiration),
          updatedAt: FieldValue.serverTimestamp(),
        });
      } else if (badgeSnapshot.exists) {
        transaction.delete(badgeRef);
      }
    } else {
      transaction.update(orderRef, {
        refundEntitlementAdjusted: true,
        refundEntitlementAdjustmentRequired: true,
      });
      return;
    }
    transaction.update(orderRef, { refundEntitlementAdjusted: true });
  });
}

async function completeVipRefund(orderRef, refundSummary) {
  if (refundSummary.status !== "refunded") {
    await orderRef.update({
      refundStatus: refundSummary.status,
      refundIds: [
        ...refundSummary.approvedRefundIds,
        ...refundSummary.pendingRefundIds,
      ],
      refundAmountCents: refundSummary.approvedAmountCents,
      refundUpdatedAt: FieldValue.serverTimestamp(),
    });
    return { status: refundSummary.status };
  }
  await orderRef.update({
    status: "refunded",
    refundStatus: "refunded",
    refundId: refundSummary.approvedRefundIds[0] ?? null,
    refundIds: refundSummary.approvedRefundIds,
    refundAmountCents: refundSummary.approvedAmountCents,
    refundedAt: FieldValue.serverTimestamp(),
    refundUpdatedAt: FieldValue.serverTimestamp(),
  });
  const snapshot = await orderRef.get();
  await applyVipRefundEntitlement(orderRef, snapshot.data());
  return {
    status: "refunded",
    refundId: refundSummary.approvedRefundIds[0] ?? null,
    refundAmountCents: refundSummary.approvedAmountCents,
  };
}

exports.refundVipMercadoPagoPayment = onCall(async (request) => {
  requireAdmin(request);
  validateVipOrderId(request.data?.orderId);
  const orderRef = db.doc(`vip_payment_orders/${request.data.orderId}`);
  const orderSnapshot = await orderRef.get();
  if (!orderSnapshot.exists) {
    throw new HttpsError("not-found", "Pagamento VIP não encontrado.");
  }
  const order = orderSnapshot.data();
  if (
    !["mercadopago", "mercadopago_checkout"].includes(order.provider) ||
    !order.providerPaymentId
  ) {
    throw new HttpsError(
      "failed-precondition",
      "Somente pagamentos aprovados do Mercado Pago podem ser devolvidos.",
    );
  }
  if (order.refundStatus === "refunded") {
    return {
      status: "refunded",
      refundId: order.refundId ?? null,
      refundAmountCents: order.refundAmountCents ?? order.amountCents,
    };
  }
  if (order.status !== "approved") {
    throw new HttpsError(
      "failed-precondition",
      "Somente pagamentos aprovados do Mercado Pago podem ser devolvidos.",
    );
  }
  if (order.refundStatus === "partial") {
    throw new HttpsError(
      "failed-precondition",
      "Já existe uma devolução parcial. Verifique o pagamento no Mercado Pago antes de solicitar outra devolução.",
    );
  }
  const isRetry = order.refundStatus === "pending" ||
    order.refundStatus === "processing";
  let refundIdempotencyKey = order.refundIdempotencyKey;
  if (!isRetry) {
    const approvalMillis = timestampMillis(
      order.providerApprovedAt ?? order.approvedAt,
    );
    if (!isVipRefundWithinWindow(approvalMillis)) {
      throw new HttpsError(
        "failed-precondition",
        "O prazo de 7 dias para solicitar a devolução foi encerrado.",
      );
    }
  }

  const privateSnapshot = await PRIVATE_CONFIG.get();
  const token = privateSnapshot.data()?.accessToken;
  if (!token) {
    throw new HttpsError(
      "failed-precondition",
      "A configuração do pagamento não está disponível.",
    );
  }
  const paymentUrl = `${PAYMENT_API}/${encodeURIComponent(order.providerPaymentId)}`;
  if (!isRetry) {
    let paymentResponse;
    try {
      paymentResponse = await fetch(paymentUrl, {
        headers: { Authorization: `Bearer ${token}` },
      });
    } catch (error) {
      console.error("Mercado Pago VIP refund payment lookup failed", error);
      throw new HttpsError(
        "unavailable",
        "Não foi possível verificar o pagamento no Mercado Pago.",
      );
    }
    const payment = await paymentResponse.json().catch(() => null);
    if (
      !paymentResponse.ok ||
      !payment ||
      !validateVipRefundPayment(request.data.orderId, order, payment)
    ) {
      console.error(
        "Mercado Pago VIP refund payment validation failed",
        paymentResponse.status,
      );
      throw new HttpsError(
        "failed-precondition",
        "O pagamento não corresponde a este pedido VIP ou não está aprovado.",
      );
    }

    refundIdempotencyKey = await db.runTransaction(async (transaction) => {
      const currentSnapshot = await transaction.get(orderRef);
      const currentOrder = currentSnapshot.data();
      if (
        !currentSnapshot.exists ||
        currentOrder.status !== "approved" ||
        ["refunded", "partial", "processing", "pending"].includes(
          currentOrder.refundStatus,
        )
      ) {
        throw new HttpsError(
          "already-exists",
          "A devolução já foi solicitada ou o pagamento foi alterado.",
        );
      }
      const attempt = (currentOrder.refundAttemptCount ?? 0) + 1;
      const idempotencyKey = `vip-refund-${request.data.orderId}-${attempt}`;
      transaction.update(orderRef, {
        refundStatus: "processing",
        refundAttemptCount: attempt,
        refundIdempotencyKey: idempotencyKey,
        refundRequestedAt: FieldValue.serverTimestamp(),
        refundRequestedBy: request.auth.uid,
      });
      return idempotencyKey;
    });
  } else if (!refundIdempotencyKey) {
    refundIdempotencyKey = `vip-refund-${request.data.orderId}`;
  }

  const refunds = await getVipPaymentRefundList(order.providerPaymentId, token);
  const refundSummary = summarizeVipRefunds(
    refunds,
    order.providerPaymentId,
    order.amountCents,
  );
  if (isRetry && refundSummary.rejectedRefundIds.length > 0) {
    await orderRef.update({
      refundStatus: "failed",
      refundError: "refund_rejected",
      refundIdempotencyKey: FieldValue.delete(),
      refundUpdatedAt: FieldValue.serverTimestamp(),
    });
    throw new HttpsError(
      "failed-precondition",
      "O Mercado Pago recusou a devolução. Você pode tentar novamente.",
    );
  }
  if (refundSummary.status !== "none") {
    return completeVipRefund(orderRef, refundSummary);
  }

  let response;
  try {
    response = await fetch(`${paymentUrl}/refunds`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
        "X-Idempotency-Key": refundIdempotencyKey,
      },
      body: JSON.stringify({}),
    });
  } catch (error) {
    console.error("Mercado Pago VIP refund request failed", error);
    throw new HttpsError(
      "unavailable",
      "Não foi possível solicitar a devolução no Mercado Pago.",
    );
  }
  const refund = await response.json().catch(() => null);
  if (
    !response.ok ||
    !refund ||
    String(refund.payment_id) !== String(order.providerPaymentId) ||
    (typeof refund.id !== "number" && typeof refund.id !== "string") ||
    !Number.isFinite(Number(refund.amount)) ||
    Number(refund.amount) <= 0 ||
    Math.round(Number(refund.amount) * 100) > order.amountCents
  ) {
    console.error(
      "Mercado Pago VIP refund request failed",
      response.status,
      refund?.message ?? refund?.error,
    );
    throw new HttpsError(
      "unavailable",
      "Não foi possível confirmar a resposta do Mercado Pago. Verifique a devolução antes de tentar novamente.",
    );
  }
  if (refund.status === "rejected") {
    await orderRef.update({
      refundStatus: "failed",
      refundError: "refund_rejected",
      refundId: String(refund.id),
      refundIdempotencyKey: FieldValue.delete(),
      refundUpdatedAt: FieldValue.serverTimestamp(),
    });
    throw new HttpsError(
      "failed-precondition",
      "O Mercado Pago recusou a devolução. Você pode tentar novamente.",
    );
  }
  const responseSummary = summarizeVipRefunds(
    [refund],
    order.providerPaymentId,
    order.amountCents,
  );
  if (
    responseSummary.status === "none" ||
    (!["approved", "pending", "in_process"].includes(refund.status))
  ) {
    throw new HttpsError(
      "unavailable",
      "A resposta do Mercado Pago ainda não permite confirmar a devolução. Verifique novamente em instantes.",
    );
  }
  return completeVipRefund(orderRef, responseSummary);
});

async function activatePaidOrder(paymentId) {
  const privateSnapshot = await PRIVATE_CONFIG.get();
  const token = privateSnapshot.data()?.accessToken;
  if (!token) throw new Error("VIP payment credential missing.");

  const response = await fetch(`${PAYMENT_API}/${encodeURIComponent(paymentId)}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!response.ok) throw new Error(`Mercado Pago lookup returned ${response.status}.`);
  const payment = await response.json();

  const orderId = payment.external_reference;
  if (
    typeof orderId !== "string" ||
    !orderId ||
    payment.currency_id !== "BRL"
  ) return;
  const orderRef = db.doc(`vip_payment_orders/${orderId}`);
  await db.runTransaction(async (transaction) => {
    const orderSnapshot = await transaction.get(orderRef);
    if (!orderSnapshot.exists) return;
    const order = orderSnapshot.data();
    const isLegacyMercadoPagoOrder = order.provider === "mercadopago";
    const isCheckoutOrder = order.provider === "mercadopago_checkout";
    const checkoutWasClosed = isCheckoutOrder &&
      ["cancelled", "expired"].includes(order.status);
    if (
      (!isLegacyMercadoPagoOrder && !isCheckoutOrder) ||
      (order.status !== "pending" && !checkoutWasClosed) ||
      (isLegacyMercadoPagoOrder &&
        order.providerPaymentId !== String(payment.id)) ||
      (payment.metadata?.type != null &&
        payment.metadata.type !== "vip_subscription") ||
      (payment.metadata?.uid != null &&
        payment.metadata.uid !== order.uid) ||
      (payment.metadata?.plan != null &&
        payment.metadata.plan !== order.plan) ||
      Math.round(Number(payment.transaction_amount) * 100) !== order.amountCents ||
      (isCheckoutOrder &&
        !isApprovedVipCheckoutPayment(orderId, order, payment))
    ) return;

    if (payment.status !== "approved") {
      if (isCheckoutOrder) return;
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
    const couponRef = order.couponCode ? COUPONS.doc(order.couponCode) : null;
    const couponSnapshot = couponRef && order.couponReservationReleased
      ? await transaction.get(couponRef)
      : null;
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
    if (couponSnapshot?.exists) {
      transaction.update(couponRef, {
        usedCount: (couponSnapshot.data().usedCount ?? 0) + 1,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.update(orderRef, {
      status: "approved",
      approvedAt: FieldValue.serverTimestamp(),
      providerApprovedAt: payment.date_approved
        ? Timestamp.fromDate(new Date(payment.date_approved))
        : FieldValue.serverTimestamp(),
      expiresAt,
      providerPaymentId: String(payment.id),
      previousVipPlan: user.vipPlan ?? "free",
      previousVipExpiresAt: user.vipExpiresAt ?? null,
      couponReservationReleased: false,
      cancelReason: FieldValue.delete(),
      expirationNoticeDismissed: FieldValue.delete(),
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
