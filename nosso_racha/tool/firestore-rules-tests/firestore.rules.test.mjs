import assert from 'node:assert/strict';
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
  collectionGroup,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  or,
  query,
  setDoc,
  serverTimestamp,
  Timestamp,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const projectId = 'demo-nosso-racha';
const rulesPath = fileURLToPath(
  new URL('../../firestore.rules', import.meta.url),
);

let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: await readFile(rulesPath, 'utf8'),
    },
  });

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const future = Timestamp.fromDate(new Date(Date.now() + 24 * 60 * 60 * 1000));

    await setDoc(doc(db, 'groups/team'), {
      owner_id: 'organizer',
      plan: 'organizer_vip',
      plan_status: 'active',
      open_events_count: 0,
      athlete_count: 2,
      co_organizer_count: 1,
    });
    await setDoc(doc(db, 'groups/legacy-team'), {
      ownerId: 'organizer-vip',
      plan: 'organizer_vip',
      plan_status: 'active',
    });
    await setDoc(doc(db, 'groups/expired-vip-team'), {
      owner_id: 'expired-vip-owner',
      plan: 'organizer_vip',
      plan_status: 'expired',
    });
    await setDoc(doc(db, 'groups/no-expiry-vip-team'), {
      owner_id: 'no-expiry-vip-owner',
      plan: 'organizer_vip',
      plan_status: 'active',
    });
    await setDoc(doc(db, 'groups/platinum-vip-team'), {
      owner_id: 'platinum-vip-owner',
      vipPlan: 'Platinum',
      vipExpiresAt: future,
    });
    await setDoc(doc(db, 'groups/owner-platinum-vip-team'), {
      owner_id: 'platinum-vip-user',
    });
    await setDoc(doc(db, 'groups/organizer-id-vip-team'), {
      organizer_id: 'platinum-vip-user',
    });
    await setDoc(doc(db, 'groups/event-capacity-team'), {
      owner_id: 'organizer',
      open_events_count: 0,
      athlete_count: 0,
      co_organizer_count: 0,
    });
    await setDoc(doc(db, 'groups/manager-event-capacity-team'), {
      owner_id: 'organizer',
      open_events_count: 0,
      athlete_count: 0,
      co_organizer_count: 0,
    });
    await setDoc(
      doc(db, 'groups/manager-event-capacity-team/members/event-manager'),
      {
        uid: 'event-manager',
        role: 'co_organizer',
      },
    );
    await setDoc(
      doc(db, 'groups/member-capacity-team'),
      {
        owner_id: 'organizer',
        open_events_count: 0,
        athlete_count: 0,
        co_organizer_count: 0,
      },
    );
    await setDoc(doc(db, 'groups/membership-limit-target'), {
      owner_id: 'organizer',
      open_events_count: 0,
      athlete_count: 0,
      co_organizer_count: 0,
    });
    await setDoc(doc(db, 'groups/athlete-limit-team'), {
      owner_id: 'organizer',
      open_events_count: 0,
      athlete_count: 40,
      co_organizer_count: 0,
    });
    await setDoc(doc(db, 'groups/co-organizer-limit-team'), {
      owner_id: 'organizer',
      open_events_count: 0,
      athlete_count: 0,
      co_organizer_count: 3,
    });
    await setDoc(doc(db, 'groups/vip-capacity-team'), {
      owner_id: 'organizer-vip',
      open_events_count: 0,
      athlete_count: 40,
      co_organizer_count: 3,
    });
    await setDoc(doc(db, 'users/free-athlete'), {
      role: 'athlete',
      status: 'active',
      plan: 'free',
      is_owner: false,
      permissions: {},
      personal_info: { full_name: 'Athlete', phone_raw: '' },
      football_stats: {
        nickname: '',
        positions: ['Atacante'],
        rating: 0.0,
      },
      payment_info: { pix_key: '' },
    });
    await setDoc(doc(db, 'users/limited-athlete'), {
      role: 'athlete',
      status: 'active',
      plan: 'free',
      group_ids: ['old-group-1', 'old-group-2'],
      is_owner: false,
      permissions: {},
    });
    await setDoc(doc(db, 'users/capacity-test-athlete'), {
      role: 'athlete',
      status: 'active',
      plan: 'free',
      group_ids: [],
      permissions: {},
    });
    await setDoc(doc(db, 'users/capacity-test-co-organizer'), {
      role: 'athlete',
      status: 'active',
      plan: 'free',
      group_ids: [],
      permissions: {},
    });
    await setDoc(doc(db, 'users/vip-capacity-athlete'), {
      role: 'athlete',
      status: 'active',
      plan: 'free',
      group_ids: [],
      permissions: {},
    });
    await setDoc(doc(db, 'users/organizer'), {
      role: 'org',
      status: 'active',
      plan: 'free',
      permissions: { can_register_user: true },
    });
    await setDoc(doc(db, 'users/event-manager'), {
      role: 'org',
      status: 'active',
      plan: 'free',
      permissions: { can_create_event: true },
    });
    await setDoc(doc(db, 'users/event-permission-creator'), {
      role: 'org',
      status: 'active',
      plan: 'free',
      permissions: { can_create_event: true },
    });
    await setDoc(doc(db, 'users/organizer-vip'), {
      role: 'athlete',
      status: 'active',
      plan: 'organizer_vip',
      subscription: {
        status: 'active',
        expires_at: future,
      },
      permissions: {},
    });
    await setDoc(doc(db, 'users/platinum-vip-owner'), {
      role: 'athlete',
      status: 'active',
      plan: 'free',
      vipPlan: 'Free',
      vipExpiresAt: null,
      permissions: {},
    });
    await setDoc(doc(db, 'users/platinum-vip-user'), {
      role: 'athlete',
      status: 'active',
      plan: 'free',
      vipPlan: 'Platinum',
      vipExpiresAt: future,
      permissions: {},
    });
    await setDoc(doc(db, 'users/expired-vip-owner'), {
      role: 'org',
      status: 'active',
      plan: 'organizer_vip',
      plan_status: 'expired',
      permissions: {},
    });
    await setDoc(doc(db, 'users/no-expiry-vip-owner'), {
      role: 'org',
      status: 'active',
      plan: 'organizer_vip',
      plan_status: 'active',
      permissions: {},
    });
    await setDoc(doc(db, 'users/master'), {
      role: 'master',
      status: 'active',
      plan: 'free',
      permissions: {},
    });
    await setDoc(doc(db, 'groups/team/members/member'), {
      uid: 'member',
      role: 'member',
    });
    await setDoc(doc(db, 'groups/team/members/co-organizer'), {
      uid: 'co-organizer',
      role: 'co_organizer',
    });
    await setDoc(doc(db, 'groups/legacy-team/members/admin-manager'), {
      uid: 'admin-manager',
      role: 'admin',
    });
    await setDoc(doc(db, 'groups/legacy-team/members/organizer-manager'), {
      uid: 'organizer-manager',
      role: 'organizer',
    });
    await setDoc(doc(db, 'groups/team/members/permitted-member'), {
      uid: 'permitted-member',
      role: 'member',
    });
    await setDoc(doc(db, 'users/permitted-member'), {
      role: 'athlete',
      permissions: { can_create_event: true },
    });

    await setDoc(doc(db, 'events/private-event'), {
      info: { visibility: 'private', group_id: 'team', status: 'scheduled' },
      audit: { created_by: 'organizer' },
      participants: [],
    });
    await setDoc(doc(db, 'events/public-event'), {
      info: {
        visibility: 'public',
        group_id: 'team',
        status: 'published',
      },
      audit: { created_by: 'organizer' },
      participants: [],
    });
    await setDoc(doc(db, 'events/scheduled-public-event'), {
      info: {
        visibility: 'public',
        group_id: 'team',
        status: 'scheduled',
      },
      audit: { created_by: 'organizer' },
      participants: [],
    });
    await setDoc(doc(db, 'events/legacy-private-event'), {
      group_id: 'legacy-team',
      info: { visibility: 'private' },
      audit: { created_by: 'another-user' },
      participants: [],
    });
    await setDoc(doc(db, 'events/legacy-nested-private-event'), {
      info: { group_id: 'legacy-team', visibility: 'private' },
      audit: { created_by: 'another-user' },
      participants: [],
    });
    await setDoc(doc(db, 'events/private-event/notes/secret'), {
      content: 'private event data',
    });
    await setDoc(doc(db, 'events/private-event/pending_payments/member'), {
      amount: 10,
    });
    await setDoc(doc(db, 'events/private-event/pending_payments/other'), {
      amount: 20,
    });
    await setDoc(doc(db, 'events/private-event/matches/game'), {
      winner: 'home',
    });
    await setDoc(doc(db, 'events/private-event/invites/valid-token'), {
      created_by: 'organizer',
      active: true,
      expires_at: future,
    });
    await setDoc(doc(db, 'events/private-event/invites/expired-token'), {
      created_by: 'organizer',
      active: true,
      expires_at: Timestamp.fromDate(new Date(Date.now() - 1000)),
    });
    await setDoc(doc(db, 'events/private-event/access/granted-user'), {
      invite_token: 'valid-token',
    });
  });
});

