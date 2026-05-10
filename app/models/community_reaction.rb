class CommunityReaction < ApplicationRecord
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

  KINDS = REACTIONS.keys.freeze

  belongs_to :community_post
  belongs_to :user

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :user_id, uniqueness: { scope: :community_post_id }

  def self.label_for(kind)
    REACTIONS[kind.to_s]&.fetch(:label, nil) || kind.to_s.humanize
  end

  def self.emoji_for(kind)
    REACTIONS[kind.to_s]&.fetch(:emoji, nil) || "👍"
  end
end
