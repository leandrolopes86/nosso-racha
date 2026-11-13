import { readFile } from 'node:fs/promises';
import { after, before, test } from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
} from 'firebase/firestore';

const projectId = 'demo-nosso-racha-admin';
const rulesPath = fileURLToPath(
  new URL('../../../nosso_racha_admin/firestore.rules', import.meta.url),
);

let testEnvironment;
let future;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: await readFile(rulesPath, 'utf8'),
    },
  });

  future = Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000));
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'groups/team'), { owner_id: 'group-owner' });
    await setDoc(doc(db, 'groups/team/members/member'), {
      uid: 'member',
      role: 'member',
    });
    await setDoc(doc(db, 'groups/team/settings/payment_gateway'), {
      access_token: 'server-side-test-secret',
    });
    await setDoc(doc(db, 'groups/team/notes/private'), {
      content: 'group-only',
    });
    await setDoc(doc(db, 'transactions/team-transaction'), {
      group_id: 'team',
      amount: 10,
    });
    await setDoc(doc(db, 'users/group-owner'), {
      role: 'athlete',
      status: 'active',
      personal_info: { full_name: 'Group Owner', phone_raw: '123' },
      vipPlan: 'Free',
      vipExpiresAt: null,
    });
    await setDoc(doc(db, 'users/attacker'), {
      role: 'athlete',
      status: 'active',
      personal_info: { full_name: 'Attacker' },
      vipPlan: 'Free',
      vipExpiresAt: null,
    });
  });
});

after(async () => {
  await testEnvironment?.cleanup();
});

test('admin rules isolate group settings, subcollections, and transactions', async () => {
  const ownerDb = testEnvironment
    .authenticatedContext('group-owner')
    .firestore();
  const memberDb = testEnvironment.authenticatedContext('member').firestore();
  const outsiderDb = testEnvironment
    .authenticatedContext('attacker')
    .firestore();

  await assertFails(
    getDoc(doc(ownerDb, 'groups/team/settings/payment_gateway')),
  );
  await assertFails(
    setDoc(doc(ownerDb, 'groups/team/settings/payment_gateway'), {
      access_token: 'client-secret',
    }),
  );
  await assertFails(
    getDoc(doc(memberDb, 'groups/team/settings/payment_gateway')),
  );
  await assertFails(
    getDoc(doc(outsiderDb, 'groups/team/settings/payment_gateway')),
  );
  await assertFails(getDoc(doc(ownerDb, 'settings/payment_gateway')));
  await assertFails(
    getDoc(doc(outsiderDb, 'groups/team/notes/private')),
  );
  await assertSucceeds(
    getDoc(doc(memberDb, 'groups/team/notes/private')),
  );
  await assertFails(
    getDoc(doc(outsiderDb, 'transactions/team-transaction')),
  );
  await assertSucceeds(
    getDoc(doc(ownerDb, 'transactions/team-transaction')),
  );
  await assertFails(
    updateDoc(doc(ownerDb, 'transactions/team-transaction'), {
      group_id: 'another-group',
    }),
  );
});