after(async () => {
  await testEnvironment?.cleanup();
});

test('only published public events are readable anonymously', async () => {
  const db = testEnvironment.unauthenticatedContext().firestore();

  await assertSucceeds(getDoc(doc(db, 'events/public-event')));
  await assertFails(getDoc(doc(db, 'events/private-event')));
  await assertFails(getDoc(doc(db, 'events/scheduled-public-event')));

  const publicEvents = await assertSucceeds(
    getDocs(
      query(
        collection(db, 'events'),
        where('info.visibility', 'in', ['public', 'moderated']),
        where('info.status', 'in', ['published', 'in_progress', 'finished']),
      ),
    ),
  );
  assert.deepEqual(
    publicEvents.docs.map((event) => event.id),
    ['public-event'],
  );
});

test('only group members can read their unpublished events early', async () => {
  const memberDb = testEnvironment.authenticatedContext('member').firestore();
  const outsiderDb = testEnvironment
    .authenticatedContext('outsider')
    .firestore();
  const anonymousDb = testEnvironment.unauthenticatedContext().firestore();

  await assertSucceeds(getDoc(doc(memberDb, 'events/scheduled-public-event')));
  await assertFails(getDoc(doc(outsiderDb, 'events/scheduled-public-event')));
  await assertFails(getDoc(doc(anonymousDb, 'events/scheduled-public-event')));

  const groupEventsQuery = (db) =>
    query(
      collection(db, 'events'),
      or(
        where('info.group_id', '==', 'team'),
        where('group_id', '==', 'team'),
      ),
    );
  await assertSucceeds(getDocs(groupEventsQuery(memberDb)));
  await assertFails(getDocs(groupEventsQuery(outsiderDb)));
});

test('private event access is limited to members and users granted invite access', async () => {
  const memberDb = testEnvironment.authenticatedContext('member').firestore();
  const grantedDb = testEnvironment
    .authenticatedContext('granted-user')
    .firestore();
  const outsiderDb = testEnvironment.authenticatedContext('outsider').firestore();

  await assertSucceeds(getDoc(doc(memberDb, 'events/private-event')));
  await assertSucceeds(getDoc(doc(grantedDb, 'events/private-event')));
  await assertFails(getDoc(doc(outsiderDb, 'events/private-event')));
});

test('group owners can list events linked through current or legacy group fields', async () => {
  const groupOwnerDb = testEnvironment
    .authenticatedContext('organizer-vip')
    .firestore();
  const outsiderDb = testEnvironment
    .authenticatedContext('outsider')
    .firestore();
  const organizationEventsQuery = (db) =>
    query(
      collection(db, 'events'),
      or(
        where('info.group_id', '==', 'legacy-team'),
        where('group_id', '==', 'legacy-team'),
      ),
    );

  const events = await assertSucceeds(
    getDocs(organizationEventsQuery(groupOwnerDb)),
  );
  assert.deepEqual(
    events.docs.map((event) => event.id).sort(),
    ['legacy-nested-private-event', 'legacy-private-event'],
  );
  await assertFails(getDoc(doc(outsiderDb, 'events/legacy-private-event')));
});

