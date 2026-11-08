# Nosso Racha

Ecossistema para organizar o futebol amador: um marketplace de rachas e campos,
um aplicativo para atletas e organizadores e um painel web para operações
administrativas. A plataforma oferece planos Free e VIP, com recursos e limites
de uso definidos por perfil e organização.

## Arquitetura do monorepo

| Diretório | Responsabilidade |
| --- | --- |
| [`nosso_racha/`](./nosso_racha/) | Aplicativo Flutter para Android, iOS e Web. Inclui as regras, índices e testes do Firestore relacionados ao app. |
| [`nosso_racha_admin/`](./nosso_racha_admin/) | Painel administrativo web em JavaScript, HTML e CSS para gerenciar usuários, planos VIP e moderação de campos. |

O aplicativo e o painel usam Firebase Authentication e Cloud Firestore. O painel
é uma interface web estática que acessa o Firebase com o SDK cliente; os
utilitários administrativos em `nosso_racha_admin/functions/` são um componente
separado e usam Node.js e Firebase Admin SDK.

## Funcionalidades

- Criação, consulta e gestão de eventos, participantes e organizações.
- Planos Free e VIP com limites e permissões associados a atletas e
  organizadores.
- Operação administrativa de usuários e planos VIP.
- Moderação de solicitações de cadastro de campos e gestão dos locais publicados.
- Fluxo em duas etapas para a ajuda de custo do goleiro: o organizador registra
  o pagamento acordado como despesa do grupo e o beneficiário confirma o
  recebimento.

## Tecnologias

- **Aplicativo:** Flutter e Dart.
- **Identidade e dados:** Firebase Authentication e Cloud Firestore.
- **Painel:** JavaScript, HTML5 e CSS3.
- **Ferramentas administrativas:** Node.js e Firebase Admin SDK.

## Requisitos

- Flutter SDK e Dart SDK compatíveis com as versões declaradas em
  `nosso_racha/pubspec.yaml`.
- Node.js apenas para executar utilitários em `nosso_racha_admin/functions/`.
- Python 3 (ou outro servidor HTTP estático) para servir o painel localmente.
- Acesso a um projeto Firebase configurado para o app e para o painel.

## Executar localmente

Clone o repositório e entre na pasta do projeto:

```powershell
git clone <URL_DO_REPOSITORIO>
cd nosso-racha
```

### Aplicativo Flutter

Em um terminal:

```powershell
cd nosso_racha
flutter pub get
flutter run
```

Para executar no navegador Chrome:

```powershell
flutter run -d chrome
```

Configure o projeto Firebase e as opções por plataforma antes de executar.
Consulte [`nosso_racha/README.md`](./nosso_racha/README.md) para os detalhes de
configuração e desenvolvimento.

### Painel administrativo

Em outro terminal, na raiz do monorepo:

```powershell
cd nosso_racha_admin
py -m http.server 8080
```

Abra <http://localhost:8080>. O painel depende da configuração Firebase
existente em `app.js`; confirme que ela corresponde ao seu projeto, que o
domínio local está autorizado no Firebase Authentication e que a conta tem
permissões administrativas nas regras do Firestore. O recurso de busca do
Google Maps também requer uma chave de navegador com restrições adequadas.

Os scripts Node do diretório `nosso_racha_admin/functions/` têm dependências
próprias. Para instalá-las quando for trabalhar nesses utilitários:

```powershell
npm --prefix nosso_racha_admin/functions ci
```

## Segurança e configuração local

Não versione chaves privadas, arquivos `.env`, configurações locais do Android
ou artefatos de build. Configure e restrinja as chaves de navegador do Firebase
e Google Maps nos respectivos consoles; uma chave de cliente não substitui as
regras de segurança do Firestore. Se uma credencial privada já tiver sido
publicada, revogue-a e gere uma nova antes de continuar.

As regras e os índices do Firestore são mantidos junto ao código. Revise as
regras e os dados do projeto antes de qualquer implantação em produção.
