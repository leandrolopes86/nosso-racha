import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.5/firebase-app.js";
import {
  getAuth,
  onAuthStateChanged,
  GoogleAuthProvider,
  signInWithEmailAndPassword,
  signInWithPopup,
  signOut,
} from "https://www.gstatic.com/firebasejs/10.12.5/firebase-auth.js";
import {
  collection,
  deleteDoc,
  doc,
  getFirestore,
  onSnapshot,
  serverTimestamp,
  Timestamp,
  updateDoc,
  writeBatch,
} from "https://www.gstatic.com/firebasejs/10.12.5/firebase-firestore.js";

// Substitua pelos dados do seu app Firebase.
const firebaseConfig = {
  apiKey: "AIzaSyB5Iivkb3yeBYcEWuvSChDIR3o4PSTLqbc",
  authDomain: "nosso-racha.firebaseapp.com",
  projectId: "nosso-racha",
  appId: "1:929254524935:web:5b221c6edf2a3be40f02a2",
};

const GOOGLE_MAPS_API_KEY =
  typeof window.nossoRachaConfig?.googleMapsApiKey === "string"
    ? window.nossoRachaConfig.googleMapsApiKey
    : "";
const VIP_PLANS = ["Free", "Bronze", "Prata", "Ouro", "Platinum"];
const MANUAL_PIX_RENEWAL_DAYS = 30;
const elements = {
  loginView: document.querySelector("#loginView"),
  dashboardView: document.querySelector("#dashboardView"),
  loginForm: document.querySelector("#loginForm"),
  loginEmail: document.querySelector("#loginEmail"),
  loginPassword: document.querySelector("#loginPassword"),
  loginButton: document.querySelector("#loginButton"),
  googleLoginButton: document.querySelector("#googleLoginButton"),
  loginMessage: document.querySelector("#loginMessage"),
  dashboardMessage: document.querySelector("#dashboardMessage"),
  signOutButton: document.querySelector("#signOutButton"),
  adminIdentity: document.querySelector("#adminIdentity"),
  collectionSelect: document.querySelector("#collectionSelect"),
  collectionCaption: document.querySelector("#collectionCaption"),
  searchInput: document.querySelector("#searchInput"),
  recordsBody: document.querySelector("#recordsBody"),
  resultCount: document.querySelector("#resultCount"),
  totalCount: document.querySelector("#totalCount"),
  vipCount: document.querySelector("#vipCount"),
  connectionState: document.querySelector("#connectionState"),
  recordDetailsDialog: document.querySelector("#recordDetailsDialog"),
  recordDetailsTitle: document.querySelector("#recordDetailsTitle"),
  recordDetailsContent: document.querySelector("#recordDetailsContent"),
  closeRecordDetailsButton: document.querySelector("#closeRecordDetailsButton"),
  venueRequestsCount: document.querySelector("#venueRequestsCount"),
  venueRequestsList: document.querySelector("#venueRequestsList"),
  venuesCount: document.querySelector("#venuesCount"),
  venuesList: document.querySelector("#venuesList"),
  addVenueButton: document.querySelector("#addVenueButton"),
  venueApprovalDialog: document.querySelector("#venueApprovalDialog"),
  venueApprovalForm: document.querySelector("#venueApprovalForm"),
  venueApprovalTitle: document.querySelector("#venueApprovalTitle"),
  approvalVenueName: document.querySelector("#approvalVenueName"),
  approvalPlaceSearch: document.querySelector("#approvalPlaceSearch"),
  venuePlaceSearchStatus: document.querySelector("#venuePlaceSearchStatus"),
  approvalVenueAddress: document.querySelector("#approvalVenueAddress"),
  approvalVenueCep: document.querySelector("#approvalVenueCep"),
  lookupVenueCepButton: document.querySelector("#lookupVenueCepButton"),
  approvalLatitude: document.querySelector("#approvalLatitude"),
  approvalLongitude: document.querySelector("#approvalLongitude"),
  venueApprovalMessage: document.querySelector("#venueApprovalMessage"),
  approveVenueButton: document.querySelector("#approveVenueButton"),
  closeVenueApprovalButton: document.querySelector("#closeVenueApprovalButton"),
  cancelVenueApprovalButton: document.querySelector("#cancelVenueApprovalButton"),
};

const firebaseIsConfigured =
  Object.values(firebaseConfig).every(
    (value) =>
      typeof value === "string" &&
      value.trim().length > 0 &&
      !value.includes("SUA_") &&
      !value.includes("SEU_"),
  );
let auth;
let db;
let unsubscribeRecords;
let records = [];
let currentCollection = "users";
let recordsLoadError = false;
let ownerProfilesById = new Map();
let unsubscribeOwnerProfiles;
let unsubscribePendingVenues;
let unsubscribeVenues;
let targetRecordId;
let pendingVenueRequests = [];
let venues = [];
let activeVenueRequestId;
let editingVenueId;
let manualVenueRef;
let googleMapsLoadPromise;
let venuePlaceSearchVersion = 0;
let googleMapsLoadTimeout;

function showMessage(element, message, kind = "error") {
  element.textContent = message;
  element.classList.remove("hidden", "is-success", "is-info");
  if (kind === "success") element.classList.add("is-success");
  if (kind === "info") element.classList.add("is-info");
}

function hideMessage(element) {
  element.textContent = "";
  element.classList.add("hidden");
  element.classList.remove("is-success", "is-info");
}

