# Painel administrativo

## Executar localmente

Na raiz do monorepo, instale e compile os utilitários Tailwind:

```powershell
npm --prefix nosso_racha_admin ci
npm --prefix nosso_racha_admin run build:css
Copy-Item nosso_racha_admin\config.example.js nosso_racha_admin\config.js
py -m http.server 8080 -d nosso_racha_admin
```

Abra <http://localhost:8080>. O `config.js` é local e ignorado pelo Git; a chave
do Google Maps deve ser restrita por referenciador HTTP e APIs. O usuário do
painel precisa ter o custom claim `admin: true` no Firebase Authentication.
Publicar regras de segurança continua obrigatório: a interface não substitui
as permissões do Firestore.

## Navegação do painel

O painel é uma aplicação de página única. `navigation.js` controla a barra
lateral responsiva e alterna as seções de visão geral, cadastros, planos VIP,
moderação de campos e financeiro sem recarregar a página. O módulo financeiro
está indicado na navegação, mas ainda não consolida os caixas das organizações.

## Catálogo de planos VIP

O módulo `vip-plans.js` lê e grava o documento `settings/vip_plans`. Os únicos
planos disponíveis, sempre nessa ordem, são **Free**, **Bronze**, **Silver**,
**Gold** e **Platinum**. Os nomes e tipos de acesso são fixos; a tela permite
configurar cor, status, limites e recursos. IDs antigos `prata` e `ouro` são
exibidos como Silver e Gold, respectivamente. Configurações antigas de tiers
personalizados não aparecem nem são aceitas para novas atribuições; ao salvar
o catálogo, somente os cinco planos padrão são mantidos. Os limites configurados
são lidos pelo app Flutter no início da execução.

O catálogo pode ser inicializado pela edição de um dos cinco planos na tela
VIP. As regras permitem leitura pública dos metadados e escrita somente a
usuários autenticados com o custom claim `admin: true`. Publique as regras
definidas em `nosso_racha/firestore.rules` antes de usar a manutenção de planos:

```powershell
cd nosso_racha
firebase deploy --only firestore:rules --project nosso-racha
```

## Cadastro e revisão de campos

Na seção **Solicitações de novos campos**, use **Adicionar campo** para abrir
um cadastro manual. A busca do Google Maps e a consulta de CEP também estão
disponíveis ao revisar solicitações existentes. Selecionar um resultado do
Google Maps preenche nome, endereço e coordenadas; a consulta de CEP preenche
o endereço. As coordenadas também podem ser digitadas antes de publicar.

Na seção **Campos e complexos cadastrados**, é possível corrigir o nome,
endereço e coordenadas de um local publicado ou excluir um cadastro duplicado.
Essas ações exigem uma conta com permissão administrativa no Firestore.

## Configurar a busca do Google Maps

O painel usa o componente Places do Maps JavaScript API. Para habilitar a
busca:

1. No Google Cloud Console, habilite **Maps JavaScript API** e **Places API
   (New)** no projeto com faturamento configurado.
2. Crie uma chave de API para uso no navegador. Restrinja-a por referenciador
   HTTP aos domínios do painel e limite as APIs permitidas às APIs necessárias.
   A chave do navegador é pública por natureza; não use uma chave de service
   account nem confie em ocultá-la no JavaScript.
3. Copie `config.example.js` para `config.js` e preencha `googleMapsApiKey` com
   a chave restrita. `config.js` é ignorado pelo Git. Em produção, disponibilize
   esse arquivo como configuração de implantação e nunca o inclua no commit.

Se uma chave já foi publicada ou compartilhada sem restrições, revogue-a no
Google Cloud Console e crie uma nova. A chave substituta deve ter restrição de
referenciador HTTP para os domínios autorizados e restrição de API para
**Maps JavaScript API** e **Places API (New)**. A chave configurada no navegador
continua visível aos visitantes do site; as restrições são a proteção.

Se a busca exibir um erro, confira no console do navegador a origem bloqueada
ou a API que não foi autorizada. A restrição de referenciador deve corresponder
ao domínio real do painel (incluindo protocolo e padrão de caminho, como
`https://seu-dominio/*`); em desenvolvimento local, autorize também a origem
local usada pelo servidor. Habilite **Maps JavaScript API** e **Places API
(New)** na mesma conta/projeto da chave e confirme que o faturamento está
ativo.

Sem essa configuração, o painel informa que a busca do Google Maps está
indisponível; a consulta de CEP e o preenchimento manual continuam disponíveis.
A consulta de CEP usa o serviço público ViaCEP.
