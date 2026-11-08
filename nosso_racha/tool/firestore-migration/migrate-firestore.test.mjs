import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { initializeOpenEventCounter } from './initialize-open-event-counter.mjs';
import { migrateFirestore } from './migrate-firestore.mjs';

const app = initializeApp({ projectId: 'demo-nosso-racha' }, 'migration-test');
const firestore = getFirestore(app);

before(async () => {
  await firestore.recursiveDelete(firestore.collection('events'));
  await firestore.recursiveDelete(firestore.collection('groups'));
  await firestore.recursiveDelete(firestore.collection('users'));
  await firestore.recursiveDelete(firestore.collection('transactions'));

  await firestore.doc('groups/legacy-group').set({ owner_id: 'owner' });
  await firestore.doc('groups/other-group').set({ owner_id: 'other-owner' });
  await firestore.doc('groups/legacy-group/members/member').set({
    uid: 'incorrect-uid',
    role: 'co_organizer',
  });

  await firestore.doc('users/member').set({
    group_ids: ['legacy-group'],
    group_id: 'other-group',
  });
  await firestore.doc('users/owner').set({ group_id: 'legacy-group' });
  await firestore.doc('users/orphan').set({ group_ids: ['deleted-group'] });

  await firestore.doc('events/legacy-event').set({
    info: { title: 'Legacy event', group_id: 'legacy-group', status: 'published' },
  });
  await firestore.doc('events/finished-event').set({
    info: { title: 'Finished event', group_id: 'legacy-group', status: 'finished' },
  });
  await firestore.doc('events/private-event').set({
    info: { title: 'Private event', visibility: 'private' },
  });
  await firestore.doc('events/invalid-visibility').set({
    info: { title: 'Invalid visibility', visibility: 'hidden' },
  });
  await firestore.doc('events/malformed-event').set({ info: null });
  await firestore.doc('transactions/legacy-event-payment').set({
    related_event_id: 'legacy-event',
    amount: 25,
  });
  await firestore.doc('transactions/unlinked-manual-payment').set({
    description: 'Manual legacy transaction',
    amount: 10,
  });
});

after(async () => {
  await app.delete();
});

test('migration previews without writes, applies legacy fields, and is idempotent', async () => {
  const preview = await migrateFirestore(firestore);

  assert.equal(preview.mode, 'dry-run');
  assert.equal(preview.openEventsCounted, 1);
  assert.equal(preview.groupsWithCountersInitialized, 2);
  assert.equal(preview.athleteCountInitialized, 1);
  assert.equal(preview.coOrganizerCountInitialized, 1);
  assert.equal(preview.eventVisibilitiesSetToPublic, 2);
  assert.equal(preview.membershipsCreated, 3);
  assert.equal(preview.membershipsRepaired, 1);
  assert.equal(preview.orphanGroupReferences, 1);
  assert.equal(preview.malformedEventsSkipped, 1);
  assert.equal(preview.invalidEventVisibilitiesSkipped, 1);
  assert.equal(preview.transactionsLinkedToGroups, 1);
  assert.equal(
    (await firestore.doc('events/legacy-event').get()).data().info.visibility,
    undefined,
  );
  assert.equal(
    (await firestore.doc('groups/legacy-group').get()).data().open_events_count,
    undefined,
  );
  assert.equal(
    (await firestore.doc('transactions/legacy-event-payment').get()).data()
      .group_id,
    undefined,
  );

  const applied = await migrateFirestore(firestore, { apply: true });
  assert.equal(applied.mode, 'apply');
  assert.equal(applied.eventVisibilitiesSetToPublic, 2);

  const migratedEvent = await firestore.doc('events/legacy-event').get();
  assert.equal(migratedEvent.data().info.visibility, 'public');

  const migratedGroup = await firestore.doc('groups/legacy-group').get();
  assert.equal(migratedGroup.data().open_events_count, 1);
  assert.equal(migratedGroup.data().athlete_count, 0);
  assert.equal(migratedGroup.data().co_organizer_count, 1);
  assert.equal(
    (await firestore.doc('transactions/legacy-event-payment').get()).data()
      .group_id,
    'legacy-group',
  );
  assert.equal(
    (await firestore.doc('transactions/unlinked-manual-payment').get()).data()
      .group_id,
    undefined,
  );

  const preservedEvent = await firestore.doc('events/private-event').get();
  assert.equal(preservedEvent.data().info.visibility, 'private');
  const invalidEvent = await firestore.doc('events/invalid-visibility').get();
  assert.equal(invalidEvent.data().info.visibility, 'hidden');

  const repairedCoOrganizer = await firestore
    .doc('groups/legacy-group/members/member')
    .get();
  assert.equal(repairedCoOrganizer.data().uid, 'member');
  assert.equal(repairedCoOrganizer.data().role, 'co_organizer');

  const ownerMembership = await firestore
    .doc('groups/legacy-group/members/owner')
    .get();
  assert.deepEqual(ownerMembership.data(), { uid: 'owner', role: 'owner' });

  const rerun = await migrateFirestore(firestore);
  assert.equal(rerun.eventVisibilitiesSetToPublic, 0);
  assert.equal(rerun.membershipsCreated, 0);
  assert.equal(rerun.membershipsRepaired, 0);
  assert.equal(rerun.membershipsAlreadyValid, 4);
  assert.equal(rerun.transactionsLinkedToGroups, 0);
});

test('open-event counter initialization is scoped and idempotent', async () => {
  const groupId = 'counter-initialization-target';
  const groupRef = firestore.doc(`groups/${groupId}`);
  await groupRef.set({ owner_id: 'counter-owner' });
  await firestore.doc('events/counter-target-scheduled').set({
    info: { group_id: groupId, status: 'scheduled' },
  });
  await firestore.doc('events/counter-target-published').set({
    info: { group_id: groupId, status: 'published' },
  });
  await firestore.doc('events/counter-target-legacy').set({
    group_id: groupId,
    info: { status: 'in_progress' },
  });
  await firestore.doc('events/counter-target-finished').set({
    info: { group_id: groupId, status: 'finished' },
  });
  await firestore.doc('events/counter-other-group').set({
    info: { group_id: 'another-group', status: 'published' },
  });

  const preview = await initializeOpenEventCounter(firestore, { groupId });
  assert.equal(preview.mode, 'dry-run');
  assert.equal(preview.openEventsCount, 3);
  assert.equal(preview.initialized, false);
  assert.equal((await groupRef.get()).get('open_events_count'), undefined);

  const applied = await initializeOpenEventCounter(firestore, {
    groupId,
    apply: true,
  });
  assert.equal(applied.initialized, true);
  assert.equal((await groupRef.get()).get('open_events_count'), 3);

  const rerun = await initializeOpenEventCounter(firestore, {
    groupId,
    apply: true,
  });
  assert.equal(rerun.initialized, false);
  assert.equal((await groupRef.get()).get('open_events_count'), 3);
  assert.equal(
    (await firestore.doc('groups/legacy-group').get()).get(
      'open_events_count',
    ),
    1,
  );
});