test('group settings and finance data require an active VIP group manager', async () => {
  const ownerDb = testEnvironment
    .authenticatedContext('organizer-vip')
    .firestore();
  const noExpiryOwnerDb = testEnvironment
    .authenticatedContext('no-expiry-vip-owner')
    .firestore();
  const platinumOwnerDb = testEnvironment
    .authenticatedContext('platinum-vip-owner')
    .firestore();
  const platinumUserDb = testEnvironment
    .authenticatedContext('platinum-vip-user')
    .firestore();
  const adminDb = testEnvironment
    .authenticatedContext('admin-manager')
    .firestore();
  const groupOrganizerDb = testEnvironment
    .authenticatedContext('organizer-manager')
    .firestore();
  const outsiderDb = testEnvironment.authenticatedContext('outsider').firestore();
  const groupSettings = doc(ownerDb, 'groups/legacy-team/settings/general');
  const paymentSettings = doc(
    ownerDb,
    'groups/legacy-team/settings/payment_gateway',
  );
  const outsiderSettings = doc(
    outsiderDb,
    'groups/legacy-team/settings/general',
  );
  const transaction = doc(ownerDb, 'transactions/group-transaction');

  await assertSucceeds(getDoc(groupSettings));
  await assertFails(getDoc(outsiderSettings));
  await assertFails(getDoc(paymentSettings));
  await assertFails(
    setDoc(paymentSettings, { access_token: 'client-secret' }),
  );
  await assertFails(
    getDoc(doc(ownerDb, 'settings/payment_gateway')),
  );
  await assertSucceeds(setDoc(groupSettings, { default_include_goalkeepers: true }));
  await assertFails(
    setDoc(doc(ownerDb, 'groups/team/settings/general'), {
      default_include_goalkeepers: true,
    }),
  );
  await assertSucceeds(
    setDoc(
      doc(adminDb, 'groups/legacy-team/settings/admin'),
      { default_include_goalkeepers: true },
    ),
  );
  await assertSucceeds(
    setDoc(
      doc(groupOrganizerDb, 'groups/legacy-team/settings/organizer'),
      { default_include_goalkeepers: true },
    ),
  );
  await assertSucceeds(
    updateDoc(doc(groupOrganizerDb, 'groups/legacy-team'), {
      name: 'Grupo atualizado',
      city: 'São Paulo',
      neighborhood: 'Centro',
    }),
  );
  await assertFails(
    updateDoc(doc(groupOrganizerDb, 'groups/legacy-team'), {
      description: 'Alteração não permitida',
    }),
  );
  await assertFails(
    setDoc(doc(outsiderDb, 'groups/legacy-team/settings/general'), {
      default_include_goalkeepers: false,
    }),
  );
  await assertSucceeds(
    setDoc(transaction, {
      group_id: 'legacy-team',
      amount: 10,
      type: 'credit',
    }),
  );
  await assertFails(
    setDoc(doc(outsiderDb, 'transactions/outsider-transaction'), {
      group_id: 'legacy-team',
      amount: 10,
      type: 'credit',
    }),
  );
  await assertFails(
    setDoc(doc(ownerDb, 'groups/expired-vip-team/settings/general'), {
      default_include_goalkeepers: true,
    }),
  );
  await assertFails(
    setDoc(doc(noExpiryOwnerDb, 'groups/no-expiry-vip-team/settings/general'), {
      default_include_goalkeepers: true,
    }),
  );
  await assertSucceeds(
    setDoc(doc(platinumOwnerDb, 'groups/platinum-vip-team/settings/general'), {
      default_include_goalkeepers: true,
    }),
  );
  await assertSucceeds(
    setDoc(
      doc(platinumUserDb, 'groups/owner-platinum-vip-team/settings/general'),
      { default_include_goalkeepers: true },
    ),
  );
  await assertSucceeds(
    setDoc(
      doc(platinumUserDb, 'groups/organizer-id-vip-team/settings/general'),
      { default_include_goalkeepers: true },
    ),
  );
});

test('goalkeeper Pix details are private and payment requires the atomic expense', async () => {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'events/goalie-payment-event'), {
      info: {
        visibility: 'private',
        group_id: 'legacy-team',
      },
      audit: { created_by: 'organizer-vip' },
      participants: [
        {
          uid: 'keeper',
          name: 'Goalkeeper',
          role_in_match: 'goalkeeper',
          status: 'active',
          goalie_payment_status: 'none',
        },
      ],
    });
    await setDoc(
      doc(db, 'events/goalie-payment-event/goalie_payments/keeper'),
      {
        uid: 'keeper',
        pix_key: '',
        goalie_payment_status: 'none',
      },
    );
    await setDoc(doc(db, 'events/goalie-payment-without-pix-event'), {
      info: {
        visibility: 'private',
        group_id: 'legacy-team',
      },
      audit: { created_by: 'organizer-vip' },
      participants: [
        {
          uid: 'keeper-without-pix',
          name: 'Goalkeeper without Pix',
          role_in_match: 'goalkeeper',
          status: 'active',
          goalie_payment_status: 'none',
        },
      ],
    });
  });

  const organizerDb = testEnvironment
    .authenticatedContext('organizer-vip')
    .firestore();
  const goalkeeperDb = testEnvironment.authenticatedContext('keeper').firestore();
  const outsiderDb = testEnvironment.authenticatedContext('outsider').firestore();
  const paymentPath = 'events/goalie-payment-event/goalie_payments/keeper';
  const organizerPayment = doc(organizerDb, paymentPath);
  const goalkeeperPayment = doc(goalkeeperDb, paymentPath);

  await assertSucceeds(getDoc(organizerPayment));
  await assertSucceeds(getDoc(goalkeeperPayment));
  await assertFails(getDoc(doc(outsiderDb, paymentPath)));

  await assertFails(
    updateDoc(organizerPayment, {
      goalie_payment_status: 'pending_confirmation',
      amount: 40,
      transaction_id: 'missing-expense',
    }),
  );

  const batch = writeBatch(organizerDb);
  batch.update(organizerPayment, {
    goalie_payment_status: 'pending_confirmation',
    amount: 40,
    marked_at: serverTimestamp(),
    marked_by_uid: 'organizer-vip',
    marked_by_name: 'Organizer',
    transaction_id: 'goalie-payment-expense',
  });
  batch.set(doc(organizerDb, 'transactions/goalie-payment-expense'), {
    group_id: 'legacy-team',
    amount: 40,
    type: 'debit',
    category: 'goalkeeper_payment',
    related_event_id: 'goalie-payment-event',
    related_user_id: 'keeper',
    registered_by_uid: 'organizer-vip',
  });
  await assertSucceeds(batch.commit());

  const noPixEventPath = 'events/goalie-payment-without-pix-event';
  const noPixPaymentPath =
    `${noPixEventPath}/goalie_payments/keeper-without-pix`;
  const noPixExpenseId = 'goalie-payment-without-pix-expense';
  const noPixBatch = writeBatch(organizerDb);
  noPixBatch.update(doc(organizerDb, noPixEventPath), {
    participants: [
      {
        uid: 'keeper-without-pix',
        name: 'Goalkeeper without Pix',
        role_in_match: 'goalkeeper',
        status: 'active',
        goalie_payment_status: 'pending_confirmation',
      },
    ],
  });
  noPixBatch.set(doc(organizerDb, noPixPaymentPath), {
    uid: 'keeper-without-pix',
    pix_key: '',
    goalie_payment_status: 'pending_confirmation',
    amount: 25,
    marked_at: serverTimestamp(),
    marked_by_uid: 'organizer-vip',
    marked_by_name: 'Organizer',
    transaction_id: noPixExpenseId,
  });
  noPixBatch.set(doc(organizerDb, `transactions/${noPixExpenseId}`), {
    group_id: 'legacy-team',
    amount: 25,
    type: 'debit',
    category: 'goalkeeper_payment',
    related_event_id: 'goalie-payment-without-pix-event',
    related_user_id: 'keeper-without-pix',
    registered_by_uid: 'organizer-vip',
  });
  await assertSucceeds(noPixBatch.commit());

  await assertFails(
    updateDoc(organizerPayment, {
      goalie_payment_status: 'confirmed',
      confirmed_at: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(outsiderDb, paymentPath), {
      goalie_payment_status: 'confirmed',
      confirmed_at: serverTimestamp(),
    }),
  );
  await assertSucceeds(
    updateDoc(goalkeeperPayment, {
      goalie_payment_status: 'confirmed',
      confirmed_at: serverTimestamp(),
    }),
  );
});