function getLoginErrorMessage(error) {
  const messages = {
    "auth/invalid-credential":
      "E-mail ou senha incorretos. Confira os dados e tente novamente.",
    "auth/invalid-login-credentials":
      "E-mail ou senha incorretos. Confira os dados e tente novamente.",
    "auth/user-not-found":
      "E-mail ou senha incorretos. Confira os dados e tente novamente.",
    "auth/wrong-password":
      "E-mail ou senha incorretos. Confira os dados e tente novamente.",
    "auth/invalid-email":
      "Informe um endereço de e-mail válido.",
    "auth/operation-not-allowed":
      "O login por e-mail e senha não está habilitado. Ative esse provedor em Firebase Console → Authentication → Sign-in method.",
    "auth/unauthorized-domain":
      "Este domínio não está autorizado. Adicione o domínio atual em Firebase Console → Authentication → Settings → Authorized domains.",
    "auth/invalid-api-key":
      "A API key do Firebase é inválida. Confira firebaseConfig em app.js.",
    "auth/api-key-not-valid":
      "A API key do Firebase não foi aceita. Confira firebaseConfig e as restrições da chave no Google Cloud Console.",
    "auth/too-many-requests":
      "Foram feitas muitas tentativas. Aguarde alguns minutos e tente novamente.",
    "auth/network-request-failed":
      "Falha de conexão com o Firebase. Verifique a internet e tente novamente.",
    "auth/popup-closed-by-user":
      "A janela de login do Google foi fechada antes de concluir a autenticação.",
    "auth/popup-blocked":
      "O navegador bloqueou a janela de login. Permita pop-ups para este site e tente novamente.",
    "auth/cancelled-popup-request":
      "Já existe uma solicitação de login em andamento. Aguarde e tente novamente.",
  };

  return Object.hasOwn(messages, error?.code)
    ? messages[error.code]
    : "Não foi possível entrar. Confira o e-mail e a senha e verifique a configuração do Firebase Authentication.";
}

function setView(isAuthenticated) {
  elements.loginView.classList.toggle("hidden", isAuthenticated);
  elements.dashboardView.classList.toggle("hidden", !isAuthenticated);
}

function getDisplayName(data, id) {
  const name =
    data.personal_info?.full_name ??
    data.name ??
    data.displayName ??
    data.groupName ??
    data.title;
  return typeof name === "string" && name.trim() ? name.trim() : `Sem nome (${id})`;
}

function getGroupDisplayName(data, id) {
  const name = data.groupName ?? data.name ?? data.title ?? data.displayName;
  return typeof name === "string" && name.trim() ? name.trim() : `Grupo (${id})`;
}

function getOrganizerId(groupData) {
  const ownerId = groupData.owner_id ?? groupData.organizer_id ?? groupData.organizer_uid;
  return typeof ownerId === "string" && ownerId.trim() ? ownerId : "";
}

function getDisplayEmail(data) {
  const email = data.email ?? data.ownerEmail ?? data.contactEmail;
  return typeof email === "string" && email.trim() ? email.trim() : "—";
}

function getSearchableText(record) {
  const isGroup = currentCollection === "groups";
  const name = isGroup
    ? getGroupDisplayName(record.data, record.id)
    : getDisplayName(record.data, record.id);
  const organizerId = isGroup ? getOrganizerId(record.data) : "";
  const organizer = ownerProfilesById.get(organizerId)?.data;
  const ownerSearch = organizer
    ? `${getDisplayName(organizer, organizerId)} ${getDisplayEmail(organizer)} ${organizerId}`
    : organizerId;
  return `${name} ${getDisplayEmail(record.data)} ${record.id} ${ownerSearch}`
    .toLocaleLowerCase("pt-BR");
}

function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;
  if (typeof value?.toDate === "function") return value.toDate();
  if (typeof value === "string" || typeof value === "number") {
    const date = new Date(value);
    return Number.isNaN(date.getTime()) ? null : date;
  }
  return null;
}

function formatDate(value) {
  const date = toDate(value);
  return date
    ? new Intl.DateTimeFormat("pt-BR", { dateStyle: "medium" }).format(date)
    : "Sem vencimento";
}

