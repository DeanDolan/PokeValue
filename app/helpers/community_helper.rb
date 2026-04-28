module CommunityHelper
  def community_flag_emoji(country_code)
    code = country_code.to_s.upcase
    return "" unless code.match?(/\A[A-Z]{2}\z/)
    code.chars.map { |char| (127397 + char.ord).chr(Encoding::UTF_8) }.join
  end

  def community_user_badges(user)
    badges = []
    badges << "Admin" if user.respond_to?(:admin?) && user.admin?

    if user.respond_to?(:badge_list) && user.badge_list.present?
      badges.concat(Array(user.badge_list))
    elsif user.respond_to?(:badges) && user.badges.present?
      badges.concat(Array(user.badges))
    end

    badges.map { |badge| badge.to_s.strip }.reject(&:blank?).uniq
  end

  def community_reaction_counts(post)
    post.community_reactions.group_by(&:kind).transform_values(&:size)
  end

  def community_total_reactions(post)
    community_reaction_counts(post).values.sum
  end

  def community_comment_reaction_counts(comment)
    comment.community_comment_reactions.group_by(&:kind).transform_values(&:size)
  end

  def community_total_comment_reactions(comment)
    community_comment_reaction_counts(comment).values.sum
  end
end
