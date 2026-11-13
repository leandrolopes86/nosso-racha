const test = require("node:test");
const assert = require("node:assert/strict");
const {
  calculateCouponDiscount,
  normalizeCouponCode,
  validateCouponSettings,
} = require("./vip-coupon-utils");

test("normalizes coupon codes and rejects unsupported characters", () => {
  assert.equal(normalizeCouponCode("  verao_25 "), "VERAO_25");
  assert.throws(() => normalizeCouponCode("AB"));
  assert.throws(() => normalizeCouponCode("CUPOM!"));
});

test("validates discount values and optional use limits", () => {
  assert.doesNotThrow(() => validateCouponSettings("percent", 25, null));
  assert.doesNotThrow(() => validateCouponSettings("fixed", 1250, 10));
  assert.doesNotThrow(() => validateCouponSettings("final_price", 100, null));
  assert.throws(() => validateCouponSettings("percent", 100, null));
  assert.throws(() => validateCouponSettings("fixed", 100, 0));
  assert.throws(() => validateCouponSettings("final_price", 100, null, []));
});

test("calculates fixed and percentage discounts in cents", () => {
  assert.equal(
    calculateCouponDiscount(
      { active: true, discountType: "percent", discountValue: 25, maxUses: null },
      10001,
    ),
    2500,
  );
  assert.equal(
    calculateCouponDiscount(
      { active: true, discountType: "fixed", discountValue: 1250, maxUses: 2 },
      5000,
    ),
    1250,
  );
});

test("applies a configured final price only to selected plans", () => {
  const coupon = {
    active: true,
    discountType: "final_price",
    discountValue: 100,
    maxUses: null,
    planIds: ["bronze", "gold"],
  };
  assert.equal(calculateCouponDiscount(coupon, 500, "bronze"), 400);
  assert.throws(() => calculateCouponDiscount(coupon, 500, "silver"), /não é válido/);
  assert.throws(() => calculateCouponDiscount(coupon, 100, "gold"), /menor que o preço atual/);
  assert.equal(
    calculateCouponDiscount(
      { active: true, discountType: "percent", discountValue: 10, maxUses: null },
      1000,
      "platinum",
    ),
    100,
  );
});

test("expires coupons at the earlier configured usage or time limit", () => {
  const expiresAtMillis = 2000;
  const coupon = {
    active: true,
    discountType: "percent",
    discountValue: 10,
    maxUses: 2,
    usedCount: 1,
    planIds: ["silver"],
    expiresAtMillis,
  };
  assert.equal(calculateCouponDiscount(coupon, 1000, "silver", 1999), 100);
  assert.throws(
    () => calculateCouponDiscount(coupon, 1000, "silver", expiresAtMillis),
    /data e hora/,
  );
  assert.throws(
    () => calculateCouponDiscount(
      { ...coupon, usedCount: 2 },
      1000,
      "silver",
      1000,
    ),
    /limite máximo/,
  );
});

test("rejects inactive, exhausted, or over-discounting coupons", () => {
  assert.throws(() => calculateCouponDiscount(
    { active: false, discountType: "percent", discountValue: 10, maxUses: null },
    1000,
  ));
  assert.throws(() => calculateCouponDiscount(
    { active: true, discountType: "percent", discountValue: 10, maxUses: 1, usedCount: 1 },
    1000,
  ));
  assert.throws(() => calculateCouponDiscount(
    { active: true, discountType: "fixed", discountValue: 1000, maxUses: null },
    1000,
  ));
  assert.throws(() => calculateCouponDiscount(
    { active: true, discountType: "percent", discountValue: 10, maxUses: null, usedCount: "1" },
    1000,
  ));
});
