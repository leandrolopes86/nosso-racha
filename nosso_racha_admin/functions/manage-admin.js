const { applicationDefault, initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { FieldValue, getFirestore } = require("firebase-admin/firestore");

const projectId = process.env.GCLOUD_PROJECT;
const action = process.env.ADMIN_ACTION;
const email = process.env.ADMIN_EMAIL?.trim().toLowerCase();
const actorUid = process.env.ADMIN_ACTOR_UID;

if (!projectId) throw new Error("Defina GCLOUD_PROJECT com o ID do projeto Firebase.");
if (!["list", "grant", "revoke"].includes(action)) {
  throw new Error("Defina ADMIN_ACTION como list, grant ou revoke.");
}
if (["grant", "revoke"].includes(action) && !email) {
  throw new Error("Defina ADMIN_EMAIL com o e-mail da conta.");
}
if (action === "revoke" && !actorUid) {
  throw new Error("Defina ADMIN_ACTOR_UID com o UID do administrador que está executando a revogação.");
}

initializeApp({ credential: applicationDefault(), projectId });

async function getAccountByEmail(auth, accountEmail) {
  try {
    return await auth.getUserByEmail(accountEmail);
  } catch (error) {
    if (error.code === "auth/user-not-found") {
      throw new Error(`Não existe uma conta com o e-mail ${accountEmail} no Firebase Authentication.`);
    }
    throw error;
  }
}

async function listActiveAdmins(auth, db) {
  const snapshot = await db.collection("adminAccess").get();
  const users = await Promise.all(
    snapshot.docs.map(async (document) => {
      try {
        const user = await auth.getUser(document.id);
        if (user.customClaims?.admin !== true) return null;
        return { uid: user.uid, email: user.email || "" };
      } catch (error) {
        if (error.code === "auth/user-not-found") return null;
        throw error;
      }
    }),
  );
  return users.filter(Boolean);
}

async function main() {
  const auth = getAuth();
  const db = getFirestore();

  if (action === "list") {
    const admins = await listActiveAdmins(auth, db);
    if (!admins.length) {
      console.log("Nenhum administrador ativo foi encontrado na coleção adminAccess.");
      return;
    }
    for (const admin of admins) {
      console.log(`${admin.email || "(sem e-mail)"}\t${admin.uid}`);
    }
    return;
  }

  const user = await getAccountByEmail(auth, email);
  if (user.disabled) throw new Error("A conta está desativada no Firebase Authentication.");

  const claims = { ...(user.customClaims || {}) };
  const adminRef = db.collection("adminAccess").doc(user.uid);

  if (action === "grant") {
    if (!user.emailVerified) throw new Error("O e-mail da conta precisa estar verificado.");
    claims.admin = true;
    await auth.setCustomUserClaims(user.uid, claims);
    await adminRef.set({
      email: user.email || "",
      grantedBy: actorUid || "local-admin-sdk",
      registeredAt: FieldValue.serverTimestamp(),
    });
    console.log(`Acesso administrativo concedido a ${user.email || user.uid}. Peça para a pessoa renovar o token.`);
    return;
  }

  if (user.uid === actorUid) {
    throw new Error("A revogação do próprio acesso foi bloqueada.");
  }

  const activeAdmins = await listActiveAdmins(auth, db);
  if (user.customClaims?.admin === true && activeAdmins.length <= 1) {
    throw new Error("Não é permitido remover o último administrador registrado.");
  }

  delete claims.admin;
  await auth.setCustomUserClaims(user.uid, claims);
  await auth.revokeRefreshTokens(user.uid);
  await adminRef.delete();
  console.log(`Acesso administrativo removido de ${user.email || user.uid}.`);
}

main().catch((error) => {
  console.error("Falha ao gerenciar administradores:", error);
  process.exitCode = 1;
});
