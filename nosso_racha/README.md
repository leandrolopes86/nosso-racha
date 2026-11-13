# Nosso Racha

Aplicativo Flutter para organizar partidas de futebol (“rachas”), seus participantes e a gestão dos pagamentos e resultados.

## Funcionalidades

- Consulta de eventos públicos e detalhes da partida.
- Cadastro e autenticação de usuários com Firebase Authentication.
- Perfil de atleta com posição limitada no plano Free, flexibilidade nos planos VIP e chave Pix opcional para goleiros.
- Criação e administração de eventos e grupos.
- Acesso a várias organizações vinculadas ao perfil e aos eventos privados permitidos.
- Inscrição, organização de participantes e formação de times.
- Acompanhamento de pagamentos, finanças e relatórios.
- Registro de resultados, presença e estatísticas.
- Notificações push e configuração de temas.
- Pagamentos por chave PIX manual ou integração com Mercado Pago.
- Pagamento negociável da ajuda de custo do goleiro, com QR Pix quando houver
  chave cadastrada, despesa atômica no caixa do grupo e confirmação de
  recebimento pelo beneficiado. A chave Pix fica em
  `events/{eventId}/goalie_payments/{uid}` (subcoleção privada), não na lista
  pública de participantes. Se não houver pagamento acordado, o organizador
  simplesmente não registra a despesa.

## Estrutura do projeto

```text
lib/
  core/theme/       Temas e paletas visuais
  models/           Modelos e conversão dos documentos Firestore
  screens/          Telas organizadas por domínio do produto
  services/         Autenticação, eventos, pagamentos, grupos e notificações
  widgets/          Componentes reutilizáveis e efeitos visuais
  main.dart         Inicialização do Firebase, providers e aplicação
test/               Testes unitários e de widgets Flutter
tool/
  firestore-migration/      Prévia e migração idempotente de dados legados
  firestore-rules-tests/    Testes de autorização no emulador Firestore
functions/                  Checkout VIP e ativação via webhook
firestore.rules             Regras de segurança versionadas
firestore.indexes.json      Índices compostos do Firestore
```

As telas dependem dos serviços injetados via Provider; os serviços encapsulam
acesso ao Firebase e os modelos convertem os documentos para tipos Dart.

## Requisitos

- Flutter SDK `>=3.38.1` e Dart SDK `>=3.10.0 <4.0.0`, conforme os requisitos das dependências atuais declarados em `pubspec.yaml`.
- Uma conta/projeto Firebase configurado para os serviços usados pelo app.
- Para compilar e executar o alvo iOS, é necessário macOS com Xcode.
- Node.js e Firebase CLI para testar as regras e a migração com os emuladores.

## Instalação

Clone o repositório e instale as dependências:

```bash
git clone <URL_DO_REPOSITORIO>
cd nosso-racha
flutter pub get
```

### Configuração do Firebase

O app inicializa o Firebase em `lib/main.dart`. Configure um projeto Firebase e gere/atualize as opções por plataforma com FlutterFire CLI:

```bash
flutterfire configure
```

Confirme que `lib/firebase_options.dart` e os arquivos nativos de configuração correspondem ao projeto Firebase escolhido. Ative e configure os serviços usados pelo aplicativo, incluindo Authentication, Cloud Firestore, Cloud Messaging e Cloud Functions.

As regras de acesso estão em `firestore.rules` e os índices das consultas estão em `firestore.indexes.json`. Antes de implantar as regras, audite e migre os dados legados. A Home descobre organizações por `groups/{groupId}/members/{uid}` e também combina os IDs legados em `users.group_ids`/`users.group_id`.
As regras permitem que cada usuário altere apenas os campos editáveis do próprio perfil; plano, permissões e dados administrativos não podem ser alterados pelo cliente comum. A validação de posição Free/VIP e da chave PIX de goleiro também é aplicada nas regras do Firestore.

Os limites padrão aplicados pelo aplicativo são centralizados em
`lib/models/plan_limits.dart`: atletas Free podem integrar até 2 organizações,
Atletas VIP até 10. Organizadores não VIP podem participar de até 2
organizações existentes, mas não criar comunidades; podem administrar as
organizações em que têm acesso. Organizador VIP pode criar comunidades
ilimitadas e participar de até 10 organizações; tem também eventos ilimitados.
Organizadores não VIP podem manter 3 rachas abertos simultaneamente, 40 atletas
e 3 co-organizadores por organização. As regras do Firestore também aplicam os
limites configurados de participação e capacidade das organizações por meio de
atualizações atômicas dos contadores. O limite `maxOwnedOrganizations` é
validado no cliente; não é aplicado independentemente pelas regras do Firestore.

