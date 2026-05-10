class CommunityReactionsController < ApplicationController
  before_action :require_login

  def create
    post = CommunityPost.includes(community_reactions: :user).find(params[:id])
    kind = params[:kind].to_s

    return invalid_reaction_response(post.channel) unless CommunityReaction::KINDS.include?(kind)

    reaction = post.community_reactions.find_or_initialize_by(user_id: current_user.id)
    current_reaction = update_reaction(reaction, kind)
    post.reload

    respond_to do |format|
      format.html { redirect_to community_path(channel: params[:channel].presence || post.channel, anchor: "community-post-#{post.id}") }
      format.json do
        render json: {
          ok: true,
          post_id: post.id,
          counts: community_reaction_counts(post),
          total_reactions: post.community_reactions.count,
          current_reaction: current_reaction,
          reactors: community_reactors(post)
        }
      end
    end
  end

  private

  def require_login
    return if current_user.present?

    respond_to do |format|
      format.html { redirect_to community_path(channel: params[:channel].presence || CommunityPost::CHANNELS.first), alert: "You must be logged in to do that." }
      format.json { render json: { ok: false, message: "You must be logged in to do that." }, status: :unauthorized }
    end
  end

  def invalid_reaction_response(channel)
    respond_to do |format|
      format.html { redirect_to community_path(channel: params[:channel].presence || channel), alert: "Invalid reaction." }
      format.json { render json: { ok: false, message: "Invalid reaction." }, status: :unprocessable_entity }
    end
  end

  def update_reaction(reaction, kind)
    return reaction.destroy && nil if reaction.persisted? && reaction.kind == kind

    reaction.update!(kind: kind)
    kind
  end

  def community_reaction_counts(post)
    CommunityReaction::KINDS.index_with { 0 }.merge(post.community_reactions.group(:kind).count.transform_values(&:to_i))
  end

  def community_reactors(post)
    post.community_reactions.includes(:user).order(created_at: :desc).map do |reaction|
      user = reaction.user
      {
        username: user.username.to_s,
        country_code: user.respond_to?(:country_code) ? user.country_code.to_s : "",
        badges: community_user_badges_for(user),
        kind: reaction.kind.to_s
      }
    end
  end

  def community_user_badges_for(user)
    user && ((user.respond_to?(:admin?) && user.admin?) || (user.respond_to?(:admin) && user.admin)) ? [ "Admin" ] : []
  end
end
