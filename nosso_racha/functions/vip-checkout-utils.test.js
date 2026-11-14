const test = require("node:test");
const assert = require("node:assert/strict");
const {
  checkoutBackUrls,
  checkoutUrlForPreference,
  isApprovedVipCheckoutPayment,
  isVipRefundWithinWindow,
  summarizeVipRefunds,
  validateVipRefundPayment,
} = require("./vip-checkout-utils");

test("builds Checkout Pro return URLs only from absolute HTTPS URLs", () => {
  assert.deepEqual(
    checkoutBackUrls("https://nosso-racha.vercel.app/#/vip-checkout-return"),
    {
      success: "https://nosso-racha.vercel.app/#/vip-checkout-return",
      failure: "https://nosso-racha.vercel.app/#/vip-checkout-return",
      pending: "https://nosso-racha.vercel.app/#/vip-checkout-return",
    },
  );
  assert.throws(
    () => checkoutBackUrls("nosso-racha:///vip-checkout-return"),
    /absolute HTTPS URL/,
  );
  assert.throws(
    () => checkoutBackUrls("http://nosso-racha.vercel.app/"),
    /absolute HTTPS URL/,
  );
});

test("selects production and sandbox Checkout Pro URLs from the credential", () => {
  assert.equal(
    checkoutUrlForPreference("APP_USR-token", {
      init_point: "https://www.mercadopago.com.br/checkout/123",
      sandbox_init_point: "https://sandbox.mercadopago.com.br/checkout/123",
    }),
    "https://www.mercadopago.com.br/checkout/123",
  );
  assert.equal(
    checkoutUrlForPreference("TEST-token", {
      init_point: "https://www.mercadopago.com.br/checkout/123",
      sandbox_init_point: "https://sandbox.mercadopago.com.br/checkout/123",
    }),
    "https://sandbox.mercadopago.com.br/checkout/123",
  );
});

test("rejects Checkout Pro links outside Mercado Pago's HTTPS domains", () => {
  assert.equal(
    checkoutUrlForPreference("APP_USR-token", {
      init_point: "https://checkout.attacker.example/pay",
    }),
    null,
  );
  assert.equal(
    checkoutUrlForPreference("APP_USR-token", {
      init_point: "http://www.mercadopago.com.br/checkout/123",
    }),
    null,
  );
});

test("accepts only approved payments matching a VIP checkout order", () => {
  const order = {
    provider: "mercadopago_checkout",
    status: "pending",
    uid: "user-1",
    plan: "gold",
    amountCents: 1590,
  };
  const payment = {
    id: 123,
    status: "approved",
    external_reference: "order-1",
    currency_id: "BRL",
    transaction_amount: 15.9,
    metadata: {
      type: "vip_subscription",
      uid: "user-1",
      plan: "gold",
    },
  };

  assert.equal(isApprovedVipCheckoutPayment("order-1", order, payment), true);
  assert.equal(
    isApprovedVipCheckoutPayment("order-2", order, payment),
    false,
  );
  assert.equal(
    isApprovedVipCheckoutPayment("order-1", order, {
      ...payment,
      transaction_amount: 14.9,
    }),
    false,
  );
  assert.equal(
    isApprovedVipCheckoutPayment("order-1", order, {
      ...payment,
      status: "pending",
    }),
    false,
  );
});

test("allows a late-approved payment to fulfill a closed checkout", () => {
  const order = {
    provider: "mercadopago_checkout",
    status: "expired",
    uid: "user-1",
    plan: "silver",
    amountCents: 800,
  };
  const payment = {
    status: "approved",
    external_reference: "order-1",
    currency_id: "BRL",
    transaction_amount: 8,
  };

  assert.equal(isApprovedVipCheckoutPayment("order-1", order, payment), true);
});

test("does not allow rejected or mismatched payments to activate a plan", () => {
  const order = {
    provider: "mercadopago_checkout",
    status: "pending",
    uid: "user-1",
    plan: "gold",
    amountCents: 1590,
  };
  const payment = {
    status: "approved",
    external_reference: "order-1",
    currency_id: "BRL",
    transaction_amount: 15.9,
    metadata: {
      type: "vip_subscription",
      uid: "user-1",
      plan: "silver",
    },
  };

  assert.equal(isApprovedVipCheckoutPayment("order-1", order, payment), false);
  assert.equal(
    isApprovedVipCheckoutPayment("order-1", order, {
      ...payment,
      metadata: { ...payment.metadata, plan: "gold" },
      currency_id: "USD",
    }),
    false,
  );
});

test("enforces the seven-day VIP refund window from approval time", () => {
  const now = 2_000_000_000_000;
  const sevenDays = 7 * 24 * 60 * 60 * 1000;
  assert.equal(isVipRefundWithinWindow(now - sevenDays, now), true);
  assert.equal(isVipRefundWithinWindow(now - sevenDays - 1, now), false);
  assert.equal(isVipRefundWithinWindow(now + 1, now), false);
  assert.equal(isVipRefundWithinWindow(Number.NaN, now), false);
});

test("refund validation requires an approved exact matching Mercado Pago payment", () => {
  const order = {
    provider: "mercadopago_checkout",
    providerPaymentId: "payment-1",
    uid: "user-1",
    plan: "gold",
    amountCents: 1590,
  };
  const payment = {
    id: "payment-1",
    status: "approved",
    external_reference: "order-1",
    currency_id: "BRL",
    transaction_amount: 15.9,
    metadata: {
      type: "vip_subscription",
      uid: "user-1",
      plan: "gold",
    },
  };

  assert.equal(validateVipRefundPayment("order-1", order, payment), true);
  assert.equal(
    validateVipRefundPayment("order-2", order, payment),
    false,
  );
  assert.equal(
    validateVipRefundPayment("order-1", order, {
      ...payment,
      transaction_amount: 25.9,
    }),
    false,
  );
  assert.equal(
    validateVipRefundPayment("order-1", order, {
      ...payment,
      status: "pending",
    }),
    false,
  );
});

test("summarizes matching refunds without treating a partial refund as complete", () => {
  const paymentId = "payment-1";
  const partial = summarizeVipRefunds(
    [
      { id: 1, payment_id: paymentId, amount: 5, status: "approved" },
      { id: 2, payment_id: "other-payment", amount: 10, status: "approved" },
    ],
    paymentId,
    1590,
  );
  assert.equal(partial.status, "partial");
  assert.equal(partial.approvedAmountCents, 500);

  const fullyRefunded = summarizeVipRefunds(
    [
      { id: 1, payment_id: paymentId, amount: 5, status: "approved" },
      { id: 2, payment_id: paymentId, amount: 10.9, status: "approved" },
    ],
    paymentId,
    1590,
  );
  assert.equal(fullyRefunded.status, "refunded");
  assert.deepEqual(fullyRefunded.approvedRefundIds, ["1", "2"]);

  const pending = summarizeVipRefunds(
    [{ id: 3, payment_id: paymentId, amount: 15.9, status: "pending" }],
    paymentId,
    1590,
  );
  assert.equal(pending.status, "pending");
});