test('active Platinum user VIP can create events', async () => {
  const platinumDb = testEnvironment
    .authenticatedContext('platinum-vip-user')
    .firestore();

  await assertSucceeds(
    setDoc(doc(platinumDb, 'events/platinum-user-event'), {
      info: { group_id: 'team', visibility: 'public' },
      audit: { created_by: 'platinum-vip-user' },
    }),
  );
});

test('users can only update their own allowed profile fields', async () => {
  const athleteDb = testEnvironment
    .authenticatedContext('free-athlete')
    .firestore();
  const otherUserDb = testEnvironment
    .authenticatedContext('other-user')
    .firestore();

  await assertSucceeds(
    updateDoc(doc(athleteDb, 'users/free-athlete'), {
      'personal_info.full_name': 'Updated Athlete',
    }),
  );
  await assertFails(
    updateDoc(doc(athleteDb, 'users/free-athlete'), {
      'football_stats.positions': ['Atacante', 'Goleiro'],
    }),
  );
  await assertFails(
    updateDoc(doc(athleteDb, 'users/free-athlete'), {
      plan: 'athlete_vip',
    }),
  );
  await assertFails(
    updateDoc(doc(otherUserDb, 'users/free-athlete'), {
      'personal_info.full_name': 'Changed by another user',
    }),
  );
  await assertSucceeds(getDoc(doc(athleteDb, 'users/free-athlete')));
  await assertFails(getDoc(doc(otherUserDb, 'users/free-athlete')));
  await assertFails(
    updateDoc(doc(athleteDb, 'users/free-athlete'), {
      role: 'master',
    }),
  );
});

test('only group members can access group subcollections', async () => {
  const memberDb = testEnvironment.authenticatedContext('member').firestore();
  const outsiderDb = testEnvironment.authenticatedContext('outsider').firestore();

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'groups/team/notes/private'),
      { content: 'group-only' },
    );
  });

  await assertSucceeds(
    getDoc(doc(memberDb, 'groups/team/notes/private')),
  );
  await assertFails(
    getDoc(doc(outsiderDb, 'groups/team/notes/private')),
  );
});

test('group membership bookkeeping requires an owner-authorized batch', async () => {
  const ownerDb = testEnvironment
    .authenticatedContext('organizer')
    .firestore();
  const outsiderDb = testEnvironment
    .authenticatedContext('outsider')
    .firestore();
  const nonce = 'membership-add-nonce';

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'users/membership-target'),
      { group_ids: [] },
    );
  });

  const batch = writeBatch(ownerDb);
  batch.set(doc(ownerDb, 'groups/team/members/membership-target'), {
    uid: 'membership-target',
    role: 'member',
  });
  batch.update(doc(ownerDb, 'groups/team'), {
    athlete_count: 3,
    capacity_member_uid: 'membership-target',
    capacity_member_role: 'member',
    capacity_member_delta: 1,
    capacity_member_nonce: nonce,
  });
  batch.update(doc(ownerDb, 'users/membership-target'), {
    group_ids: ['team'],
    membership_change_group_id: 'team',
    membership_change_nonce: nonce,
  });
  await assertSucceeds(batch.commit());

  await assertFails(
    updateDoc(doc(outsiderDb, 'users/membership-target'), {
      group_ids: ['another-group'],
    }),
  );
});

test('only authorized organizers can create organizations', async () => {
  const athleteDb = testEnvironment
    .authenticatedContext('free-athlete')
    .firestore();
  const organizerDb = testEnvironment
    .authenticatedContext('organizer')
    .firestore();
  const organizerVipDb = testEnvironment
    .authenticatedContext('organizer-vip')
    .firestore();

  await assertFails(
    setDoc(doc(athleteDb, 'groups/athlete-created'), {
      owner_id: 'free-athlete',
      name: 'Unauthorized group',
    }),
  );
  await assertFails(
    setDoc(doc(organizerDb, 'groups/non-vip-organizer-created'), {
      owner_id: 'organizer',
      name: 'Non-VIP organizer group',
    }),
  );
  await assertSucceeds(
    (async () => {
      const batch = writeBatch(organizerVipDb);
      batch.set(doc(organizerVipDb, 'groups/organizer-vip-created'), {
        owner_id: 'organizer-vip',
        name: 'Organizer VIP group',
        open_events_count: 0,
        athlete_count: 0,
        co_organizer_count: 0,
      });
      batch.set(
        doc(
          organizerVipDb,
          'groups/organizer-vip-created/members/organizer-vip',
        ),
        {
          uid: 'organizer-vip',
          role: 'owner',
        },
      );
      batch.update(doc(organizerVipDb, 'users/organizer-vip'), {
        group_ids: ['organizer-vip-created'],
        membership_change_group_id: 'organizer-vip-created',
        membership_change_nonce: 'organizer-vip-created',
      });
      await batch.commit();
    })(),
  );
});

test('external athletes can create and read only their own join requests', async () => {
  const athleteDb = testEnvironment
    .authenticatedContext('free-athlete')
    .firestore();
  const otherAthleteDb = testEnvironment
    .authenticatedContext('other-athlete')
    .firestore();
  const organizerDb = testEnvironment
    .authenticatedContext('organizer')
    .firestore();
  const requestRef = doc(
    athleteDb,
    'events/public-event/join_requests/free-athlete',
  );

  await assertSucceeds(
    setDoc(requestRef, {
      uid: 'free-athlete',
      name: 'Athlete',
      nickname: 'Player',
      role_in_match: 'line',
      status: 'pending',
      requested_at: Timestamp.now(),
    }),
  );
  await assertSucceeds(getDoc(requestRef));
  await assertFails(
    getDoc(
      doc(
        otherAthleteDb,
        'events/public-event/join_requests/free-athlete',
      ),
    ),
  );
  await assertFails(
    getDocs(collection(athleteDb, 'events/public-event/join_requests')),
  );
  await assertFails(
    setDoc(
      doc(athleteDb, 'events/public-event/join_requests/other-athlete'),
      {
        uid: 'free-athlete',
        name: 'Athlete',
        nickname: '',
        role_in_match: 'line',
        status: 'pending',
        requested_at: Timestamp.now(),
      },
    ),
  );
  await assertSucceeds(
    getDocs(collection(organizerDb, 'events/public-event/join_requests')),
  );
  await assertSucceeds(
    updateDoc(doc(organizerDb, 'events/public-event'), {
      participants: [
        {
          uid: 'free-athlete',
          status: 'active',
          role_in_match: 'line',
          is_external: true,
        },
      ],
    }),
  );
  await assertSucceeds(
    deleteDoc(
      doc(
        organizerDb,
        'events/public-event/join_requests/free-athlete',
      ),
    ),
  );
  await assertSucceeds(
    setDoc(requestRef, {
      uid: 'free-athlete',
      name: 'Athlete',
      nickname: 'Player',
      role_in_match: 'line',
      status: 'pending',
      requested_at: Timestamp.now(),
    }),
  );
  await assertSucceeds(deleteDoc(requestRef));
});

