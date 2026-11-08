import assert from 'node:assert/strict';
import test from 'node:test';
import { createTestUsers } from './create-test-users.mjs';

function createLogger() {
  return {
    messages: [],
    log(message) {
      this.messages.push(message);
    },
    error(message) {
      this.messages.push(message);
    },
  };
}

test('creates 30 named users sequentially with the expected email and password', async () => {
  const users = [];
  let activeRequests = 0;
  let maxActiveRequests = 0;
  const auth = {
    async createUser(user) {
      activeRequests += 1;
      maxActiveRequests = Math.max(maxActiveRequests, activeRequests);
      await Promise.resolve();
      activeRequests -= 1;
      users.push(user);
      return { uid: `generated-uid-${users.length}`, ...user };
    },
  };
  const logger = createLogger();

  const result = await createTestUsers(auth, { logger });

  assert.deepEqual(result, { created: 30, alreadyExisted: 0, errors: 0 });
  assert.equal(users.length, 30);
  assert.equal(maxActiveRequests, 1);
  assert.deepEqual(users[0], {
    email: 'usuario1@nossoracha.com.br',
    password: '123456',
    displayName: 'Usuario 1',
  });
  assert.equal(users[29].email, 'usuario30@nossoracha.com.br');
  assert.equal(users[29].displayName, 'Usuario 30');
  assert.equal(logger.messages[0], 'Usuário criado: usuario1@nossoracha.com.br');
});

test('skips existing emails and continues after other creation errors', async () => {
  const attemptedEmails = [];
  const logger = createLogger();
  const auth = {
    async createUser({ email }) {
      attemptedEmails.push(email);
      if (email.startsWith('usuario1@')) {
        throw { code: 'auth/email-already-exists', message: 'Already exists' };
      }
      if (email.startsWith('usuario2@')) {
        throw { code: 'auth/internal-error', message: 'Temporary failure' };
      }
      return { uid: 'generated-uid', email };
    },
  };

  const result = await createTestUsers(auth, { count: 3, logger });

  assert.deepEqual(result, { created: 1, alreadyExisted: 1, errors: 1 });
  assert.equal(attemptedEmails.length, 3);
  assert.ok(logger.messages.some((message) => message.includes('já existe')));
  assert.ok(logger.messages.some((message) => message.includes('Falha ao criar')));
});

test('validates user count and minimum password length', async () => {
  await assert.rejects(createTestUsers({}, { count: 0 }), /inteiro positivo/);
  await assert.rejects(
    createTestUsers({}, { password: '123' }),
    /pelo menos 6 caracteres/,
  );
});
