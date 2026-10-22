module DashboardHelper
  STATUS_LABELS = { "pending" => "Pendente", "processing" => "Processando", "processed" => "Processado", "failed" => "Falhou", "retrying" => "Nova tentativa", "paid" => "Pago", "refunded" => "Reembolsado" }.freeze
  ICONS = {
    "terminal" => "M3 4h18v16H3z M6 8l4 4-4 4 M12 16h5",
    "grid" => "M3 3h6v6H3z M15 3h6v6h-6z M3 15h6v6H3z M15 15h6v6h-6z",
    "table" => "M3 4h18v16H3z M3 9h18 M9 9v11 M15 9v11",
    "book" => "M12 5v16 M12 5C8 2 4 3 2 4v15c3-1 7-1 10 2 3-3 7-3 10-2V4c-3-1-7-2-10 1",
    "search" => "M20 20l-5-5 M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0",
    "send" => "M3 3l19 9-19 9 4-9-4-9z M7 12h15",
    "refresh" => "M20 7a9 9 0 1 0 1 9 M20 2v6h-6",
    "check" => "M8 12l3 3 6-7 M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0",
    "alert" => "M12 7v6 M12 17h.01 M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0",
    "clock" => "M12 6v6l4 2 M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0",
    "inbox" => "M3 4h18v16H3z M3 14h5l2 3h4l2-3h5",
    "copy" => "M8 8h13v13H8z M16 8V3H3v13h5",
    "arrow" => "M4 12h16 M14 6l6 6-6 6",
    "close" => "M5 5l14 14 M19 5L5 19",
    "menu" => "M3 6h18 M3 12h18 M3 18h18",
    "lock" => "M5 10h14v11H5z M8 10V6a4 4 0 0 1 8 0v4",
    "server" => "M3 3h18v7H3z M3 14h18v7H3z M6 6h1 M6 17h1",
    "chart" => "M3 3v18h18 M6 16l5-6 4 3 6-9",
    "plus" => "M12 4v16 M4 12h16"
  }.freeze

  def dashboard_icon(name)
    tag.svg(tag.path(d: ICONS.fetch(name, ICONS["grid"])), viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": "1.6", "stroke-linecap": "round", "stroke-linejoin": "round", class: "icon", "aria-hidden": "true")
  end

  def status_badge(status)
    tag.span(class: "status-badge #{status.in?(STATUS_LABELS.keys) ? status : ''}") do
      safe_join([ tag.span("", class: "status-dot"), STATUS_LABELS.fetch(status, status.to_s) ], " ")
    end
  end

  def dashboard_time(time)
    time&.strftime("%d/%m/%Y %H:%M:%S UTC") || "Ainda não enfileirado"
  end

  def event_filters(**overrides)
    { q: @query, status: @status, event_type: @event_type }.merge(overrides)
  end

  def highlighted_json(payload)
    # Escape every token via tag builders; payload content never becomes markup.
    tokens = JSON.pretty_generate(payload).scan(/"(?:\\.|[^"\\])*"\s*:|"(?:\\.|[^"\\])*"|\b(?:true|false|null)\b|-?\d+(?:\.\d+)?|\s+|./m)
    safe_join(tokens.map do |token|
      style = if token.rstrip.end_with?(":")
        "json-key"
      elsif token.start_with?('"')
        "json-string"
      elsif token.match?(/\A(?:-?\d|true|false|null)/)
        "json-number"
      else
        "json-punctuation"
      end
      tag.span(token, class: style)
    end)
  end

  def chart_points(series)
    maximum = [ series.map { |point| point[:count] }.max, 1 ].max
    series.each_with_index.map { |point, index| "#{(index * 700.0 / (series.size - 1)).round(2)},#{(190 - point[:count] * 160.0 / maximum).round(2)}" }.join(" ")
  end
end
