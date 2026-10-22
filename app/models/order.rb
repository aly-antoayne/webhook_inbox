class Order < ApplicationRecord
  validates :external_id, presence: true, uniqueness: true
  validates :amount_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :currency, inclusion: { in: %w[BRL USD EUR] }
  validates :status, inclusion: { in: %w[pending paid refunded] }
end