test('join request profile snapshots must match the athlete profile', async () => {
  const athleteDb = testEnvironment
    .authenticatedContext('profile-snapshot-athlete')
    .firestore();
  const organizerDb = testEnvironment
    .authenticatedContext('organizer')
    .firestore();
  const requestRef = doc(
    athleteDb,
    'events/public-event/join_requests/profile-snapshot-athlete',
  );
  const profile = {
    name: 'Athlete',
    nickname: '',
    phone: '',
    positions: ['Atacante'],
    rating: 0.0,
    pix_key: '',
    can_play_multiple_positions: false,
  };
  const request = {
    uid: 'profile-snapshot-athlete',
    name: 'Athlete',
    nickname: '',
    role_in_match: 'line',
    status: 'pending',
    requested_at: Timestamp.now(),
    profile,
  };

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'users/profile-snapshot-athlete'),
      {
        role: 'athlete',
        status: 'active',
        plan: 'free',
        is_owner: false,
        personal_info: { full_name: 'Athlete', phone_raw: '' },
        football_stats: {
          nickname: '',
          positions: ['Atacante'],
          rating: 0.0,
        },
        payment_info: { pix_key: '' },
      },
    );
  });

  await assertFails(
    setDoc(requestRef, {
      ...request,
      profile: { ...profile, rating: 100 },
    }),
  );
  await assertSucceeds(setDoc(requestRef, request));
  await assertFails(getDoc(doc(organizerDb, 'users/profile-snapshot-athlete')));
});

test('organizers can decide requests and athletes can resubmit rejected ones', async () => {
  const athleteDb = testEnvironment
    .authenticatedContext('rejected-request-athlete')
    .firestore();
  const organizerDb = testEnvironment
    .authenticatedContext('organizer')
    .firestore();
  const requestPath =
    'events/public-event/join_requests/rejected-request-athlete';
  const requestRef = doc(athleteDb, requestPath);
  const requestData = {
    uid: 'rejected-request-athlete',
    name: 'Athlete',
    nickname: '',
    role_in_match: 'line',
    status: 'pending',
    requested_at: Timestamp.now(),
  };

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'users/rejected-request-athlete'),
      {
        role: 'athlete',
        status: 'active',
        plan: 'free',
        is_owner: false,
        personal_info: { full_name: 'Athlete', phone_raw: '' },
        football_stats: { nickname: '', positions: ['Atacante'] },
        payment_info: { pix_key: '' },
      },
    );
    await setDoc(doc(context.firestore(), requestPath), {
      ...requestData,
      status: 'rejected',
      reviewed_at: Timestamp.now(),
      reviewed_by: 'organizer',
    });
  });

  await assertSucceeds(
    setDoc(requestRef, {
      ...requestData,
      profile: {
        name: 'Athlete',
        nickname: '',
        phone: '',
        positions: ['Atacante'],
        rating: 0.0,
        pix_key: '',
        can_play_multiple_positions: false,
      },
    }),
  );
  await assertSucceeds(
    updateDoc(doc(organizerDb, requestPath), {
      status: 'approved',
      reviewed_at: Timestamp.now(),
      reviewed_by: 'organizer',
    }),
  );
});

test('new free users must choose one position and goalkeeper Pix is optional', async () => {
  const db = testEnvironment.authenticatedContext('new-athlete').firestore();
  const userRef = doc(db, 'users/new-athlete');
  const baseUser = {
    role: 'athlete',
    status: 'active',
    plan: 'free',
    is_owner: false,
    permissions: {},
    football_stats: { positions: ['Atacante'] },
    payment_info: { pix_key: '' },
  };

  await assertSucceeds(setDoc(userRef, baseUser));

  const goalkeeperDb = testEnvironment
    .authenticatedContext('new-goalkeeper')
    .firestore();
  const goalkeeperRef = doc(goalkeeperDb, 'users/new-goalkeeper');
  await assertSucceeds(
    setDoc(goalkeeperRef, {
      ...baseUser,
      football_stats: { positions: ['Goleiro'] },
    }),
  );
  await assertSucceeds(
    setDoc(goalkeeperRef, {
      ...baseUser,
      football_stats: { positions: ['Goleiro'] },
      payment_info: { pix_key: 'keeper@example.com' },
    }),
  );
});

test('goalkeeper position does not require Pix and regular managers cannot change plans', async () => {
  const athleteDb = testEnvironment
    .authenticatedContext('free-athlete')
    .firestore();
  const managerDb = testEnvironment
    .authenticatedContext('organizer')
    .firestore();
  const masterDb = testEnvironment
    .authenticatedContext('master')
    .firestore();
  const adminDb = testEnvironment
    .authenticatedContext('rules-admin', { admin: true })
    .firestore();

  await assertSucceeds(
    updateDoc(doc(athleteDb, 'users/free-athlete'), {
      'football_stats.positions': ['Goleiro'],
    }),
  );
  await assertSucceeds(
    updateDoc(doc(athleteDb, 'users/free-athlete'), {
      'football_stats.positions': ['Goleiro'],
      'payment_info.pix_key': 'keeper@example.com',
    }),
  );
  await assertSucceeds(
    updateDoc(doc(managerDb, 'users/free-athlete'), {
      status: 'inactive',
    }),
  );
  await assertFails(
    updateDoc(doc(managerDb, 'users/free-athlete'), {
      plan: 'athlete_vip',
    }),
  );
  await assertFails(
    updateDoc(doc(masterDb, 'users/free-athlete'), {
      plan: 'athlete_vip',
    }),
  );
  await assertSucceeds(
    updateDoc(doc(adminDb, 'users/free-athlete'), {
      plan: 'athlete_vip',
    }),
  );
});

