function normalizeCouponCode(value) {
  if (typeof value !== "string") {
    throw new TypeError("Informe um código de cupom válido.");
  }
  const code = value.trim().toUpperCase();
  if (!/^[A-Z0-9][A-Z0-9_-]{2,31}$/.test(code)) {
    throw new TypeError("O código deve ter de 3 a 32 caracteres: letras, números, hífen ou sublinhado.");
  }
  return code;
}

const VIP_PLAN_IDS = ["bronze", "silver", "gold", "platinum"];
const DISCOUNT_TYPES = ["percent", "fixed", "final_price"];

function validateCouponSettings(
  discountType,
  discountValue,
  maxUses,
  planIds = VIP_PLAN_IDS,
  expiresAtMillis = null,
) {
  if (!DISCOUNT_TYPES.includes(discountType)) {
    throw new TypeError("Escolha percentual, valor fixo ou preço final para o desconto.");
  }
  if (!Number.isSafeInteger(discountValue) || discountValue < 1) {
    throw new TypeError("Informe um valor de desconto válido.");
  }
  if (discountType === "percent" && discountValue > 99) {
    throw new TypeError("O desconto percentual deve estar entre 1% e 99%.");
  }
  if (discountType !== "percent" && discountValue > 10000000) {
    throw new TypeError("O valor não pode exceder R$ 100.000,00.");
  }
  if (maxUses !== null && (!Number.isSafeInteger(maxUses) || maxUses < 1 || maxUses > 1000000)) {
    throw new TypeError("O limite de usos deve ser um inteiro entre 1 e 1.000.000.");
  }
  if (
    !Array.isArray(planIds) ||
    planIds.length === 0 ||
    planIds.some((plan) => !VIP_PLAN_IDS.includes(plan)) ||
    new Set(planIds).size !== planIds.length
  ) {
    throw new TypeError("Selecione ao menos um plano VIP válido.");
  }
  if (
    expiresAtMillis !== null &&
    (!Number.isSafeInteger(expiresAtMillis) ||
      expiresAtMillis < 0 ||
      expiresAtMillis > 253402300799999)
  ) {
    throw new TypeError("A data de encerramento do cupom é inválida.");
  }
}

function calculateCouponDiscount(coupon, amountCents, plan, now = Date.now()) {
  if (!coupon || coupon.active !== true) {
    throw new RangeError("Este cupom não está ativo.");
  }
  const maxUses = coupon.maxUses;
  const usedCount = coupon.usedCount ?? 0;
  if (!Number.isSafeInteger(usedCount) || usedCount < 0) {
    throw new RangeError("A contagem de usos deste cupom está inválida.");
  }
  if (maxUses !== null && maxUses !== undefined && usedCount >= maxUses) {
    throw new RangeError("Este cupom atingiu o limite máximo de usos.");
  }
  const planIds = coupon.planIds ?? VIP_PLAN_IDS;
  const expiresAtMillis =
    coupon.expiresAt?.toMillis?.() ?? coupon.expiresAtMillis ?? null;
  validateCouponSettings(
    coupon.discountType,
    coupon.discountValue,
    maxUses ?? null,
    planIds,
    expiresAtMillis,
  );
  if (expiresAtMillis !== null && now >= expiresAtMillis) {
    throw new RangeError("Este cupom já passou da data e hora de encerramento.");
  }
  if (plan && !planIds.includes(plan)) {
    throw new RangeError("Este cupom não é válido para o plano selecionado.");
  }
  if (!Number.isSafeInteger(amountCents) || amountCents < 1) {
    throw new RangeError("O preço deste plano ainda não foi configurado.");
  }

  const discountCents = coupon.discountType === "percent"
    ? Math.floor(amountCents * coupon.discountValue / 100)
    : coupon.discountType === "fixed"
      ? coupon.discountValue
      : amountCents - coupon.discountValue;
  if (discountCents < 1 || discountCents >= amountCents) {
    throw new RangeError(coupon.discountType === "final_price"
      ? "O preço final do cupom deve ser menor que o preço atual do plano."
      : "Este desconto não pode ser aplicado ao preço do plano.");
  }
  return discountCents;
}

module.exports = {
  calculateCouponDiscount,
  normalizeCouponCode,
  VIP_PLAN_IDS,
  validateCouponSettings,
};