Os recursos e limites dos planos Free, Bronze, Silver, Gold e Platinum são
carregados de `settings/vip_plans` no Firestore durante a inicialização e
modelados em `lib/models/vip_plans_config.dart`.
Enquanto o catálogo remoto não estiver configurado ou disponível, o app mantém
os limites padrões locais e registra a falha no log. O painel grava `vipPlan`
e `vipExpiresAt` no perfil; os IDs desses tiers são fixos. Cada plano mapeia
para acesso Free, atleta VIP ou organizador VIP, e pode definir limites de
organizações, eventos, atletas, co-organizadores e recursos. Os nomes legados
`prata` e `ouro` continuam reconhecidos como Silver e Gold. O acesso às
funcionalidades administrativas VIP continua verificado pelo vínculo de
proprietário ou co-organizador em `lib/services/group_plan_service.dart`.
A validade é obrigatória e planos vencidos não concedem benefícios. O formato
legado de assinatura do proprietário continua
aceito por `plan`, `subscription.status` ou `plan_status` e,
opcionalmente, `subscription.expires_at` ou `plan_expires_at`. As regras do
Firestore aplicam as permissões e os limites de eventos e membros configurados.
As configurações gerais e de pagamento ficam em
`groups/{groupId}/settings/general` e
`groups/{groupId}/settings/payment_gateway`; eventos e lançamentos financeiros
usam o mesmo `group_id` para manter cada painel isolado.

Atletas que não pertencem à organização enviam uma solicitação de entrada
armazenada em `events/{eventId}/join_requests/{uid}`. O organizador aprova ou
rejeita a solicitação na tela do evento; somente após aprovação o atleta entra
na lista ou na fila. Solicitações de goleiro são conferidas novamente na
aprovação para respeitar as vagas externas reservadas.

Para auditar ou executar a migração compatível com os dados legados, use
`tool/firestore-migration`. Ela começa em modo de prévia (sem escrita), atribui
`public` somente a eventos cujo campo `info.visibility` está ausente ou nulo,
cria/ajusta as associações apontadas por `users.group_ids` e `users.group_id` e
garante uma associação para cada proprietário de grupo. Associações válidas
existentes, inclusive o papel `co_organizer`, são preservadas. Grupos inexistentes
e eventos sem o mapa `info` são reportados como ignorados e exigem revisão manual.
Também inicializa `athlete_count`, `co_organizer_count` e `open_events_count`
com base nas associações e eventos existentes. Eventos abertos sem organização,
com referência órfã, documentos de evento malformados e visibilidades desconhecidas
e papéis de membro inválidos aparecem no relatório para revisão. Eventos
existentes com `info.visibility` são preservados. Lançamentos antigos ligados
a eventos recebem o `group_id` da organização do evento; lançamentos manuais
legados sem evento relacionado não são atribuídos automaticamente a um grupo.
Configure Application
Default Credentials com permissão de leitura e escrita no Firestore antes de
usar o projeto de produção; não coloque chaves de serviço no repositório:

```bash
npm --prefix tool/firestore-migration install
firebase emulators:exec --only firestore --project demo-nosso-racha "npm --prefix tool/firestore-migration test"
npm --prefix tool/firestore-migration run migrate -- --project nosso-racha
```

Revise a prévia e resolva qualquer documento ignorado antes de executar com
`--apply`. A migração deve ser aplicada antes de implantar as regras novas e
antes que os clientes atualizados tentem criar/remover eventos ou membros.
Pause gravações de eventos e membros durante a aplicação da migração e a
implantação conjunta das regras/cliente para evitar divergência entre os
contadores recalculados e gravações de versões antigas do app:

```bash
npm --prefix tool/firestore-migration run migrate -- --project nosso-racha --apply
firebase deploy --only firestore --project nosso-racha
```

O script é idempotente e não altera visibilidades que já estejam definidas.
Eventos sem `info.visibility` recebem `public`, preservando o comportamento
anterior do app. Associações apontadas para grupos inexistentes, eventos sem o
mapa `info` e visibilidades desconhecidas exigem revisão manual antes do deploy.

Para inicializar somente o contador de eventos abertos de uma organização
legada, sem alterar os demais dados, use a operação direcionada. Ela começa em
modo de prévia e só grava com `--apply`:

```bash
npm --prefix tool/firestore-migration run initialize-open-event-counter -- --project nosso-racha --group <ID>
npm --prefix tool/firestore-migration run initialize-open-event-counter -- --project nosso-racha --group <ID> --apply
```

O contador é calculado a partir dos eventos `scheduled`, `published` e
`in_progress` vinculados àquela organização. Um contador válido existente não
é sobrescrito.

Convites para eventos privados exigem autenticação. O link pode ser resgatado por sete dias; após o resgate, o usuário mantém acesso ao evento. A coleção `events/{eventId}/invites` contém o token secreto: não compartilhe documentos de convite nem permita listagem dessa subcoleção.

O app chama as funções `createMercadoPagoPix`, `refundMercadoPagoPix` e `checkAndProcessPayment` para pagamentos de eventos. O código-fonte dessas funções existentes não está neste repositório. O checkout e webhook de assinaturas VIP estão implementados em `functions/index.js`. Não inclua tokens privados do Mercado Pago no app cliente.

## Planos VIP e pagamentos