test('events must be created by an organizer in their organization', async () => {
  const eventData = (uid) => ({
    info: { group_id: 'team', visibility: 'public' },
    audit: { created_by: uid },
  });
  const ownerDb = testEnvironment
    .authenticatedContext('organizer')
    .firestore();
  const coOrganizerDb = testEnvironment
    .authenticatedContext('co-organizer')
    .firestore();
  const permittedMemberDb = testEnvironment
    .authenticatedContext('permitted-member')
    .firestore();
  const memberDb = testEnvironment.authenticatedContext('member').firestore();
  const outsiderDb = testEnvironment
    .authenticatedContext('outsider')
    .firestore();

  await assertSucceeds(
    setDoc(doc(ownerDb, 'events/owner-event'), eventData('organizer')),
  );
  await assertSucceeds(
    setDoc(
      doc(coOrganizerDb, 'events/co-organizer-event'),
      eventData('co-organizer'),
    ),
  );
  await assertSucceeds(
    setDoc(
      doc(permittedMemberDb, 'events/permitted-member-event'),
      eventData('permitted-member'),
    ),
  );
  await assertFails(
    setDoc(doc(memberDb, 'events/member-event'), eventData('member')),
  );
  await assertFails(
    setDoc(doc(outsiderDb, 'events/outsider-event'), eventData('outsider')),
  );
  await assertFails(
    setDoc(doc(ownerDb, 'events/unlinked-event'), {
      ...eventData('organizer'),
      info: { visibility: 'public' },
    }),
  );
});

test('open event limits require a transaction-bound counter update', async () => {
  const ownerDb = testEnvironment
    .authenticatedContext('organizer')
    .firestore();
  const groupRef = doc(ownerDb, 'groups/event-capacity-team');

  await assertFails(
    setDoc(doc(ownerDb, 'events/unaccounted-open-event'), {
      info: {
        group_id: 'event-capacity-team',
        status: 'scheduled',
        visibility: 'public',
      },
      audit: { created_by: 'organizer' },
    }),
  );

  const createOpenEvent = async (eventId, previousCount) => {
    const batch = writeBatch(ownerDb);
    batch.update(groupRef, {
      open_events_count: previousCount + 1,
      capacity_event_id: eventId,
      capacity_event_delta: 1,
      capacity_event_nonce: `event-${eventId}`,
    });
    batch.set(doc(ownerDb, `events/${eventId}`), {
      info: {
        group_id: 'event-capacity-team',
        status: 'scheduled',
        visibility: 'public',
      },
      audit: { created_by: 'organizer' },
    });
    return batch.commit();
  };

  await assertSucceeds(createOpenEvent('capacity-event-1', 0));
  await assertSucceeds(createOpenEvent('capacity-event-2', 1));
  await assertSucceeds(createOpenEvent('capacity-event-3', 2));
  await assertFails(createOpenEvent('capacity-event-4', 3));
  await assertFails(
    updateDoc(groupRef, {
      open_events_count: 4,
      capacity_event_id: 'forged-event',
      capacity_event_delta: 1,
      capacity_event_nonce: 'forged-nonce',
    }),
  );

  await assertFails(
    updateDoc(doc(ownerDb, 'events/capacity-event-1'), {
      'info.status': 'finished',
    }),
  );
  const closeBatch = writeBatch(ownerDb);
  closeBatch.update(groupRef, {
    open_events_count: 2,
    capacity_event_id: 'capacity-event-1',
    capacity_event_delta: -1,
    capacity_event_nonce: 'close-event-1',
  });
  closeBatch.update(doc(ownerDb, 'events/capacity-event-1'), {
    'info.status': 'finished',
  });
  await assertSucceeds(closeBatch.commit());

  const deleteBatch = writeBatch(ownerDb);
  deleteBatch.update(groupRef, {
    open_events_count: 1,
    capacity_event_id: 'capacity-event-2',
    capacity_event_delta: -1,
    capacity_event_nonce: 'delete-event-2',
  });
  deleteBatch.delete(doc(ownerDb, 'events/capacity-event-2'));
  await assertSucceeds(deleteBatch.commit());

  const reopenBatch = writeBatch(ownerDb);
  reopenBatch.update(groupRef, {
    open_events_count: 2,
    capacity_event_id: 'capacity-event-1',
    capacity_event_delta: 1,
    capacity_event_nonce: 'reopen-event-1',
  });
  reopenBatch.update(doc(ownerDb, 'events/capacity-event-1'), {
    'info.status': 'published',
  });
  await assertSucceeds(reopenBatch.commit());
});

test('group managers can create events with a validated group counter update', async () => {
  const managerDb = testEnvironment
    .authenticatedContext('event-manager')
    .firestore();
  const groupRef = doc(managerDb, 'groups/manager-event-capacity-team');
  const eventId = 'manager-created-event';

  await assertFails(
    updateDoc(groupRef, {
      open_events_count: 1,
      capacity_event_id: 'unpaired-manager-event',
      capacity_event_delta: 1,
      capacity_event_nonce: 'unpaired-manager-event-nonce',
    }),
  );

  const batch = writeBatch(managerDb);

  batch.update(groupRef, {
    open_events_count: 1,
    capacity_event_id: eventId,
    capacity_event_delta: 1,
    capacity_event_nonce: 'manager-created-event-nonce',
  });
  batch.set(doc(managerDb, `events/${eventId}`), {
    info: {
      group_id: 'manager-event-capacity-team',
      status: 'scheduled',
      visibility: 'public',
    },
    audit: { created_by: 'event-manager' },
  });

  await assertSucceeds(batch.commit());

  const creatorDb = testEnvironment
    .authenticatedContext('event-permission-creator')
    .firestore();
  const creatorBatch = writeBatch(creatorDb);
  creatorBatch.update(
    doc(creatorDb, 'groups/manager-event-capacity-team'),
    {
      open_events_count: 2,
      capacity_event_id: 'permission-created-event',
      capacity_event_delta: 1,
      capacity_event_nonce: 'permission-created-event-nonce',
    },
  );
  creatorBatch.set(doc(creatorDb, 'events/permission-created-event'), {
    info: {
      group_id: 'manager-event-capacity-team',
      status: 'scheduled',
      visibility: 'public',
    },
    audit: { created_by: 'event-permission-creator' },
  });

  await assertSucceeds(creatorBatch.commit());
});

