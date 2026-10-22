# Webhook Inbox

API em Ruby on Rails para receber webhooks em JSON, armazenar os eventos e processá-los em segundo plano. O projeto demonstra deduplicação por identificador externo, acompanhamento de status e novas tentativas após falhas temporárias.

O processamento atual registra a tentativa no log e marca o evento como concluído; não realiza operações de pagamento nem integrações externas.

## Tecnologias

- Ruby 3.4.2 (versão definida em `.ruby-version`).
- Rails 8.1.4, em modo API.
- SQLite para persistência e Puma como servidor.
- Active Job com adaptador `:async` em desenvolvimento e Solid Queue em produção.
- Minitest para testes de modelos, controllers e jobs.

## Executar localmente

Com Ruby e Bundler instalados:

```sh
git clone https://github.com/aly-antoayne/webhook_inbox.git
cd webhook_inbox
bundle install
bundle exec rails db:prepare
bundle exec rails server
```

A API fica disponível em `http://localhost:3000`. O repositório é privado e exige acesso autorizado para clonagem. No Windows, utilize RubyInstaller com Devkit caso seja necessário compilar dependências nativas.

Em desenvolvimento, os jobs executam dentro do processo da aplicação. Não é necessário iniciar um worker separado; jobs pendentes em memória podem ser perdidos quando o servidor reinicia.

## Endpoints

| Método | Rota | Comportamento |
| --- | --- | --- |
| POST | `/webhooks` | Salva um novo evento e agenda seu processamento. |
| GET | `/webhooks` | Retorna até 100 eventos, do mais recente para o mais antigo. |

### Receber um evento

O corpo deve ser JSON e conter `id` e `type`. O payload completo é armazenado, incluindo campos adicionais.

Exemplo em PowerShell:

```powershell
$payload = @{
  id = "evt_001"
  type = "payment.approved"
  data = @{
    payment_id = "pay_123"
    amount_cents = 15000
    currency = "BRL"
  }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod -Uri "http://localhost:3000/webhooks" -Method Post -ContentType "application/json" -Body $payload
```

Respostas:

- `201 Created`: evento criado; retorna o registro salvo.
- `200 OK`: identificador já recebido; retorna a mensagem `Evento já recebido` e, quando recuperado pelo controller, o registro existente.
- `422 Unprocessable Entity`: erro de validação, como ausência de identificador ou tipo; retorna um objeto com `errors`.

O campo `id` enviado no payload é salvo como `external_id`. O campo `id` do registro retornado é o identificador interno do banco. Repetir um identificador externo não atualiza o payload anterior nem agenda outro job. A unicidade é validada pelo modelo e por um índice único no banco.

### Consultar eventos

```powershell
Invoke-RestMethod -Uri "http://localhost:3000/webhooks" -Method Get
```

A listagem inclui payload, status, número de tentativas e datas de criação e atualização. Não há paginação ou filtros implementados.

## Processamento e novas tentativas

O `ProcessWebhookEventJob` usa a fila `default`:

1. Carrega o evento e encerra se ele já estiver `processed`.
2. Incrementa `attempts` e altera o status para `processing`.
3. Registra o processamento no log e altera o status para `processed`.

Eventos novos começam em `pending`. Para `TemporaryError`, o job permite até três execuções no total, com espera de cinco segundos entre tentativas. Ao esgotá-las, marca o evento como `failed`. Essa política não abrange automaticamente qualquer tipo de exceção.

Para demonstrar uma falha temporária, envie um identificador novo e `simulate_failure: true` na raiz do JSON:

```json
{
  "id": "evt_retry_001",
  "type": "payment.approved",
  "simulate_failure": true,
  "data": {}
}
```

Nesse cenário, a primeira execução retorna o status para `pending` e lança a falha simulada; a segunda conclui o processamento.

## Testes

```sh
bundle exec rails db:test:prepare
bundle exec rails test
```

Para executar somente os testes do job:

```sh
bundle exec rails test test/jobs/process_webhook_event_job_test.rb
```

A suíte cobre validações, recebimento e deduplicação de eventos, processamento, eventos já concluídos e recuperação após falha temporária.

## Estrutura principal

| Arquivo | Responsabilidade |
| --- | --- |
| `app/controllers/webhooks_controller.rb` | Recebimento e listagem dos eventos. |
| `app/models/webhook_event.rb` | Validações do identificador externo e do tipo. |
| `app/jobs/process_webhook_event_job.rb` | Processamento, contagem de tentativas e retry. |
| `config/routes.rb` | Rotas da API. |
| `config/database.yml` | Bancos SQLite por ambiente. |
| `config/queue.yml` | Workers e dispatchers do Solid Queue. |
| `test/` | Testes automatizados e fixtures. |

## Configuração e deploy

Os bancos locais ficam em `storage/`. Em produção, a configuração separa os bancos principal, de fila, de cache e de cable.

O projeto inclui `Dockerfile` e configuração de Kamal em `config/deploy.yml`. Os destinos e configurações de deploy são exemplos e precisam ser ajustados ao ambiente. Em produção, execute o Solid Queue por `ruby bin/jobs`, com `RAILS_ENV=production`, ou pelo supervisor integrado ao Puma ao definir `SOLID_QUEUE_IN_PUMA=true`.

Chaves e credenciais devem ser configuradas separadamente no ambiente de destino. O repositório exclui `config/master.key`, `config/credentials.yml.enc`, `config/credentials/`, arquivos `.env*`, `.kamal/secrets*`, bancos locais e logs. Não copie segredos para código, exemplos ou commits.

## Limitações atuais

A API ainda não implementa autenticação nem verificação de assinatura do remetente. Os endpoints permitem receber eventos e consultar os payloads armazenados; essas proteções precisam ser implementadas antes de expor a aplicação a dados reais em um ambiente público.

A deduplicação do recebimento e a verificação de status do job não garantem execução única de efeitos externos em cenários concorrentes.
