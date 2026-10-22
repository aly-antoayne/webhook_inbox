# Webhook Inbox

Aplicação Ruby on Rails que demonstra pagamentos fictícios de ponta a ponta: webhook assinado → evento persistido → worker → pedido atualizado de `pending` para `paid`.

O dashboard em `/dashboard` (ou `/`) reúne eventos, pedidos e workers. O projeto não faz cobranças nem reembolsos bancários e não está conectado a um provedor real.

## Stack

- Ruby 3.4.2, Rails 8.1.4, SQLite e Puma.
- Active Job com Solid Queue persistente em desenvolvimento e produção.
- Minitest com adaptador de teste em memória.

## Executar no Windows / PowerShell

```powershell
bundle install
bundle exec rails db:prepare
```

Gere credenciais locais **uma vez**. Repetir o bloco troca as credenciais; reinicie o servidor se fizer isso.

```powershell
$signingSecret = ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
$readToken = ruby -rsecurerandom -e 'puts SecureRandom.hex(32)'
$dashboardPassword = ruby -rsecurerandom -e 'puts SecureRandom.hex(24)'
@(
  ('$env:WEBHOOK_SIGNING_SECRET = "' + $signingSecret + '"')
  ('$env:WEBHOOK_READ_TOKEN = "' + $readToken + '"')
  '$env:DASHBOARD_USERNAME = "portfolio"'
  ('$env:DASHBOARD_PASSWORD = "' + $dashboardPassword + '"')
) | Set-Content .env.local.ps1
```

O arquivo `.env.local.ps1` contém segredos, fica ignorado pelo Git e deve permanecer local. Rails não o carrega automaticamente: execute-o em cada terminal que precisar dessas variáveis.

**Terminal 1 — servidor:**

```powershell
. .\.env.local.ps1
bundle exec rails server
```

**Terminal 2 — worker persistente:**

```powershell
bundle exec ruby bin/jobs --mode async
```

O argumento `--mode async` faz o supervisor do Solid Queue usar threads, compatíveis com Windows. A fila continua persistida em SQLite; isso é diferente do adaptador Active Job `:async`. Não é mais necessário definir `USE_SOLID_QUEUE`.

Abra `http://localhost:3000/dashboard` e use o usuário `portfolio` e a senha gerada no arquivo local. O servidor precisa ser reiniciado para receber novas variáveis de ambiente.

## Demonstração de pagamentos

Com servidor e worker ativos, em um terceiro terminal:

```powershell
. .\.env.local.ps1
ruby bin/demo-payments
```

O remetente fictício faz requisições HTTP reais, assinadas com HMAC. Ele envia `order.created`, aguarda o processamento, envia `payment.approved` e consulta os eventos com o token de leitura. Um pedido de BRL 159,90 aparece como `paid` no dashboard.

Cada execução usa identificadores novos. Para outra porta local:

```powershell
$env:DEMO_BASE_URL = "http://127.0.0.1:3001"
ruby bin/demo-payments
```

O cliente aceita apenas `localhost` e `127.0.0.1`. Se o worker estiver parado, o evento permanece salvo e enfileirado; o cliente informa o tempo de espera excedido.

Para popular também exemplos de pedido pendente, reembolso e falha temporária:

```powershell
bundle exec rails demo:orders
```

Essa tarefa funciona apenas em desenvolvimento e insere exemplos diretamente no banco antes de enfileirá-los. Use `bin/demo-payments` para demonstrar a assinatura e a API HTTP.

## Endpoints e proteção

| Método | Rota | Autorização | Resultado |
| --- | --- | --- | --- |
| POST | `/webhooks` | Assinatura HMAC e timestamp | Salva e enfileira o evento. |
| GET | `/webhooks` | `Authorization: Bearer <WEBHOOK_READ_TOKEN>` | Até 100 eventos mais recentes. |
| GET | `/`, `/dashboard` | HTTP Basic | Indicadores, pedidos, eventos e workers. |
| GET | `/dashboard/events` | HTTP Basic | Busca, filtros e paginação de eventos. |
| GET | `/dashboard/events/:id` | HTTP Basic | Payload, metadados e histórico de tentativas. |
| GET | `/dashboard/documentation` | HTTP Basic | Guia de integração e ciclo do evento. |
| POST | `/dashboard/demo` | HTTP Basic + CSRF | Enfileira um cenário fictício; bloqueado em produção. |
| POST | `/dashboard/events/:id/retry` | HTTP Basic + CSRF | Reenfileira um evento com falha. |