function dateToInputValue(value) {
  const date = toDate(value);
  if (!date) return "";
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function formatDetailValue(value) {
  if (value === null) return "Nulo";
  if (value === undefined) return "—";
  if (typeof value === "boolean") return value ? "Sim" : "Não";
  if (typeof value === "string") return value.trim() ? value : "Vazio";
  if (typeof value === "number") return String(value);
  if (value instanceof Date) return formatDate(value);
  if (typeof value?.toDate === "function") return formatDate(value);
  return String(value);
}

function createDetailNode(value) {
  if (Array.isArray(value)) {
    if (value.length === 0) {
      const empty = document.createElement("p");
      empty.className = "detail-empty";
      empty.textContent = "Lista vazia";
      return empty;
    }

    const list = document.createElement("ul");
    list.className = "detail-list";
    for (const item of value) {
      const entry = document.createElement("li");
      entry.append(createDetailNode(item));
      list.append(entry);
    }
    return list;
  }

  if (value && typeof value === "object" && !(value instanceof Date) && typeof value.toDate !== "function") {
    const entries = Object.entries(value);
    if (entries.length === 0) {
      const empty = document.createElement("p");
      empty.className = "detail-empty";
      empty.textContent = "Sem dados";
      return empty;
    }

    const list = document.createElement("dl");
    list.className = "detail-grid";
    for (const [key, nestedValue] of entries) {
      const item = document.createElement("div");
      item.className = "detail-item";

      const term = document.createElement("dt");
      term.textContent = key.replaceAll("_", " ");
      const description = document.createElement("dd");
      description.append(createDetailNode(nestedValue));
      item.append(term, description);
      list.append(item);
    }
    return list;
  }

  const text = document.createElement("span");
  text.textContent = formatDetailValue(value);
  return text;
}

function openRecordDetails(record) {
  elements.recordDetailsTitle.textContent = getDisplayName(record.data, record.id);
  elements.recordDetailsContent.replaceChildren();

  const documentId = document.createElement("p");
  documentId.className = "detail-document-id";
  documentId.textContent = `ID do documento: ${record.id}`;
  elements.recordDetailsContent.append(documentId, createDetailNode(record.data));
  elements.recordDetailsDialog.showModal();
}

function getVipData(record) {
  if (currentCollection !== "groups") return record.data;
  const organizerId = getOrganizerId(record.data);
  return ownerProfilesById.get(organizerId)?.data ?? {};
}

function openOrganizerProfile(organizerId) {
  if (!organizerId) {
    showMessage(elements.dashboardMessage, "Este grupo não possui um UID de organizador.");
    return;
  }

  const ownerProfile = ownerProfilesById.get(organizerId);
  if (!ownerProfile) {
    showMessage(
      elements.dashboardMessage,
      `Não foi encontrado um perfil em users/${organizerId}. Confira o campo owner_id do grupo.`,
    );
    return;
  }

  targetRecordId = organizerId;
  elements.collectionSelect.value = "users";
  elements.searchInput.value = organizerId;
  listenToCollection("users");
}

function createPlanSelect(currentPlan) {
  const select = document.createElement("select");
  select.className = "row-editor";
  select.setAttribute("aria-label", "Plano VIP");

  for (const plan of VIP_PLANS) {
    const option = document.createElement("option");
    option.value = plan;
    option.textContent = plan;
    select.append(option);
  }

  select.value = VIP_PLANS.includes(currentPlan) ? currentPlan : "Free";
  return select;
}

function createRecordRow(record) {
  const row = document.createElement("tr");
  row.dataset.recordId = record.id;
  const isGroup = currentCollection === "groups";
  const organizerId = isGroup ? getOrganizerId(record.data) : "";
  const organizerProfile = organizerId ? ownerProfilesById.get(organizerId) : undefined;
  const vipData = getVipData(record);
  const nameCell = document.createElement("td");
  nameCell.dataset.label = isGroup ? "Grupo" : "Usuário";
  const name = document.createElement("button");
  name.className = "person-name";
  name.type = "button";
  name.textContent = isGroup
    ? getGroupDisplayName(record.data, record.id)
    : getDisplayName(record.data, record.id);
  name.title = name.textContent;
  name.setAttribute("aria-label", `Ver dados completos de ${name.textContent}`);
  name.addEventListener("click", () => openRecordDetails(record));
  nameCell.append(name);

  const emailCell = document.createElement("td");
  emailCell.dataset.label = isGroup ? "Organizador" : "E-mail";
  if (isGroup) {
    const organizerButton = document.createElement("button");
    organizerButton.type = "button";
    organizerButton.className = "organizer-link";
    organizerButton.textContent = organizerProfile
      ? `${getDisplayName(organizerProfile.data, organizerId)} · ${getDisplayEmail(organizerProfile.data)}`
      : organizerId
        ? `Perfil do organizador · ${organizerId}`
        : "Organizador não informado";
    organizerButton.disabled = !organizerProfile;
    organizerButton.title = organizerProfile
      ? "Abrir perfil do usuário e gerenciar a renovação"
      : "Perfil não encontrado na coleção users";
    organizerButton.addEventListener("click", () => openOrganizerProfile(organizerId));
    emailCell.append(organizerButton);
  } else {
    const email = document.createElement("div");
    email.className = "person-email";
    email.textContent = getDisplayEmail(record.data);
    email.title = email.textContent;
    emailCell.append(email);
  }

  const planCell = document.createElement("td");
  planCell.dataset.label = isGroup ? "Plano do organizador" : "Plano VIP";
  const badge = document.createElement("span");
  const plan = VIP_PLANS.includes(vipData.vipPlan) ? vipData.vipPlan : "Free";
  badge.className = `plan-badge${plan === "Free" ? "" : " is-vip"}`;
  badge.textContent = plan;
  if (isGroup) badge.title = "Plano do organizador";
  planCell.append(badge);

  const expiryCell = document.createElement("td");
  expiryCell.dataset.label = isGroup
    ? "Vencimento do organizador"
    : "Vencimento";
  const dateDisplay = document.createElement("span");
  dateDisplay.textContent = formatDate(vipData.vipExpiresAt);
  if (isGroup) dateDisplay.title = "Vencimento do plano do organizador";
  expiryCell.append(dateDisplay);

  const actionCell = document.createElement("td");
  actionCell.dataset.label = "Ações";
  const actionWrap = document.createElement("div");
  actionWrap.className = "action-cell";

  if (isGroup) {
    const organizerButton = document.createElement("button");
    organizerButton.type = "button";
    organizerButton.className = "button button-outline button-small";
    organizerButton.textContent = "Ver / renovar usuário";
    organizerButton.disabled = !organizerProfile;
    organizerButton.addEventListener("click", () => openOrganizerProfile(organizerId));
    actionWrap.append(organizerButton);
    actionCell.append(actionWrap);
    row.append(nameCell, emailCell, planCell, expiryCell, actionCell);
    return row;
  }

  const planSelect = createPlanSelect(plan);
  const expiryInput = document.createElement("input");
  expiryInput.className = "row-editor row-date";
  expiryInput.type = "date";
  expiryInput.setAttribute("aria-label", "Data de vencimento");
  expiryInput.value = dateToInputValue(record.data.vipExpiresAt);
  expiryInput.disabled = planSelect.value === "Free";

  planSelect.addEventListener("change", () => {
    expiryInput.disabled = planSelect.value === "Free";
    if (planSelect.value === "Free") expiryInput.value = "";
  });

  const saveButton = document.createElement("button");
  saveButton.type = "button";
  saveButton.className = "button button-primary button-small";
  saveButton.textContent = "Salvar";
  saveButton.addEventListener("click", () =>
    savePlan(record.id, planSelect, expiryInput, saveButton),
  );

  const pixButton = document.createElement("button");
  pixButton.type = "button";
  pixButton.className = "button button-outline button-small";
  pixButton.textContent = "Aprovar Pix";
  pixButton.title = `Simula aprovação e renova por ${MANUAL_PIX_RENEWAL_DAYS} dias`;
  pixButton.addEventListener("click", () =>
    approveManualPix(record.id, planSelect, expiryInput, pixButton),
  );

  actionWrap.append(planSelect, expiryInput, saveButton, pixButton);
  actionCell.append(actionWrap);
  row.append(nameCell, emailCell, planCell, expiryCell, actionCell);
  return row;
}

function renderRecords() {
  const query = elements.searchInput.value.trim().toLocaleLowerCase("pt-BR");
  const filteredRecords = records.filter((record) => getSearchableText(record).includes(query));
  const now = Date.now();
  const activeVipOwners = new Set();
  for (const record of records) {
    const vipData = getVipData(record);
    const expiration = toDate(vipData.vipExpiresAt);
    const hasActiveVip =
      VIP_PLANS.includes(vipData.vipPlan) &&
      vipData.vipPlan !== "Free" &&
      expiration !== null &&
      expiration.getTime() > now;
    if (hasActiveVip) {
      activeVipOwners.add(
        currentCollection === "groups" ? getOrganizerId(record.data) : record.id,
      );
    }
  }

  elements.totalCount.textContent = String(records.length);
  elements.vipCount.textContent = String(activeVipOwners.size);
  elements.resultCount.textContent = `${filteredRecords.length} ${
    filteredRecords.length === 1 ? "cadastro" : "cadastros"
  }`;
  elements.recordsBody.replaceChildren();

  if (filteredRecords.length === 0) {
    const row = document.createElement("tr");
    const cell = document.createElement("td");
    cell.colSpan = 5;
    cell.className = "empty-state";
    cell.textContent = recordsLoadError
      ? "Não foi possível carregar os cadastros."
      : records.length
        ? "Nenhum cadastro corresponde à busca."
        : "Nenhum cadastro encontrado.";
    row.append(cell);
    elements.recordsBody.append(row);
    return;
  }

  const fragment = document.createDocumentFragment();
  for (const record of filteredRecords) {
    fragment.append(createRecordRow(record));
  }
  elements.recordsBody.append(fragment);
  if (targetRecordId) {
    const targetRow = [...elements.recordsBody.querySelectorAll("tr")].find(
      (row) => row.dataset.recordId === targetRecordId,
    );
    targetRow?.scrollIntoView({ behavior: "smooth", block: "center" });
    targetRecordId = undefined;
  }
}

function createVenueRequestCard(request) {
  const card = document.createElement("article");
  card.className = "venue-request-card";

  const header = document.createElement("div");
  header.className = "venue-request-header";
  const name = document.createElement("h3");
  name.className = "venue-request-name";
  name.textContent = request.data.name || "Local sem nome";
  const date = document.createElement("span");
  date.className = "muted";
  const createdAt = toDate(request.data.created_at);
  date.textContent = createdAt
    ? new Intl.DateTimeFormat("pt-BR", { dateStyle: "medium" }).format(createdAt)
    : "Data não informada";
  header.append(name, date);

  const address = document.createElement("p");
  address.className = "venue-request-address";
  address.textContent = request.data.address || "Endereço não informado";

  const requester = document.createElement("p");
  requester.className = "muted venue-requester";
  const requesterName = request.data.requester_name || "Organizador";
  const requesterEmail = request.data.requester_email || request.data.created_by || "";
  requester.textContent = requesterEmail
    ? `Solicitado por ${requesterName} · ${requesterEmail}`
    : `Solicitado por ${requesterName}`;

  const approveButton = document.createElement("button");
  approveButton.type = "button";
  approveButton.className = "button button-primary button-small";
  approveButton.textContent = "Revisar e aprovar";
  approveButton.addEventListener("click", () => openVenueApproval(request));

  const footer = document.createElement("div");
  footer.className = "venue-request-footer";
  footer.append(requester, approveButton);
  card.append(header, address, footer);
  return card;
}

function renderPendingVenues() {
  elements.venueRequestsCount.textContent = `${
    pendingVenueRequests.length
  } ${pendingVenueRequests.length === 1 ? "pendente" : "pendentes"}`;
  elements.venueRequestsList.replaceChildren();

  if (pendingVenueRequests.length === 0) {
    const emptyState = document.createElement("p");
    emptyState.className = "empty-state venue-empty-state";
    emptyState.textContent = "Nenhuma solicitação pendente.";
    elements.venueRequestsList.append(emptyState);
    return;
  }

  const fragment = document.createDocumentFragment();
  for (const request of pendingVenueRequests) {
    fragment.append(createVenueRequestCard(request));
  }
  elements.venueRequestsList.append(fragment);
}

function createVenueCard(venue) {
  const card = document.createElement("article");
  card.className = "venue-request-card";

  const header = document.createElement("div");
  header.className = "venue-request-header";
  const name = document.createElement("h3");
  name.className = "venue-request-name";
  name.textContent = venue.data.name || "Local sem nome";
  header.append(name);

  const address = document.createElement("p");
  address.className = "venue-request-address";
  address.textContent = venue.data.address || "Endereço não informado";

  const actions = document.createElement("div");
  actions.className = "venue-request-footer";
  const editButton = document.createElement("button");
  editButton.type = "button";
  editButton.className = "button button-quiet button-small";
  editButton.textContent = "Editar";
  editButton.addEventListener("click", () => openVenueEditor(venue));

  const deleteButton = document.createElement("button");
  deleteButton.type = "button";
  deleteButton.className = "button button-quiet button-small";
  deleteButton.textContent = "Excluir";
  deleteButton.addEventListener("click", () => void deleteVenue(venue));
  actions.append(editButton, deleteButton);
  card.append(header, address, actions);
  return card;
}

function renderVenues() {
  elements.venuesCount.textContent = `${venues.length} ${
    venues.length === 1 ? "local" : "locais"
  }`;
  elements.venuesList.replaceChildren();

  if (venues.length === 0) {
    const emptyState = document.createElement("p");
    emptyState.className = "empty-state venue-empty-state";
    emptyState.textContent = "Nenhum local cadastrado.";
    elements.venuesList.append(emptyState);
    return;
  }

  const fragment = document.createDocumentFragment();
  for (const venue of venues) {
    fragment.append(createVenueCard(venue));
  }
  elements.venuesList.append(fragment);
}

function listenToVenues() {
  unsubscribeVenues?.();
  elements.venuesCount.textContent = "Carregando…";
  elements.venuesList.replaceChildren();
  const loading = document.createElement("p");
  loading.className = "empty-state";
  loading.textContent = "Carregando locais…";
  elements.venuesList.append(loading);

  unsubscribeVenues = onSnapshot(
    collection(db, "venues"),
    (snapshot) => {
      venues = snapshot.docs
        .map((document) => ({ id: document.id, data: document.data() }))
        .sort((left, right) =>
          String(left.data.name ?? "").localeCompare(
            String(right.data.name ?? ""),
            "pt-BR",
          ),
        );
      renderVenues();
    },
    (error) => {
      venues = [];
      elements.venuesList.replaceChildren();
      const errorState = document.createElement("p");
      errorState.className = "empty-state venue-empty-state";
      errorState.textContent = "Não foi possível carregar os locais cadastrados.";
      elements.venuesList.append(errorState);
      elements.venuesCount.textContent = "Erro";
      showMessage(
        elements.dashboardMessage,
        error.code === "permission-denied"
          ? "Esta conta não tem permissão para gerenciar locais. Verifique a claim administrativa e as regras do Firestore."
          : `Não foi possível carregar os locais: ${error.message}`,
      );
    },
  );
}

function listenToPendingVenues() {
  unsubscribePendingVenues?.();
  elements.venueRequestsCount.textContent = "Carregando…";
  elements.venueRequestsList.replaceChildren();
  const loading = document.createElement("p");
  loading.className = "empty-state";
  loading.textContent = "Carregando solicitações…";
  elements.venueRequestsList.append(loading);

  unsubscribePendingVenues = onSnapshot(
    collection(db, "pending_venues"),
    (snapshot) => {
      pendingVenueRequests = snapshot.docs
        .map((document) => ({ id: document.id, data: document.data() }))
        .sort((left, right) => {
          const leftDate = toDate(left.data.created_at)?.getTime() ?? 0;
          const rightDate = toDate(right.data.created_at)?.getTime() ?? 0;
          return rightDate - leftDate;
        });
      renderPendingVenues();
    },
    (error) => {
      pendingVenueRequests = [];
      elements.venueRequestsList.replaceChildren();
      const errorState = document.createElement("p");
      errorState.className = "empty-state venue-empty-state";
      errorState.textContent = "Não foi possível carregar as solicitações.";
      elements.venueRequestsList.append(errorState);
      elements.venueRequestsCount.textContent = "Erro";
      showMessage(
        elements.dashboardMessage,
        error.code === "permission-denied"
          ? "Esta conta não tem permissão para moderar locais. Verifique a claim administrativa e as regras do Firestore."
          : `Não foi possível carregar as solicitações de locais: ${error.message}`,
      );
    },
  );
}

function openVenueApproval(request) {
  activeVenueRequestId = request.id;
  editingVenueId = undefined;
  manualVenueRef = undefined;
  elements.venueApprovalTitle.textContent = "Revisar solicitação";
  elements.approveVenueButton.textContent = "Aprovar e publicar";
  elements.approvalVenueName.value = request.data.name ?? "";
  elements.approvalVenueAddress.value = request.data.address ?? "";
  elements.approvalLatitude.value = request.data.latitude ?? "";
  elements.approvalLongitude.value = request.data.longitude ?? "";
  elements.approvalVenueCep.value = "";
  hideMessage(elements.venueApprovalMessage);
  elements.venueApprovalDialog.showModal();
  void setupVenuePlaceSearch();
}

function openManualVenueForm() {
  activeVenueRequestId = undefined;
  editingVenueId = undefined;
  manualVenueRef = doc(collection(db, "venues"));
  elements.venueApprovalTitle.textContent = "Adicionar campo";
  elements.approveVenueButton.textContent = "Adicionar e publicar";
  elements.approvalVenueName.value = "";
  elements.approvalVenueAddress.value = "";
  elements.approvalLatitude.value = "";
  elements.approvalLongitude.value = "";
  elements.approvalVenueCep.value = "";
  hideMessage(elements.venueApprovalMessage);
  elements.venueApprovalDialog.showModal();
  void setupVenuePlaceSearch();
}

function openVenueEditor(venue) {
  activeVenueRequestId = undefined;
  editingVenueId = venue.id;
  manualVenueRef = undefined;
  elements.venueApprovalTitle.textContent = "Editar local";
  elements.approveVenueButton.textContent = "Salvar alterações";
  elements.approvalVenueName.value = venue.data.name ?? "";
  elements.approvalVenueAddress.value = venue.data.address ?? "";
  elements.approvalLatitude.value = venue.data.latitude ?? "";
  elements.approvalLongitude.value = venue.data.longitude ?? "";
  elements.approvalVenueCep.value = "";
  hideMessage(elements.venueApprovalMessage);
  elements.venueApprovalDialog.showModal();
  void setupVenuePlaceSearch();
}

async function deleteVenue(venue) {
  const name = venue.data.name || "este local";
  if (!window.confirm(`Excluir "${name}" do cadastro de locais?`)) return;

  try {
    await deleteDoc(doc(db, "venues", venue.id));
    showMessage(elements.dashboardMessage, "Local excluído com sucesso.", "success");
  } catch (error) {
    showMessage(
      elements.dashboardMessage,
      error.code === "permission-denied"
        ? "A exclusão foi negada pelas regras do Firestore. Confirme se a conta tem permissão administrativa."
        : `Não foi possível excluir o local: ${error.message}`,
    );
  }
}

async function loadGooglePlaces() {
  if (window.google?.maps?.importLibrary) {
    return window.google.maps.importLibrary("places");
  }
  if (!GOOGLE_MAPS_API_KEY.trim()) {
    throw new Error(
      "Configure googleMapsApiKey em config.js para habilitar a busca do Google Maps.",
    );
  }
  if (!googleMapsLoadPromise) {
    googleMapsLoadPromise = new Promise((resolve, reject) => {
      let settled = false;
      const fail = (error) => {
        if (settled) return;
        settled = true;
        window.clearTimeout(googleMapsLoadTimeout);
        googleMapsLoadTimeout = undefined;
        googleMapsLoadPromise = undefined;
        reject(error);
      };
      window.nossoRachaGoogleMapsReady = () => {
        if (settled) return;
        settled = true;
        window.clearTimeout(googleMapsLoadTimeout);
        googleMapsLoadTimeout = undefined;
        resolve();
      };
      window.gm_authFailure = () => {
        fail(
          new Error(
            "O Google Maps rejeitou a chave. Confirme Maps JavaScript API, Places API (New), faturamento e as restrições de domínio da chave.",
          ),
        );
      };
      const script = document.createElement("script");
      script.src =
        "https://maps.googleapis.com/maps/api/js" +
        `?key=${encodeURIComponent(GOOGLE_MAPS_API_KEY.trim())}` +
        "&loading=async&callback=nossoRachaGoogleMapsReady&v=weekly";
      script.async = true;
      script.onerror = () =>
        fail(new Error("Não foi possível carregar a API JavaScript do Google Maps."));
      googleMapsLoadTimeout = window.setTimeout(
        () =>
          fail(
            new Error(
              "O Google Maps não respondeu. Verifique a conexão, a chave e as APIs habilitadas no Google Cloud.",
            ),
          ),
        15000,
      );
      document.head.append(script);
    });
  }
  await googleMapsLoadPromise;
  try {
    return await window.google.maps.importLibrary("places");
  } catch (error) {
    throw new Error(
      `Não foi possível carregar a Places API (New): ${error.message}`,
    );
  }
}

async function setupVenuePlaceSearch() {
  const setupVersion = ++venuePlaceSearchVersion;
  elements.approvalPlaceSearch.replaceChildren();
  elements.venuePlaceSearchStatus.textContent = "";
  try {
    const places = await loadGooglePlaces();
    if (setupVersion !== venuePlaceSearchVersion) return;
    const autocomplete = new places.PlaceAutocompleteElement({
      includedRegionCodes: ["br"],
    });
    autocomplete.placeholder = "Busque pelo nome ou endereço";
    autocomplete.className = "text-field venue-place-autocomplete";
    autocomplete.setAttribute("aria-labelledby", "approvalPlaceSearchLabel");
    autocomplete.addEventListener("gmp-select", (event) => {
      void selectVenuePlace(event.placePrediction);
    });
    elements.approvalPlaceSearch.append(autocomplete);
  } catch (error) {
    if (setupVersion !== venuePlaceSearchVersion) return;
    elements.venuePlaceSearchStatus.textContent = error.message;
  }
}

async function selectVenuePlace(placePrediction) {
  if (!placePrediction) return;
  hideMessage(elements.venueApprovalMessage);
  elements.venuePlaceSearchStatus.textContent = "Carregando dados do local…";
  try {
    const place = placePrediction.toPlace();
    await place.fetchFields({
      fields: ["displayName", "formattedAddress", "location"],
    });
    if (!place.location) {
      throw new Error("O resultado selecionado não possui coordenadas.");
    }

    elements.approvalVenueName.value =
      place.displayName?.text || elements.approvalVenueName.value;
    elements.approvalVenueAddress.value = place.formattedAddress || "";
    elements.approvalLatitude.value = place.location.lat();
    elements.approvalLongitude.value = place.location.lng();
    elements.venuePlaceSearchStatus.textContent =
      "Local selecionado. Endereço e coordenadas preenchidos.";
  } catch (error) {
    elements.venuePlaceSearchStatus.textContent =
      `Não foi possível carregar o local selecionado: ${error.message}`;
  }
}

async function lookupVenueCep() {
  hideMessage(elements.venueApprovalMessage);
  const cep = elements.approvalVenueCep.value.replace(/\D/g, "");
  if (cep.length !== 8) {
    showMessage(elements.venueApprovalMessage, "Informe um CEP válido com 8 dígitos.");
    elements.approvalVenueCep.focus();
    return;
  }

  elements.lookupVenueCepButton.disabled = true;
  try {
    const response = await fetch(`https://viacep.com.br/ws/${cep}/json/`);
    if (!response.ok) {
      throw new Error(`Consulta de CEP indisponível (HTTP ${response.status}).`);
    }
    const result = await response.json();
    if (result.erro) {
      throw new Error("CEP não encontrado.");
    }

    const city = [result.localidade, result.uf].filter(Boolean).join(" - ");
    elements.approvalVenueAddress.value = [
      result.logradouro,
      result.bairro,
      city,
      result.cep ? `CEP ${result.cep}` : "",
    ]
      .filter(Boolean)
      .join(", ");
    elements.venuePlaceSearchStatus.textContent =
      "Endereço preenchido pelo CEP. Informe ou selecione as coordenadas.";
  } catch (error) {
    showMessage(
      elements.venueApprovalMessage,
      `Não foi possível consultar o CEP: ${error.message}`,
    );
  } finally {
    elements.lookupVenueCepButton.disabled = false;
  }
}

async function approveVenue(event) {
  event.preventDefault();
  hideMessage(elements.venueApprovalMessage);

  const name = elements.approvalVenueName.value.trim();
  const address = elements.approvalVenueAddress.value.trim();
  const latitudeValue = elements.approvalLatitude.value.trim();
  const longitudeValue = elements.approvalLongitude.value.trim();
  const latitude = Number(elements.approvalLatitude.value);
  const longitude = Number(elements.approvalLongitude.value);
  if (
    (!activeVenueRequestId && !manualVenueRef && !editingVenueId) ||
    name.length < 2 ||
    address.length < 5 ||
    !latitudeValue ||
    !longitudeValue ||
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90 ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180
  ) {
    showMessage(
      elements.venueApprovalMessage,
      "Informe um nome (mín. 2 caracteres), endereço (mín. 5) e coordenadas válidas antes de publicar.",
    );
    return;
  }

  elements.approveVenueButton.disabled = true;
  const wasEditing = Boolean(editingVenueId);
  try {
    if (editingVenueId) {
      await updateDoc(doc(db, "venues", editingVenueId), {
        name,
        address,
        street: address,
        latitude,
        longitude,
        status: "approved",
        updated_at: serverTimestamp(),
        updated_by: auth.currentUser.uid,
      });
    } else {
      const batch = writeBatch(db);
      const venueRef =
        manualVenueRef ?? doc(db, "venues", activeVenueRequestId);
      batch.set(venueRef, {
        name,
        address,
        street: address,
        latitude,
        longitude,
        status: "approved",
        ...(activeVenueRequestId
          ? { source_request_id: activeVenueRequestId }
          : {}),
        approved_at: serverTimestamp(),
        approved_by: auth.currentUser.uid,
        created_at: serverTimestamp(),
      });
      if (activeVenueRequestId) {
        batch.delete(doc(db, "pending_venues", activeVenueRequestId));
      }
      await batch.commit();
    }
    elements.venueApprovalDialog.close();
    activeVenueRequestId = undefined;
    editingVenueId = undefined;
    manualVenueRef = undefined;
    showMessage(
      elements.dashboardMessage,
      wasEditing
        ? "Local atualizado com sucesso."
        : "Local aprovado e publicado para os organizadores.",
      "success",
    );
  } catch (error) {
    showMessage(
      elements.venueApprovalMessage,
      error.code === "permission-denied"
        ? "A aprovação foi negada pelas regras do Firestore. Confirme se a conta tem permissão administrativa."
        : `Não foi possível aprovar o local: ${error.message}`,
    );
  } finally {
    elements.approveVenueButton.disabled = false;
  }
}

function listenToCollection(collectionName) {
  unsubscribeRecords?.();
  unsubscribeRecords = undefined;
  unsubscribeOwnerProfiles?.();
  unsubscribeOwnerProfiles = undefined;
  currentCollection = collectionName;
  recordsLoadError = false;
  ownerProfilesById = new Map();
  elements.collectionCaption.textContent =
    collectionName === "users"
      ? "Usuários sincronizados com o Firestore"
      : "Grupos e planos dos respectivos organizadores";
  document.querySelector("#recordsHeading").textContent =
    collectionName === "users" ? "Usuários" : "Grupos";
  document.querySelector("#emailHeading").textContent =
    collectionName === "users" ? "E-mail" : "Organizador";
  document.querySelector("#planHeading").textContent =
    collectionName === "users" ? "Plano VIP" : "Plano do organizador";
  document.querySelector("#expiryHeading").textContent =
    collectionName === "users" ? "Vencimento" : "Vencimento do organizador";
  document.querySelector("#vipLabel").textContent =
    collectionName === "users" ? "Planos ativos" : "Organizadores VIP ativos";
  elements.connectionState.textContent = "Conectando";
  elements.recordsBody.replaceChildren();
  const loadingRow = document.createElement("tr");
  const loadingCell = document.createElement("td");
  loadingCell.colSpan = 5;
  loadingCell.className = "empty-state";
  loadingCell.textContent = "Carregando cadastros…";
  loadingRow.append(loadingCell);
  elements.recordsBody.append(loadingRow);

  if (collectionName === "groups") {
    unsubscribeOwnerProfiles = onSnapshot(
      collection(db, "users"),
      (snapshot) => {
        ownerProfilesById = new Map(
          snapshot.docs.map((userDocument) => [
            userDocument.id,
            { id: userDocument.id, data: userDocument.data() },
          ]),
        );
        renderRecords();
      },
      (error) => {
        showMessage(
          elements.dashboardMessage,
          `Não foi possível carregar os perfis dos organizadores: ${error.message}`,
        );
      },
    );
  }

  unsubscribeRecords = onSnapshot(
    collection(db, collectionName),
    (snapshot) => {
      recordsLoadError = false;
      records = snapshot.docs.map((document) => ({
        id: document.id,
        data: document.data(),
      }));
      elements.connectionState.textContent = "Conectado";
      hideMessage(elements.dashboardMessage);
      renderRecords();
    },
    (error) => {
      records = [];
      recordsLoadError = true;
      elements.connectionState.textContent = "Erro";
      renderRecords();
      showMessage(
        elements.dashboardMessage,
        error.code === "permission-denied"
          ? `Login realizado, mas esta conta não tem permissão para listar "${collectionName}". As regras do Firestore continuam exigindo acesso administrativo para esses dados.`
          : `Não foi possível carregar "${collectionName}": ${error.message}`,
      );
    },
  );
}

async function savePlan(recordId, planSelect, expiryInput, button) {
  hideMessage(elements.dashboardMessage);
  const plan = planSelect.value;
  let expiration = null;

  if (plan !== "Free") {
    if (!expiryInput.value) {
      showMessage(elements.dashboardMessage, "Defina a data de vencimento para um plano pago.");
      expiryInput.focus();
      return;
    }

    expiration = new Date(`${expiryInput.value}T23:59:59`);
    if (Number.isNaN(expiration.getTime()) || expiration.getTime() <= Date.now()) {
      showMessage(elements.dashboardMessage, "A data de vencimento deve ser válida e futura.");
      expiryInput.focus();
      return;
    }
  }

  button.disabled = true;
  try {
    const updates = {
      vipPlan: plan,
      vipExpiresAt: expiration ? Timestamp.fromDate(expiration) : null,
      updatedAt: serverTimestamp(),
    };
    await updateDoc(doc(db, currentCollection, recordId), updates);
    showMessage(elements.dashboardMessage, "Plano VIP atualizado com sucesso.", "success");
  } catch (error) {
    showMessage(
      elements.dashboardMessage,
      error.code === "permission-denied"
        ? "A gravação foi negada pelas regras do Firestore. Confirme se as regras atualizadas estão publicadas e se você está autenticado."
        : `Falha ao atualizar o plano: ${error.message}`,
    );
  } finally {
    button.disabled = false;
  }
}

async function approveManualPix(recordId, planSelect, expiryInput, button) {
  hideMessage(elements.dashboardMessage);
  if (planSelect.value === "Free") {
    showMessage(elements.dashboardMessage, "Selecione um plano pago antes de aprovar o Pix manual.");
    planSelect.focus();
    return;
  }

  const today = new Date();
  const currentExpiry = toDate(expiryInput.value ? new Date(`${expiryInput.value}T23:59:59`) : null);
  const renewalStart =
    currentExpiry && currentExpiry.getTime() > today.getTime() ? currentExpiry : today;
  const renewedUntil = new Date(renewalStart);
  renewedUntil.setDate(renewedUntil.getDate() + MANUAL_PIX_RENEWAL_DAYS);

  button.disabled = true;
  try {
    await updateDoc(doc(db, currentCollection, recordId), {
      vipPlan: planSelect.value,
      vipExpiresAt: Timestamp.fromDate(renewedUntil),
      updatedAt: serverTimestamp(),
      lastManualPayment: {
        method: "pix_manual",
        approvedAt: serverTimestamp(),
        approvedBy: auth.currentUser.uid,
        plan: planSelect.value,
      },
    });
    expiryInput.value = dateToInputValue(renewedUntil);
    showMessage(
      elements.dashboardMessage,
      `Pix registrado. O plano ${planSelect.value} foi renovado até ${formatDate(renewedUntil)}.`,
      "success",
    );
  } catch (error) {
    showMessage(
      elements.dashboardMessage,
      error.code === "permission-denied"
        ? "A gravação foi negada pelas regras do Firestore. Confirme se as regras atualizadas estão publicadas e se você está autenticado."
        : `Falha ao registrar o Pix: ${error.message}`,
    );
  } finally {
    button.disabled = false;
  }
}

async function showAdminDashboard(user) {
  hideMessage(elements.loginMessage);
  setView(true);
  elements.adminIdentity.textContent = user.email ?? user.uid;
  listenToCollection(elements.collectionSelect.value);
  listenToPendingVenues();
  listenToVenues();
}

function initialize() {
  if (!firebaseIsConfigured) {
    showMessage(
      elements.loginMessage,
      "Configure firebaseConfig em app.js com os dados do seu projeto antes de entrar.",
    );
    elements.loginButton.disabled = true;
    return;
  }

  const app = initializeApp(firebaseConfig);
  auth = getAuth(app);
  db = getFirestore(app);

  onAuthStateChanged(auth, (user) => {
    if (!user) {
      unsubscribeRecords?.();
      unsubscribeRecords = undefined;
      unsubscribePendingVenues?.();
      unsubscribePendingVenues = undefined;
      unsubscribeVenues?.();
      unsubscribeVenues = undefined;
      pendingVenueRequests = [];
      venues = [];
      records = [];
      recordsLoadError = false;
      elements.connectionState.textContent = "Desconectado";
      setView(false);
      return;
    }

    showAdminDashboard(user);
  });

  elements.loginForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    hideMessage(elements.loginMessage);
    elements.loginButton.disabled = true;

    try {
      await signInWithEmailAndPassword(
        auth,
        elements.loginEmail.value.trim(),
        elements.loginPassword.value,
      );
    } catch (error) {
      console.error("Firebase Authentication sign-in failed:", error);
      showMessage(elements.loginMessage, getLoginErrorMessage(error));
    } finally {
      elements.loginButton.disabled = false;
    }
  });

  elements.googleLoginButton.addEventListener("click", async () => {
    hideMessage(elements.loginMessage);
    elements.googleLoginButton.disabled = true;

    try {
      const provider = new GoogleAuthProvider();
      provider.setCustomParameters({ prompt: "select_account" });
      await signInWithPopup(auth, provider);
    } catch (error) {
      console.error("Firebase Google sign-in failed:", error);
      showMessage(elements.loginMessage, getLoginErrorMessage(error));
    } finally {
      elements.googleLoginButton.disabled = false;
    }
  });

  elements.signOutButton.addEventListener("click", async () => {
    try {
      await signOut(auth);
    } catch (error) {
      showMessage(elements.dashboardMessage, `Não foi possível sair da conta: ${error.message}`);
    }
  });

  elements.collectionSelect.addEventListener("change", () => {
    listenToCollection(elements.collectionSelect.value);
  });
  elements.searchInput.addEventListener("input", renderRecords);
  elements.addVenueButton.addEventListener("click", openManualVenueForm);
  elements.lookupVenueCepButton.addEventListener("click", lookupVenueCep);
  elements.closeRecordDetailsButton.addEventListener("click", () => {
    elements.recordDetailsDialog.close();
  });
  elements.venueApprovalForm.addEventListener("submit", approveVenue);
  elements.closeVenueApprovalButton.addEventListener("click", () => {
    elements.venueApprovalDialog.close();
  });
  elements.cancelVenueApprovalButton.addEventListener("click", () => {
    elements.venueApprovalDialog.close();
  });
  elements.recordDetailsDialog.addEventListener("click", (event) => {
    if (event.target === elements.recordDetailsDialog) {
      elements.recordDetailsDialog.close();
    }
  });
}

initialize();