test('member limits require membership and counter changes in one batch', async () => {
  const ownerDb = testEnvironment
    .authenticatedContext('organizer')
    .firestore();
  const groupRef = doc(ownerDb, 'groups/member-capacity-team');

  const unindexedBatch = writeBatch(ownerDb);
  unindexedBatch.update(groupRef, {
    athlete_count: 1,
    capacity_member_uid: 'free-athlete',
    capacity_member_role: 'member',
    capacity_member_delta: 1,
    capacity_member_nonce: 'unindexed-member-add',
  });
  unindexedBatch.set(
    doc(ownerDb, 'groups/member-capacity-team/members/free-athlete'),
    {
      uid: 'free-athlete',
      role: 'member',
    },
  );
  await assertFails(unindexedBatch.commit());

  const batch = writeBatch(ownerDb);
  batch.update(groupRef, {
    athlete_count: 1,
    capacity_member_uid: 'free-athlete',
    capacity_member_role: 'member',
    capacity_member_delta: 1,
    capacity_member_nonce: 'member-first-add',
  });
  batch.set(doc(ownerDb, 'groups/member-capacity-team/members/free-athlete'), {
    uid: 'free-athlete',
    role: 'member',
  });
  batch.update(doc(ownerDb, 'users/free-athlete'), {
    group_ids: ['member-capacity-team'],
    membership_change_group_id: 'member-capacity-team',
    membership_change_nonce: 'member-first-add',
  });
  await assertSucceeds(batch.commit());

  await assertFails(
    updateDoc(groupRef, {
      athlete_count: 2,
      capacity_member_uid: 'forged-member',
      capacity_member_role: 'member',
      capacity_member_delta: 1,
      capacity_member_nonce: 'forged-member-add',
    }),
  );

  const removeBatch = writeBatch(ownerDb);
  removeBatch.update(groupRef, {
    athlete_count: 0,
    capacity_member_uid: 'free-athlete',
    capacity_member_role: 'member',
    capacity_member_delta: -1,
    capacity_member_nonce: 'member-first-remove',
  });
  removeBatch.delete(
    doc(ownerDb, 'groups/member-capacity-team/members/free-athlete'),
  );
  removeBatch.update(doc(ownerDb, 'users/free-athlete'), {
    group_ids: [],
    last_removed_group_id: 'member-capacity-team',
    last_membership_change_nonce: 'member-index-remove',
    membership_change_group_id: 'member-capacity-team',
    membership_change_nonce: 'member-first-remove',
  });
  await assertSucceeds(removeBatch.commit());

  const membershipLimitBatch = writeBatch(ownerDb);
  const targetGroupRef = doc(ownerDb, 'groups/membership-limit-target');
  membershipLimitBatch.update(targetGroupRef, {
    athlete_count: 1,
    capacity_member_uid: 'limited-athlete',
    capacity_member_role: 'member',
    capacity_member_delta: 1,
    capacity_member_nonce: 'limited-athlete-add',
  });
  membershipLimitBatch.set(
    doc(
      ownerDb,
      'groups/membership-limit-target/members/limited-athlete',
    ),
    {
      uid: 'limited-athlete',
      role: 'member',
    },
  );
  membershipLimitBatch.update(doc(ownerDb, 'users/limited-athlete'), {
    group_ids: ['old-group-1', 'old-group-2', 'membership-limit-target'],
  });
  await assertFails(membershipLimitBatch.commit());
});

test('organization athlete and co-organizer caps are plan-aware', async () => {
  const ownerDb = testEnvironment
    .authenticatedContext('organizer')
    .firestore();
  const vipDb = testEnvironment
    .authenticatedContext('organizer-vip')
    .firestore();

  const addMember = (db, groupId, uid, role, countField, nextCount, nonce) => {
    const batch = writeBatch(db);
    const groupRef = doc(db, `groups/${groupId}`);
    batch.update(groupRef, {
      [countField]: nextCount,
      capacity_member_uid: uid,
      capacity_member_role: role,
      capacity_member_delta: 1,
      capacity_member_nonce: nonce,
    });
    batch.set(doc(db, `groups/${groupId}/members/${uid}`), {
      uid,
      role,
    });
    batch.update(doc(db, `users/${uid}`), {
      group_ids: [groupId],
      membership_change_group_id: groupId,
      membership_change_nonce: nonce,
    });
    return batch.commit();
  };

  await assertFails(
    addMember(
      ownerDb,
      'athlete-limit-team',
      'capacity-test-athlete',
      'member',
      'athlete_count',
      41,
      'over-athlete-limit',
    ),
  );
  await assertFails(
    addMember(
      ownerDb,
      'co-organizer-limit-team',
      'capacity-test-co-organizer',
      'co_organizer',
      'co_organizer_count',
      4,
      'over-co-organizer-limit',
    ),
  );
  await assertSucceeds(
    addMember(
      vipDb,
      'vip-capacity-team',
      'vip-capacity-athlete',
      'member',
      'athlete_count',
      41,
      'vip-athlete-over-free-limit',
    ),
  );
});

test('private event subcollections require event access', async () => {
  const memberDb = testEnvironment.authenticatedContext('member').firestore();
  const outsiderDb = testEnvironment.authenticatedContext('outsider').firestore();

  await assertSucceeds(getDoc(doc(memberDb, 'events/private-event/notes/secret')));
  await assertFails(
    getDoc(doc(outsiderDb, 'events/private-event/notes/secret')),
  );

  await assertSucceeds(
    getDoc(doc(memberDb, 'events/private-event/matches/game')),
  );
  await assertFails(
    getDoc(doc(outsiderDb, 'events/private-event/matches/game')),
  );
  await assertFails(
    setDoc(doc(memberDb, 'events/private-event/matches/new-game'), {}),
  );
  await assertSucceeds(
    setDoc(
      doc(
        testEnvironment.authenticatedContext('organizer').firestore(),
        'events/private-event/matches/new-game',
      ),
      {},
    ),
  );
});

test('pending payments are private to the payer and event organizers', async () => {
  const memberDb = testEnvironment.authenticatedContext('member').firestore();
  const outsiderDb = testEnvironment.authenticatedContext('outsider').firestore();
  const organizerDb = testEnvironment
    .authenticatedContext('organizer')
    .firestore();

  await assertSucceeds(
    getDoc(doc(memberDb, 'events/private-event/pending_payments/member')),
  );
  await assertFails(
    getDoc(doc(memberDb, 'events/private-event/pending_payments/other')),
  );
  await assertFails(
    getDoc(doc(outsiderDb, 'events/private-event/pending_payments/member')),
  );
  await assertSucceeds(
    getDoc(doc(organizerDb, 'events/private-event/pending_payments/other')),
  );
  await assertFails(
    getDocs(collection(memberDb, 'events/private-event/pending_payments')),
  );
});

