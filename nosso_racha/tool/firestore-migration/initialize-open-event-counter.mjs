import { applicationDefault, initializeApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { pathToFileURL } from 'node:url';

const OPEN_EVENT_STATUSES = new Set([
  'scheduled',
  'published',
  'in_progress',
]);

export async function initializeOpenEventCounter(
  firestore,
  { groupId, apply = false },
) {
  if (typeof groupId !== 'string' || groupId.trim().length === 0) {
    throw new TypeError('Informe um ID de organização válido.');
  }

  const groupRef = firestore.collection('groups').doc(groupId);
  const groupSnapshot = await groupRef.get();
  if (!groupSnapshot.exists) {
    throw new Error(`Organização "${groupId}" não encontrada.`);
  }

  const eventsRef = firestore.collection('events');
  const [eventsWithInfoGroup, eventsWithRootGroup] = await Promise.all([
    eventsRef.where('info.group_id', '==', groupId).get(),
    eventsRef.where('group_id', '==', groupId).get(),
  ]);
  const events = new Map();
  for (const event of [
    ...eventsWithInfoGroup.docs,
    ...eventsWithRootGroup.docs,
  ]) {
    events.set(event.id, event);
  }

  let openEventsCount = 0;
  for (const event of events.values()) {
    const data = event.data();
    const info = data.info;
    if (info == null || typeof info !== 'object' || Array.isArray(info)) {
      continue;
    }

    const eventGroupId = info.group_id ?? data.group_id ?? null;
    if (
      eventGroupId === groupId &&
      OPEN_EVENT_STATUSES.has(info.status)
    ) {
      openEventsCount += 1;
    }
  }

  const report = {
    mode: apply ? 'apply' : 'dry-run',
    groupId,
    openEventsCount,
    previousCount: groupSnapshot.get('open_events_count') ?? null,
    initialized: false,
  };
  if (!apply) return report;

  report.initialized = await firestore.runTransaction(async (transaction) => {
    const currentGroup = await transaction.get(groupRef);
    if (!currentGroup.exists) {
      throw new Error(`Organização "${groupId}" não encontrada.`);
    }

    const currentCount = currentGroup.get('open_events_count');
    if (Number.isInteger(currentCount) && currentCount >= 0) {
      report.previousCount = currentCount;
      return false;
    }

    transaction.update(groupRef, { open_events_count: openEventsCount });
    return true;
  });

  return report;
}

async function main() {
  const groupArgumentIndex = process.argv.indexOf('--group');
  const groupId =
    groupArgumentIndex >= 0
      ? process.argv[groupArgumentIndex + 1]
      : undefined;
  if (!groupId || groupId.startsWith('--')) {
    throw new Error('Uso: --group <ID> [--project <ID>] [--apply]');
  }

  const projectArgumentIndex = process.argv.indexOf('--project');
  const projectId =
    (projectArgumentIndex >= 0
      ? process.argv[projectArgumentIndex + 1]
      : undefined) ??
    process.env.GCLOUD_PROJECT ??
    process.env.FIREBASE_PROJECT_ID ??
    'nosso-racha';
  const app = initializeApp(
    {
      projectId,
      ...(process.env.FIRESTORE_EMULATOR_HOST
        ? {}
        : { credential: applicationDefault() }),
    },
    `initialize-open-event-counter-${groupId}`,
  );

  try {
    const report = await initializeOpenEventCounter(getFirestore(app), {
      groupId,
      apply: process.argv.includes('--apply'),
    });
    console.log(JSON.stringify(report, null, 2));
  } finally {
    await app.delete();
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error('A inicialização do contador falhou:', error);
    process.exitCode = 1;
  });
}
