class CommunityReaction < ApplicationRecord
  # Defines the reaction options shown in the community section
  REACTIONS = {
    "like" => { emoji: "👍", label: "Like" },
    "love" => { emoji: "❤️", label: "Love" },
    "haha" => { emoji: "😂", label: "Haha" },
    "smile" => { emoji: "😊", label: "Smile" },
    "money_face" => { emoji: "🤑", label: "Money Face" },
    "fire" => { emoji: "🔥", label: "Fire" },
    "skull" => { emoji: "💀", label: "Skull" },
    "handshake" => { emoji: "🤝", label: "Handshake" },
    "wow" => { emoji: "😮", label: "Wow" },
    "sad" => { emoji: "😢", label: "Sad" },
    "angry" => { emoji: "😡", label: "Angry" }
  }.freeze

  # Stores the allowed reaction keys for validation
  KINDS = REACTIONS.keys.freeze

  # Each reaction belongs to one post and one user
  belongs_to :community_post
  belongs_to :user

  # Makes sure only approved reaction types can be saved
  validates :kind, presence: true, inclusion: { in: KINDS }

  # Stops the same user from reacting more than once to the same post
  validates :user_id, uniqueness: { scope: :community_post_id }

  # Returns the readable label for a reaction
  def self.label_for(kind)
    REACTIONS[kind.to_s]&.fetch(:label, nil) || kind.to_s.humanize
  end

  # Returns the emoji for a reaction
  def self.emoji_for(kind)
    REACTIONS[kind.to_s]&.fetch(:emoji, nil) || "👍"
  end
end
