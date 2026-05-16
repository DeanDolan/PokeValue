class SetOverride < ApplicationRecord
  validates :slug, presence: true, uniqueness: true # only one override row can exist per set slug
end
