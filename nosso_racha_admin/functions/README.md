# Administração sem Cloud Functions

Este fluxo não publica Cloud Functions e não exige migrar o projeto para o plano
Blaze. Os scripts usam Firebase Admin SDK localmente, com as credenciais do
Google Cloud autenticadas na máquina do operador. Nunca execute esses scripts
no navegador nem coloque credenciais de service account no repositório.

> **Atenção durante os testes:** as regras atuais permitem que qualquer usuário
> autenticado altere os campos de plano VIP em `users`. Essa permissão é
> temporária e deve ser restringida antes de disponibilizar o painel em produção.

## Preparação

Instale as dependências do Admin SDK uma vez:

```powershell
npm --prefix functions install
```

## Criar usuários de teste no Authentication

O script cria `usuario1@nossoracha.com.br` até `usuario30@nossoracha.com.br`,
com nomes `Usuario 1` até `Usuario 30` e a senha compartilhada `123456`.
Contas que já existirem são ignoradas; outros erros encerram a execução.
Use essas contas somente em um projeto de desenvolvimento/teste.

No PowerShell, a partir da pasta `nosso-racha`:

```powershell
Set-Location .\nosso_racha_admin
$env:GOOGLE_APPLICATION_CREDENTIALS = (Resolve-Path ..\nosso_racha\serviceAccountKey.json).Path
node functions\seed-test-users.js
```

Proteja o arquivo de credenciais, não o envie ao repositório e remova a variável
de ambiente ao terminar:

```powershell
Remove-Item Env:GOOGLE_APPLICATION_CREDENTIALS
```

Autentique o Google Cloud CLI com uma identidade que tenha permissão para
gerenciar usuários do Firebase Authentication e gravar no Firestore:

```powershell
gcloud auth application-default login
$env:GCLOUD_PROJECT = "nosso-racha"
```

## Registrar o primeiro administrador

1. Crie ou confirme a conta do proprietário em Firebase Authentication. Ela
   precisa estar ativa e ter o e-mail verificado.
2. Copie o UID em Firebase Console → Authentication → Users.
3. Execute:

   ```powershell
   $env:ADMIN_UID = "UID_DO_PROPRIETARIO"
   node functions\bootstrap-admin.js
   ```

4. Para retornar à proteção administrativa no futuro, conceda a claim
   `admin: true` com este script e reative a validação correspondente nas regras
   do Firestore e no painel.

## Listar administradores

```powershell
$env:ADMIN_ACTION = "list"
node functions\manage-admin.js
```

## Conceder acesso a outra conta

A conta precisa existir no Authentication, estar ativa e ter e-mail verificado:

```powershell
$env:ADMIN_ACTION = "grant"
$env:ADMIN_EMAIL = "pessoa@exemplo.com"
$env:ADMIN_ACTOR_UID = "UID_DO_ADMIN_QUE_AUTORIZA"
node functions\manage-admin.js
```

Após habilitar novamente a validação da claim, peça à pessoa para sair e entrar
novamente no painel para renovar o token.

## Revogar acesso

```powershell
$env:ADMIN_ACTION = "revoke"
$env:ADMIN_EMAIL = "pessoa@exemplo.com"
$env:ADMIN_ACTOR_UID = "UID_DO_ADMIN_QUE_AUTORIZA"
node functions\manage-admin.js
```

O script impede revogar o próprio UID informado e o último administrador
registrado. Refresh tokens são revogados, mas tokens de acesso já emitidos
podem continuar válidos por até uma hora.

## Firestore

As regras estão em `../firestore.rules` e podem ser publicadas sem implantar
Cloud Functions:

```powershell
firebase deploy --only firestore:rules --project nosso-racha
```

Revise as regras existentes antes de publicar, especialmente o acesso à coleção
`users`; veja a descrição e as premissas no arquivo de regras. O plano VIP de
grupo é exibido a partir do perfil do organizador e deve ser renovado em
`users/{uid}`. As regras não permitem gravar dados VIP no documento do grupo.
