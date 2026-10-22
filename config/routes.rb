Rails.application.routes.draw do
root "dashboard#index"
get "/dashboard", to: "dashboard#index"
get "/dashboard/events", to: "dashboard#events", as: :dashboard_events
get "/dashboard/documentation", to: "dashboard#documentation", as: :dashboard_documentation
post "/dashboard/demo", to: "dashboard#demo", as: :dashboard_demo
post "/dashboard/events/:id/retry", to: "dashboard#retry_event", as: :retry_dashboard_event
get "/dashboard/events/:id", to: "dashboard#show", as: :dashboard_event
post "/webhooks", to: "webhooks#create"
get "/webhooks", to: "webhooks#index"
end