test('VIP payment requests are owner scoped and payment orders are server written', async () => {
  const payerDb = testEnvironment.authenticatedContext('vip-payer').firestore();
  const otherDb = testEnvironment.authenticatedContext('vip-other').firestore();
  const adminDb = testEnvironment
    .authenticatedContext('vip-admin', { admin: true })
    .firestore();
  const requestRef = doc(payerDb, 'vip_payment_requests/vip-request');
  const expiresAt = Timestamp.fromDate(new Date(Date.now() + 30 * 86400000));

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'settings/payment_config'), {
      provider: 'pix_manual',
      prices: { bronze: { amountCents: 1500, durationDays: 30 } },
    });
    await setDoc(doc(db, 'users/vip-payer'), {
      role: 'athlete',
      status: 'active',
      vipPlan: 'Free',
      vipExpiresAt: null,
    });
    await setDoc(doc(db, 'vip_payment_orders/vip-order'), {
      uid: 'vip-payer',
      status: 'pending',
    });
    await setDoc(doc(db, 'vip_coupons/VERAO25'), {
      code: 'VERAO25',
      discountType: 'percent',
      discountValue: 25,
      maxUses: 5,
      usedCount: 0,
      active: true,
    });
  });

  await assertSucceeds(getDoc(doc(adminDb, 'vip_coupons/VERAO25')));
  await assertSucceeds(getDocs(collection(adminDb, 'vip_coupons')));
  await assertFails(getDoc(doc(payerDb, 'vip_coupons/VERAO25')));
  await assertFails(getDocs(collection(payerDb, 'vip_coupons')));
  await assertFails(
    setDoc(doc(adminDb, 'vip_coupons/CLIENT-WRITE'), {
      code: 'CLIENT-WRITE',
      active: true,
    }),
  );
  await assertSucceeds(
    setDoc(requestRef, {
      uid: 'vip-payer',
      userName: 'VIP Payer',
      email: 'vip@example.com',
      plan: 'bronze',
      amountCents: 1500,
      durationDays: 30,
      provider: 'pix_manual',
      status: 'pending',
      createdAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(getDoc(requestRef));
  await assertFails(getDoc(doc(otherDb, 'vip_payment_requests/vip-request')));
  await assertFails(
    setDoc(doc(payerDb, 'vip_payment_orders/client-order'), {
      uid: 'vip-payer',
      status: 'approved',
    }),
  );
  await assertSucceeds(getDoc(doc(payerDb, 'vip_payment_orders/vip-order')));
  await assertFails(getDoc(doc(otherDb, 'vip_payment_orders/vip-order')));

  await assertSucceeds(
    updateDoc(doc(adminDb, 'users/vip-payer'), {
      vipPlan: 'Bronze',
      vipExpiresAt: expiresAt,
      updatedAt: serverTimestamp(),
      lastManualPayment: {
        method: 'pix_manual',
        approvedAt: serverTimestamp(),
        approvedBy: 'vip-admin',
        plan: 'Bronze',
      },
    }),
  );
  await assertSucceeds(
    updateDoc(doc(adminDb, 'vip_payment_requests/vip-request'), {
      status: 'approved',
      reviewedAt: serverTimestamp(),
      reviewedBy: 'vip-admin',
      expiresAt,
    }),
  );
});

test('admin rules reserve user reads and VIP changes for admin claims', async () => {
  const ownerDb = testEnvironment
    .authenticatedContext('group-owner')
    .firestore();
  const attackerDb = testEnvironment
    .authenticatedContext('attacker')
    .firestore();
  const adminDb = testEnvironment
    .authenticatedContext('console-admin', { admin: true })
    .firestore();

  await assertSucceeds(getDoc(doc(attackerDb, 'users/attacker')));
  await assertFails(getDoc(doc(attackerDb, 'users/group-owner')));
  await assertSucceeds(getDocs(collection(adminDb, 'users')));
  await assertSucceeds(
    updateDoc(doc(ownerDb, 'users/group-owner'), {
      'personal_info.full_name': 'Updated name',
    }),
  );
  await assertFails(
    updateDoc(doc(attackerDb, 'users/attacker'), {
      role: 'master',
    }),
  );
  await assertFails(
    updateDoc(doc(attackerDb, 'users/attacker'), {
      vipPlan: 'Bronze',
      vipExpiresAt: future,
      updatedAt: future,
    }),
  );
  await assertSucceeds(
    updateDoc(doc(adminDb, 'users/group-owner'), {
      vipPlan: 'Bronze',
      vipExpiresAt: future,
      updatedAt: future,
    }),
  );
  await assertFails(
    updateDoc(doc(adminDb, 'users/group-owner'), {
      vipPlan: 'community_plus',
      vipExpiresAt: future,
      updatedAt: future,
    }),
  );
  await assertFails(
    updateDoc(doc(adminDb, 'users/group-owner'), {
      vipPlan: 'Ouro',
      vipExpiresAt: Timestamp.fromDate(new Date(Date.now() - 1000)),
      updatedAt: future,
    }),
  );
});
