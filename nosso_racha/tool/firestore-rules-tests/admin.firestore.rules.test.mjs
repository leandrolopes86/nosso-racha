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
      vipPlan: 'Ouro',
      vipExpiresAt: Timestamp.fromDate(new Date(Date.now() - 1000)),
      updatedAt: future,
    }),
  );
});
