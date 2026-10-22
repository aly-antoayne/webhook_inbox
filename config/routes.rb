Rails.application.routes.draw do
post "/webhooks", to: "webhooks#create"
get "/webhooks", to: "webhooks#index"
end
