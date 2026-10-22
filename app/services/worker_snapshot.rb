class WorkerSnapshot
  def self.call(adapter: ActiveJob::Base.queue_adapter.class.name.demodulize.delete_suffix("Adapter"), queue: SolidQueue)
    return { adapter: adapter, available: false, message: "Jobs em memória: este adaptador não expõe processos ou heartbeats persistentes." } unless adapter == "SolidQueue"

    { adapter: adapter, available: true,
      counts: { "Prontos" => queue::ReadyExecution.count, "Agendados" => queue::ScheduledExecution.count,
                "Em execução" => queue::ClaimedExecution.count, "Falhas na fila" => queue::FailedExecution.count },
      processes: queue::Process.order(last_heartbeat_at: :desc).limit(50).to_a }
  rescue ActiveRecord::ActiveRecordError
    { adapter: adapter, available: false, message: "Não foi possível consultar o banco da fila. Verifique a conexão e as migrations do Solid Queue." }
  end
end
