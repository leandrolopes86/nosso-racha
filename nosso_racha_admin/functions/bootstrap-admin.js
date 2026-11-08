const { applicationDefault, initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

const uid = process.env.ADMIN_UID;
const projectId = process.env.GCLOUD_PROJECT;
if (!uid) {
  throw new Error("Defina ADMIN_UID com o UID da conta inicial de administrador.");
}
if (!projectId) {
  throw new Error("Defina GCLOUD_PROJECT com o ID do projeto Firebase.");
}

initializeApp({ credential: applicationDefault(), projectId });

async function bootstrapAdmin() {
  const auth = getAuth();
  const db = getFirestore();
  const user = await auth.getUser(uid);

  if (user.disabled || !user.emailVerified) {
    throw new Error("A conta deve estar ativa e ter o e-mail verificado.");
  }

  await auth.setCustomUserClaims(uid, {
    ...(user.customClaims || {}),
    admin: true,
  });
  await db.collection("adminAccess").doc(uid).set({
    email: user.email || "",
    grantedBy: uid,
    registeredAt: FieldValue.serverTimestamp(),
  });

  console.log(`Acesso administrativo inicial configurado para ${user.email || uid}.`);
}

bootstrapAdmin().catch((error) => {
  console.error("Falha ao configurar o administrador inicial:", error);
  process.exitCode = 1;
});
