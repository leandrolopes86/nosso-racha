const fs = require("node:fs");
const path = require("node:path");
const { cert, initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");

const credentialPath = process.env.GOOGLE_APPLICATION_CREDENTIALS;
if (!credentialPath) {
  throw new Error(
    "Defina GOOGLE_APPLICATION_CREDENTIALS com o caminho de serviceAccountKey.json.",
  );
}
if (!fs.existsSync(credentialPath)) {
  throw new Error(`Arquivo de credenciais não encontrado: ${credentialPath}`);
}

initializeApp({
  credential: cert(require(path.resolve(credentialPath))),
});

async function seedTestUsers() {
  const auth = getAuth();

  for (let number = 1; number <= 30; number += 1) {
    const email = `usuario${number}@nossoracha.com.br`;

    try {
      await auth.createUser({
        email,
        password: "123456",
        displayName: `Usuario ${number}`,
      });
      console.log(`Usuário criado: ${email}`);
    } catch (error) {
      if (error.code === "auth/email-already-exists") {
        console.log(`Usuário já existe: ${email}`);
        continue;
      }
      throw error;
    }
  }
}

seedTestUsers().catch((error) => {
  console.error("Falha ao criar usuários de teste:", error);
  process.exitCode = 1;
});