test('invite redemption requires a valid invite and only grants access to self', async () => {
  const guestDb = testEnvironment.authenticatedContext('guest').firestore();
  const otherUserDb = testEnvironment
    .authenticatedContext('different-guest')
    .firestore();
  const anonymousDb = testEnvironment.unauthenticatedContext().firestore();

  await assertSucceeds(
    getDoc(doc(guestDb, 'events/private-event/invites/valid-token')),
  );
  await assertFails(
    getDoc(doc(anonymousDb, 'events/private-event/invites/valid-token')),
  );
  await assertFails(
    getDoc(doc(guestDb, 'events/private-event/invites/expired-token')),
  );

  await assertSucceeds(
    setDoc(doc(guestDb, 'events/private-event/access/guest'), {
      invite_token: 'valid-token',
    }),
  );
  await assertFails(
    setDoc(doc(guestDb, 'events/private-event/access/other-user'), {
      invite_token: 'valid-token',
    }),
  );
  await assertFails(
    setDoc(doc(otherUserDb, 'events/private-event/access/different-guest'), {
      invite_token: 'unknown-token',
    }),
  );
});

test('only organizers can create private event invites', async () => {
  const organizerDb = testEnvironment
    .authenticatedContext('organizer')
    .firestore();
  const outsiderDb = testEnvironment.authenticatedContext('outsider').firestore();
  const invite = {
    created_by: 'organizer',
    active: true,
    expires_at: Timestamp.fromDate(new Date(Date.now() + 6 * 24 * 60 * 60 * 1000)),
  };

  await assertSucceeds(
    setDoc(doc(organizerDb, 'events/private-event/invites/new-token'), invite),
  );
  await assertFails(
    setDoc(doc(outsiderDb, 'events/private-event/invites/forbidden'), invite),
  );
  await assertFails(
    setDoc(doc(organizerDb, 'events/public-event/invites/not-private'), invite),
  );
});

test('group members can append themselves but outsiders cannot change participants', async () => {
  const memberDb = testEnvironment.authenticatedContext('member').firestore();
  const outsiderDb = testEnvironment
    .authenticatedContext('outsider')
    .firestore();

  await assertSucceeds(
    updateDoc(doc(memberDb, 'events/private-event'), {
      participants: [
        {
          uid: 'member',
          status: 'active',
          role_in_match: 'line',
          is_external: false,
        },
      ],
    }),
  );
  await assertFails(
    updateDoc(doc(outsiderDb, 'events/public-event'), {
      participants: [
        {
          uid: 'outsider',
          status: 'active',
          role_in_match: 'line',
          is_external: true,
        },
      ],
    }),
  );
  await assertFails(
    updateDoc(doc(memberDb, 'events/private-event'), {
      'info.visibility': 'public',
    }),
  );
});

test('group membership documents do not expose other members to ordinary users', async () => {
  const memberDb = testEnvironment.authenticatedContext('member').firestore();

  await assertSucceeds(getDoc(doc(memberDb, 'groups/team/members/member')));
  await assertFails(
    getDoc(doc(memberDb, 'groups/team/members/co-organizer')),
  );
  await assertSucceeds(
    getDocs(
      query(
        collectionGroup(memberDb, 'members'),
        where('uid', '==', 'member'),
      ),
    ),
  );
  await assertFails(
    getDocs(
      query(
        collectionGroup(memberDb, 'members'),
        where('uid', '==', 'co-organizer'),
      ),
    ),
  );
  await assertFails(getDocs(collectionGroup(memberDb, 'members')));
});

test('VIP catalog exposes only the five supported plans and configured limits', async () => {
  const anonymousDb = testEnvironment.unauthenticatedContext().firestore();
  const memberDb = testEnvironment.authenticatedContext('member').firestore();
  const ownerDb = testEnvironment.authenticatedContext('organizer').firestore();
  const adminDb = testEnvironment
    .authenticatedContext('catalog-admin', { admin: true })
    .firestore();
  const catalogRef = doc(adminDb, 'settings/vip_plans');
  const expiration = Timestamp.fromDate(
    new Date(Date.now() + 24 * 60 * 60 * 1000),
  );

  await assertSucceeds(getDoc(doc(anonymousDb, 'settings/vip_plans')));
  await assertFails(
    setDoc(doc(memberDb, 'settings/vip_plans'), {
      plans: {},
    }),
  );
  await assertSucceeds(
    setDoc(catalogRef, {
      plans: {
        community_plus: {
          active: true,
          appPlan: 'organizer_vip',
          limits: { maxOpenEvents: 8 },
        },
        platinum: {
          active: true,
          appPlan: 'organizer_vip',
          limits: {
            maxAthletesPerGroup: 41,
            maxCoOrganizersPerGroup: 4,
          },
        },
      },
    }),
  );
  await assertFails(
    updateDoc(doc(adminDb, 'users/organizer'), {
      vipPlan: 'community_plus',
      vipExpiresAt: expiration,
      updatedAt: expiration,
    }),
  );
  await assertSucceeds(
    updateDoc(doc(adminDb, 'users/organizer'), {
      vipPlan: 'Platinum',
      vipExpiresAt: expiration,
      updatedAt: expiration,
    }),
  );

  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'groups/configured-platinum-team'), {
      owner_id: 'organizer',
      athlete_count: 40,
      co_organizer_count: 0,
    });
    for (const uid of ['configured-capacity-athlete', 'configured-capacity-overflow']) {
      await setDoc(doc(db, `users/${uid}`), { group_ids: [] });
    }
  });

  const capacityBatch = writeBatch(ownerDb);
  capacityBatch.update(doc(ownerDb, 'groups/configured-platinum-team'), {
    athlete_count: 41,
    capacity_member_uid: 'configured-capacity-athlete',
    capacity_member_role: 'member',
    capacity_member_delta: 1,
    capacity_member_nonce: 'configured-platinum-capacity',
  });
  capacityBatch.set(
    doc(ownerDb, 'groups/configured-platinum-team/members/configured-capacity-athlete'),
    { uid: 'configured-capacity-athlete', role: 'member' },
  );
  capacityBatch.update(doc(ownerDb, 'users/configured-capacity-athlete'), {
    group_ids: ['configured-platinum-team'],
    membership_change_group_id: 'configured-platinum-team',
    membership_change_nonce: 'configured-platinum-capacity',
  });
  await assertSucceeds(capacityBatch.commit());

  const overflowBatch = writeBatch(ownerDb);
  overflowBatch.update(doc(ownerDb, 'groups/configured-platinum-team'), {
    athlete_count: 42,
    capacity_member_uid: 'configured-capacity-overflow',
    capacity_member_role: 'member',
    capacity_member_delta: 1,
    capacity_member_nonce: 'configured-platinum-overflow',
  });
  overflowBatch.set(
    doc(ownerDb, 'groups/configured-platinum-team/members/configured-capacity-overflow'),
    { uid: 'configured-capacity-overflow', role: 'member' },
  );
  overflowBatch.update(doc(ownerDb, 'users/configured-capacity-overflow'), {
    group_ids: ['configured-platinum-team'],
    membership_change_group_id: 'configured-platinum-team',
    membership_change_nonce: 'configured-platinum-overflow',
  });
  await assertFails(overflowBatch.commit());
});
