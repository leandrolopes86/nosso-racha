import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { FieldPath, getFirestore } from 'firebase-admin/firestore';
import { pathToFileURL } from 'node:url';

const PAGE_SIZE = 300;
const BATCH_SIZE = 400;
const VALID_MEMBER_ROLES = new Set(['owner', 'member', 'co_organizer']);
const VALID_EVENT_VISIBILITIES = new Set(['public', 'moderated', 'private']);

async function* getDocumentPages(firestore, collectionName) {
  let lastDocument;

  while (true) {
    let query = firestore
      .collection(collectionName)
      .orderBy(FieldPath.documentId())
      .limit(PAGE_SIZE);
    if (lastDocument) query = query.startAfter(lastDocument);

    const page = await query.get();
    if (page.empty) return;

    yield page.docs;
    lastDocument = page.docs[page.docs.length - 1];
    if (page.size < PAGE_SIZE) return;
  }
}

export async function migrateFirestore(firestore, { apply = false } = {}) {
  const report = {
    mode: apply ? 'apply' : 'dry-run',
    eventsScanned: 0,
    transactionsScanned: 0,
    transactionsLinkedToGroups: 0,
    openEventsCounted: 0,
    eventVisibilitiesSetToPublic: 0,
    invalidEventVisibilitiesSkipped: 0,
    malformedEventsSkipped: 0,
    groupsScanned: 0,
    groupsWithCountersInitialized: 0,
    athleteCountInitialized: 0,
    coOrganizerCountInitialized: 0,
    orphanOpenEventGroupReferences: 0,
    orphanOpenEventDetails: [],
    unlinkedOpenEvents: 0,
    unlinkedOpenEventIds: [],
    invalidMembershipRoles: 0,
    invalidMembershipDetails: [],
    usersScanned: 0,
    membershipsCreated: 0,
    membershipsRepaired: 0,
    membershipsAlreadyValid: 0,
    orphanGroupReferences: 0,
    orphanGroupReferenceDetails: [],
    malformedEventDetails: [],
    invalidEventVisibilityDetails: [],
  };
  const groups = new Map();
  const membershipRoles = new Map();
  const processedMemberships = new Set();
  const openEventsByGroup = new Map();
  const eventGroupIds = new Map();
  let batch = firestore.batch();
  let queuedWrites = 0;

  const flushBatch = async () => {
    if (!apply || queuedWrites === 0) return;
    await batch.commit();
    batch = firestore.batch();
    queuedWrites = 0;
  };

  const queueSet = async (reference, data) => {
    if (!apply) return;
    batch.set(reference, data, { merge: true });
    queuedWrites += 1;
    if (queuedWrites >= BATCH_SIZE) await flushBatch();
  };

  for await (const docs of getDocumentPages(firestore, 'groups')) {
    for (const group of docs) {
      report.groupsScanned += 1;
      const data = group.data();
      groups.set(group.id, {
        ownerId: data.owner_id ?? data.ownerId ?? null,
        reference: group.ref,
      });
    }
  }

  for await (const docs of getDocumentPages(firestore, 'users')) {
    for (const user of docs) {
      report.usersScanned += 1;
      const data = user.data();
      const groupIds = new Set([
        ...(Array.isArray(data.group_ids)
          ? data.group_ids.filter((id) => typeof id === 'string' && id.length > 0)
          : []),
        ...(typeof data.group_id === 'string' && data.group_id.length > 0
          ? [data.group_id]
          : []),
      ]);

      for (const groupId of groupIds) {
        if (!groups.has(groupId)) {
          report.orphanGroupReferences += 1;
          report.orphanGroupReferenceDetails.push({
            userId: user.id,
            groupId,
          });
          continue;
        }

        const membership = firestore
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .doc(user.id);
        processedMemberships.add(membership.path);
        const existing = await membership.get();
        const existingData = existing.data();
        const isOwner = groups.get(groupId).ownerId === user.id;
        const role = isOwner
          ? 'owner'
          : VALID_MEMBER_ROLES.has(existingData?.role)
            ? existingData.role
            : 'member';
        membershipRoles.set(membership.path, role);
        const needsRepair =
          !existing.exists ||
          existingData.uid !== user.id ||
          existingData.role !== role;

        if (!existing.exists) {
          report.membershipsCreated += 1;
        } else if (needsRepair) {
          report.membershipsRepaired += 1;
        } else {
          report.membershipsAlreadyValid += 1;
        }

        if (needsRepair) {
          await queueSet(membership, { uid: user.id, role });
        }
      }
    }
    await flushBatch();
  }

  for (const [groupId, group] of groups) {
    const ownerId = group.ownerId;
    if (typeof ownerId !== 'string' || ownerId.length === 0) continue;

    const membership = firestore
      .collection('groups')
      .doc(groupId)
      .collection('members')
      .doc(ownerId);
    if (processedMemberships.has(membership.path)) continue;
    const existing = await membership.get();
    const existingData = existing.data();
    membershipRoles.set(membership.path, 'owner');
    const needsRepair =
      !existing.exists ||
      existingData.uid !== ownerId ||
      existingData.role !== 'owner';

    if (!existing.exists) {
      report.membershipsCreated += 1;
    } else if (needsRepair) {
      report.membershipsRepaired += 1;
    } else {
      report.membershipsAlreadyValid += 1;
    }

    if (needsRepair) {
      await queueSet(membership, { uid: ownerId, role: 'owner' });
    }
  }
  await flushBatch();

  for (const [groupId, group] of groups) {
    const members = await group.reference.collection('members').get();
    for (const member of members.docs) {
      const role = member.data().role;
      if (
        VALID_MEMBER_ROLES.has(role) &&
        !membershipRoles.has(member.ref.path)
      ) {
        membershipRoles.set(member.ref.path, role);
      } else if (
        !VALID_MEMBER_ROLES.has(role) &&
        !membershipRoles.has(member.ref.path)
      ) {
        report.invalidMembershipRoles += 1;
        report.invalidMembershipDetails.push({
          groupId,
          memberId: member.id,
          role: role ?? null,
        });
      }
    }
    openEventsByGroup.set(groupId, 0);
  }

  const memberCountsByGroup = new Map(
    [...groups.keys()].map((groupId) => [
      groupId,
      { athleteCount: 0, coOrganizerCount: 0 },
    ]),
  );
  for (const [path, role] of membershipRoles) {
    const groupId = path.split('/')[1];
    const counts = memberCountsByGroup.get(groupId);
    if (!counts) continue;
    if (role === 'member') counts.athleteCount += 1;
    if (role === 'co_organizer') counts.coOrganizerCount += 1;
  }
  for (const counts of memberCountsByGroup.values()) {
    report.athleteCountInitialized += counts.athleteCount;
    report.coOrganizerCountInitialized += counts.coOrganizerCount;
  }

  for await (const docs of getDocumentPages(firestore, 'events')) {
    for (const event of docs) {
      report.eventsScanned += 1;
      const eventData = event.data();
      const info = eventData.info;
      const eventInfo =
        info != null && typeof info === 'object' && !Array.isArray(info)
          ? info
          : {};
      const groupId = eventInfo.group_id ?? eventData.group_id ?? null;
      if (typeof groupId === 'string' && groups.has(groupId)) {
        eventGroupIds.set(event.id, groupId);
      }

      if (info == null || typeof info !== 'object' || Array.isArray(info)) {
        report.malformedEventsSkipped += 1;
        report.malformedEventDetails.push(event.id);
        continue;
      }

      const status = info.status;
      if (['scheduled', 'published', 'in_progress'].includes(status)) {
        if (typeof groupId !== 'string' || groupId.length === 0) {
          report.unlinkedOpenEvents += 1;
          report.unlinkedOpenEventIds.push(event.id);
        } else if (!groups.has(groupId)) {
          report.orphanOpenEventGroupReferences += 1;
          report.orphanOpenEventDetails.push({
            eventId: event.id,
            groupId,
          });
        } else {
          openEventsByGroup.set(
            groupId,
            (openEventsByGroup.get(groupId) ?? 0) + 1,
          );
          report.openEventsCounted += 1;
        }
      }

      if (info.visibility != null) {
        if (!VALID_EVENT_VISIBILITIES.has(info.visibility)) {
          report.invalidEventVisibilitiesSkipped += 1;
          report.invalidEventVisibilityDetails.push(event.id);
        }
        continue;
      }

      report.eventVisibilitiesSetToPublic += 1;
      if (apply) {
        await queueSet(event.ref, { info: { visibility: 'public' } });
      }
    }
    await flushBatch();
  }

  for await (const docs of getDocumentPages(firestore, 'transactions')) {
    for (const transaction of docs) {
      report.transactionsScanned += 1;
      const data = transaction.data();
      if (typeof data.group_id === 'string' && data.group_id.length > 0) {
        continue;
      }
      const eventId = data.related_event_id;
      const groupId =
        typeof eventId === 'string' ? eventGroupIds.get(eventId) : null;
      if (!groupId) continue;

      report.transactionsLinkedToGroups += 1;
      await queueSet(transaction.ref, { group_id: groupId });
    }
    await flushBatch();
  }

  for (const [groupId, group] of groups) {
    const counts = memberCountsByGroup.get(groupId) ?? {
      athleteCount: 0,
      coOrganizerCount: 0,
    };
    const openEventsCount = openEventsByGroup.get(groupId) ?? 0;
    await queueSet(group.reference, {
      athlete_count: counts.athleteCount,
      co_organizer_count: counts.coOrganizerCount,
      open_events_count: openEventsCount,
    });
    report.groupsWithCountersInitialized += 1;
  }

  await flushBatch();
  return report;
}

async function main() {
  const apply = process.argv.includes('--apply');
  const projectArgumentIndex = process.argv.indexOf('--project');
  const projectId =
    (projectArgumentIndex >= 0
      ? process.argv[projectArgumentIndex + 1]
      : undefined) ??
    process.env.GCLOUD_PROJECT ??
    process.env.FIREBASE_PROJECT_ID ??
    'nosso-racha';
  const options = { projectId };
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    options.credential = applicationDefault();
  }
  const app = initializeApp({
    ...options,
  });

  try {
    const report = await migrateFirestore(getFirestore(app), { apply });
    console.log(JSON.stringify(report, null, 2));
    if (
      report.malformedEventsSkipped > 0 ||
      report.orphanGroupReferences > 0 ||
      report.orphanOpenEventGroupReferences > 0 ||
      report.unlinkedOpenEvents > 0 ||
      report.invalidMembershipRoles > 0 ||
      report.invalidEventVisibilitiesSkipped > 0
    ) {
      console.error(
        'Há documentos ignorados que precisam de revisão manual antes de considerar a migração completa.',
      );
      process.exitCode = 2;
    }
  } finally {
    await app.delete();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error('A migração do Firestore falhou:', error);
    process.exitCode = 1;
  });
}