No painel `nosso_racha_admin`, os cards exibem preço e duração; para editá-los, abra o modal **Editar plano** na seção **Planos VIP**. A seção **Pagamento VIP** concentra o método ativo e os dados Pix ou Mercado Pago. A preferência pública fica em `settings/payment_config`; o Access Token do Mercado Pago é armazenado em `settings/private_vip_payment_config`, sem leitura pelo app.

A seção **Cupons de desconto** permite limitar cada cupom a um ou mais planos VIP e escolher desconto percentual, valor fixo ou preço final. Também é possível limitar usos, definir data e hora de encerramento, ou ambos; o cupom deixa de valer quando qualquer limite for atingido primeiro. O servidor valida o plano, a validade e o limite no checkout e reserva o uso de forma atômica. Solicitações Pix manual recusadas e cobranças automáticas canceladas ou falhas liberam a reserva.

No modo Pix Manual, o app registra uma solicitação pendente em `vip_payment_requests`. Um administrador aprova ou recusa no painel; ao aprovar, o tier e o vencimento são atualizados no perfil do usuário. No modo Mercado Pago, a callable cria a cobrança e o webhook `mercadoPagoVipWebhook` consulta a API antes de ativar o plano. As telas atualizam o estado e os selos usam `vipPlan` e `vipExpiresAt`; um tier expirado deixa de ser tratado como VIP ativo.

Para preparar o projeto:

```bash
npm --prefix functions install
npm --prefix functions run lint
npm --prefix functions test
firebase deploy --only firestore:rules,firestore:indexes,functions --project nosso-racha
```

Depois, configure no painel Mercado Pago uma notificação do tipo `payment` para:
`https://southamerica-east1-nosso-racha.cloudfunctions.net/mercadoPagoVipWebhook`.
O administrador deve inserir o Access Token somente no painel; não o inclua em `config.js`, no app Flutter ou no repositório. Preços e duração começam em zero/30 dias até serem definidos pelo administrador, e planos sem preço positivo não permitem iniciar a cobrança.

## Executar

Liste os dispositivos disponíveis e inicie o app:

```bash
flutter devices
flutter run
```

Exemplos para alvos específicos:

```bash
flutter run -d chrome
flutter run -d <ID_DO_DISPOSITIVO>
```

Ao iniciar, a Home pública lista os rachas disponíveis. Depois de entrar, abra
uma organização associada ao perfil para consultar os eventos daquele grupo.
Organizadores autorizados podem criar eventos pelo botão **NOVO JOGO**; convites
para eventos privados são resgatados ao abrir o link já autenticado.

Não há capturas de tela versionadas no repositório neste momento.

## Dependências

As dependências principais declaradas em `pubspec.yaml` incluem:

- **Firebase:** `firebase_core`, `firebase_auth`, `cloud_firestore`, `cloud_functions` e `firebase_messaging`.
- **Estado e armazenamento:** `provider` e `shared_preferences`.
- **Interface:** `google_fonts`, `lucide_icons_flutter` e `cupertino_icons`.
- **Utilitários e integrações:** `intl`, `mask_text_input_formatter`, `url_launcher`, `http`, `share_plus`, `package_info_plus` e `web`.
- **Desenvolvimento e testes:** Flutter SDK, `flutter_test` e `flutter_lints`.

`flutter_launcher_icons` não é usado: a configuração antiga apontava para
`assets/images/logo.png`, que não existe no repositório. Os ícones nativos já
gerados permanecem nos diretórios de plataforma e as telas com referência à
imagem exibem um ícone de fallback. Para adicionar geração automática, primeiro
inclua e versione a imagem original da marca.

Para resolver as dependências declaradas, execute `flutter pub get`. Para
inspecionar atualizações disponíveis sem aplicar migrações de versão principal:

```bash
flutter pub outdated
```

As versões principais do Firebase estão limitadas no `pubspec.yaml` para evitar
uma migração incompatível implícita; atualize-as em uma mudança dedicada e
valide cada plataforma.

## Verificações

Execute a análise estática e os testes antes de enviar alterações:

```bash
flutter analyze
flutter test
```

Os testes de autorização das regras do Firestore usam o emulador e ficam em
`tool/firestore-rules-tests`. Instale as dependências Node uma vez e execute:

```bash
npm --prefix tool/firestore-rules-tests install
firebase emulators:exec --only firestore --project demo-nosso-racha "npm --prefix tool/firestore-rules-tests test"
```

Os testes da migração são executados pelo mesmo emulador:

```bash
npm --prefix tool/firestore-migration install
firebase emulators:exec --only firestore --project demo-nosso-racha "npm --prefix tool/firestore-migration test"
```

## Contribuição

1. Crie uma branch para sua alteração.
2. Mantenha as mudanças focadas e siga os padrões existentes no projeto.
3. Execute `dart format lib test`, `flutter analyze` e `flutter test` e descreva eventuais falhas conhecidas.
4. Abra um pull request com o objetivo, as alterações e os passos para validar.

## Licença

Este repositório não contém um arquivo de licença. Até que uma licença seja escolhida e adicionada, os direitos de uso, cópia e distribuição não estão concedidos por este README. Defina a licença do projeto antes de distribuí-lo como software de código aberto.