As consultas e o recebimento ficam indisponíveis se suas credenciais não estiverem configuradas, inclusive em desenvolvimento. As respostas do painel e da API usam `Cache-Control: no-store`.

### Assinatura de eventos

Este é um protocolo de demonstração próprio, não a implementação de um provedor específico:

- `WEBHOOK_SIGNING_SECRET`: segredo compartilhado com o remetente, com pelo menos 32 bytes.
- `X-Webhook-Timestamp`: horário Unix em segundos, decimal.
- `X-Webhook-Signature`: `sha256=<digest hexadecimal minúsculo>`.
- Digest: HMAC-SHA256 do texto `timestamp.corpo_original`, usando o segredo.
- Tolerância: cinco minutos para timestamps no passado ou no futuro.
- A comparação é feita em tempo constante. Alterar espaços, valores ou qualquer byte do corpo invalida a assinatura.
- Apenas o JSON assinado é utilizado: parâmetros de query não sobrescrevem `id`, `type` ou o payload.
- Reenvios dentro da janela são deduplicados por `id`; reenvios posteriores precisam de timestamp e assinatura novos.

Exemplo da composição no remetente Ruby:

```ruby
timestamp = Time.now.to_i.to_s
digest = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
signature = "sha256=#{digest}"
```

O corpo deve ser um objeto JSON com `id` e `type` textuais, não vazios e com até 255 caracteres. O payload inteiro é armazenado.

| Código HTTP | Significado |
| --- | --- |
| 201 | Evento salvo e enfileirado. |
| 200 | Mesmo evento e mesmo payload já recebidos. |
| 400 | JSON inválido. |
| 401 | Assinatura ausente, inválida ou expirada; ou token de consulta inválido. |
| 409 | Identificador reutilizado com outro payload, ou recebimento concorrente que requer reenvio. |
| 415 | Corpo enviado sem `Content-Type: application/json`. |
| 422 | Campos obrigatórios inválidos. |
| 503 | Credenciais não configuradas, ou evento salvo aguardando recuperação do enfileiramento. |

O `id` externo vira `external_id`; o `id` retornado no registro é o identificador interno do banco. Em caso de 503 da fila, reenvie o mesmo evento com assinatura atualizada. O payload original permanece salvo.

### Consulta autenticada

```powershell
. .\.env.local.ps1
Invoke-RestMethod -Uri "http://localhost:3000/webhooks" -Headers @{
  Authorization = "Bearer $env:WEBHOOK_READ_TOKEN"
}
```

O token de leitura também deve ter pelo menos 32 bytes. Ele é independente do segredo de assinatura e não deve ser enviado em query strings.

## Contrato de pedidos

```json
{
  "id": "evt_order_001",
  "type": "order.created",
  "data": {
    "order_id": "order_001",
    "amount_cents": 15990,
    "currency": "BRL"
  }
}
```

Para aprovar ou reembolsar, envie um novo `id` com `payment.approved` ou `payment.refunded`, mantendo os dados do pedido.

- `Order` guarda identificador, valor inteiro em centavos, moeda e estado.
- Estados: `pending` → `paid` → `refunded`.
- Valor não negativo; moedas BRL, USD e EUR; apenas reembolso integral.
- Valor ou moeda divergente faz o evento falhar sem alterar o pedido.
- Uma aprovação antes da criação também cria o pedido; eventos atrasados não regridem seu estado.
- Eventos genéricos de pagamento sem `data.order_id` continuam processados sem criar pedidos.
- A validação de domínio é assíncrona: o recebimento pode retornar 201 e o processamento terminar em `failed`.

## Fila, recuperação e tentativas

Solid Queue persiste os jobs no banco `storage/development_queue.sqlite3` em desenvolvimento e no banco de fila configurado para produção. Reiniciar o servidor não apaga os jobs. O worker separado precisa estar ativo.

O evento é salvo antes do enfileiramento. `enqueued_at` só é preenchido depois que a fila aceita o job. Se a fila falhar, o evento permanece pendente e o endpoint responde 503. A tarefa recorrente `RecoverWebhookDeliveriesJob` recupera até 100 eventos sem marca de entrega por execução, a cada minuto; um reenvio também tenta recuperar a entrega.

O scheduler do Solid Queue precisa estar ativo para essa recuperação automática. Não use `--skip-recurring` no uso normal.

