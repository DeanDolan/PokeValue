class SetOverride < ApplicationRecord
  validates :slug, presence: true, uniqueness: true
end
