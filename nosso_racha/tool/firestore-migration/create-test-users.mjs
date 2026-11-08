import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { applicationDefault, cert, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

const USER_COUNT = 30;
const DEFAULT_PASSWORD = '123456';
const REPOSITORY_ROOT = resolve(
  fileURLToPath(new URL('../..', import.meta.url)),
);

export async function createTestUsers(
  auth,
  { count = USER_COUNT, password = DEFAULT_PASSWORD, logger = console } = {},
) {
  if (!Number.isInteger(count) || count < 1) {
    throw new RangeError('A quantidade de usuários deve ser um inteiro positivo.');
  }
  if (typeof password !== 'string' || password.length < 6) {
    throw new RangeError('A senha deve ter pelo menos 6 caracteres.');
  }

  const result = { created: 0, alreadyExisted: 0, errors: 0 };

  for (let number = 1; number <= count; number += 1) {
    const email = `usuario${number}@nossoracha.com.br`;
    try {
      await auth.createUser({
        email,
        password,
        displayName: `Usuario ${number}`,
      });
      result.created += 1;
      logger.log(`Usuário criado: ${email}`);
    } catch (error) {
      if (error.code === 'auth/email-already-exists') {
        result.alreadyExisted += 1;
        logger.log(`Usuário já existe: ${email}`);
        continue;
      }

      result.errors += 1;
      logger.error(`Falha ao criar ${email}: ${error.message}`);
    }
  }

  logger.log(
    `Concluído: ${result.created} criado(s), ` +
      `${result.alreadyExisted} já existente(s), ${result.errors} erro(s).`,
  );
  return result;
}

async function main() {
  const credentialPath =
    process.env.GOOGLE_APPLICATION_CREDENTIALS ??
    resolve(REPOSITORY_ROOT, 'serviceAccountKey.json');

  let credential;
  try {
    credential = JSON.parse(await readFile(credentialPath, 'utf8'));
  } catch (error) {
    throw new Error(
      `Não foi possível ler as credenciais em "${credentialPath}": ${error.message}`,
      { cause: error },
    );
  }

  const app = initializeApp({
    credential: credential.client_email
      ? cert(credential)
      : applicationDefault(),
    projectId: credential.project_id,
  });
  const result = await createTestUsers(getAuth(app));
  if (result.errors > 0) process.exitCode = 1;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    console.error(error.message);
    process.exitCode = 1;
  });
}