Essa entrega é **pelo menos uma vez**: uma interrupção entre gravar o job e marcar o evento pode gerar outro job. O processamento usa transação e lock no evento, e ignora eventos já processados. Isso não equivale a uma garantia de execução única para integrações externas.

`ProcessWebhookEventJob` incrementa `attempts` e aplica o evento ao pedido. Cada execução registra início, término, resultado e mensagem em `WebhookAttempt`. `TemporaryError` permite até três execuções no total, com intervalo de cinco segundos; o esgotamento marca `failed`. Dados de pedido inválidos também marcam `failed`. Eventos anteriores à criação desse histórico mantêm seu contador, sem gerar tentativas retroativas fictícias.

Para demonstrar uma falha temporária, adicione `"simulate_failure": true` na raiz de um novo payload: a primeira tentativa volta a `pending`, e a seguinte pode concluir.

## Dashboard

- **Visão geral:** indicadores e gráfico por hora ou dia, com períodos de 24 horas ou sete dias; cinco eventos recentes e dez pedidos atualizados recentemente.
- **Eventos:** busca por identificador ou tipo, filtros por status e tipo, dez registros por página e estado vazio quando não há resultados.
- **Detalhes:** JSON com destaque de sintaxe, cópia do payload, metadados e histórico real de tentativas com duração. O botão de reprocessamento aparece para eventos com falha.
- **Workers:** jobs prontos, agendados, em execução e falhas da fila; até 50 processos Solid Queue com host, PID e último heartbeat.
- **Documentação:** arquitetura, autenticação dos endpoints, contrato de pedidos e estados do processamento.
- **Demonstração:** botão “Enviar evento de teste” com pagamento aprovado, falha temporária, reembolso e dados inválidos. Disponível fora de produção, insere eventos diretamente e usa a fila configurada. Para testar a assinatura HTTP, use `bin/demo-payments`.

Use **Atualizar** para consultar novos dados. Os horários são exibidos em UTC. Os gráficos agrupam os registros por hora ou dia, incluindo o intervalo atual ainda em andamento. Um processo registrado não garante saúde: confira o heartbeat. Falhas de domínio tratadas pelo job aparecem nos eventos, não necessariamente nas falhas da fila.

O visual adapta as quatro telas do arquivo `stitch_webhook_inbox_dashboard.zip`: visão geral, eventos, detalhes e documentação. As views ERB usam `public/dashboard.css` e `public/dashboard.js`, com navegação adaptada para celular, foco visível e suporte à preferência por movimento reduzido. As fontes Geist e Space Grotesk são servidas localmente; suas licenças ficam em `public/fonts`. A interface não depende de CDN, Tailwind em tempo de execução ou serviços de analytics.

Depois de atualizar uma instalação existente, execute `bundle exec rails db:prepare` e reinicie o servidor e o worker para carregar as novas tabelas e o registro de tentativas.

## Testes

```powershell
bundle exec rails db:test:prepare
bundle exec rails test
```

A suíte cobre assinatura, timestamps, adulteração do corpo, consulta autenticada, proteção do dashboard e CSRF, filtros e paginação, demonstração, reprocessamento, histórico de tentativas, deduplicação, recuperação de enfileiramento, pedidos fora de ordem e o fluxo HTTP assinado de `pending` para `paid`.

## Configuração e limites

As variáveis necessárias são `WEBHOOK_SIGNING_SECRET`, `WEBHOOK_READ_TOKEN`, `DASHBOARD_USERNAME` e `DASHBOARD_PASSWORD`. Em produção, injete-as por um gerenciador de segredos e use HTTPS. A API e o painel têm credenciais separadas; não há contas de usuário, permissões por cliente ou isolamento entre organizações.

O projeto inclui Dockerfile e configuração de Kamal de exemplo. Ajuste servidores, domínio, TLS e segredos antes de um deploy. Em produção, use `RAILS_ENV=production` para o worker ou o supervisor integrado ao Puma com `SOLID_QUEUE_IN_PUMA=true`.

Antes de integrar um provedor real, adapte os headers, assinatura, rotação de segredos e contrato de eventos à documentação dele. Ainda faltam controles como rate limiting, limites de payload, retenção de dados e observabilidade de produção. O simulador não confirma pagamentos com um banco.

Chaves Rails, credenciais, arquivos `.env*`, segredos Kamal, bancos locais e logs ficam fora do Git. Nunca coloque valores reais em exemplos ou commits.
