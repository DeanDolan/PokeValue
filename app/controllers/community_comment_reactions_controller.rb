class CommunityCommentReactionsController < ApplicationController
  before_action :require_login

  def create
    comment = CommunityComment.includes(community_comment_reactions: :user).find(params[:id])
    kind = params[:kind].to_s

    return invalid_reaction_response(comment.community_post.channel) unless CommunityCommentReaction::KINDS.include?(kind)

    reaction = comment.community_comment_reactions.find_or_initialize_by(user_id: current_user.id)
    current_reaction = update_reaction(reaction, kind)
    comment.reload

    respond_to do |format|
      format.html { redirect_to community_path(channel: params[:channel].presence || comment.community_post.channel, anchor: "community-post-#{comment.community_post_id}") }
      format.json do
        render json: {
          ok: true,
          comment_id: comment.id,
          counts: community_comment_reaction_counts(comment),
          total_reactions: comment.community_comment_reactions.count,
          current_reaction: current_reaction,
          reactors: community_comment_reactors(comment)
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

  def community_comment_reaction_counts(comment)
    CommunityCommentReaction::KINDS.index_with { 0 }.merge(comment.community_comment_reactions.group(:kind).count.transform_values(&:to_i))
  end

  def community_comment_reactors(comment)
    comment.community_comment_reactions.includes(:user).order(created_at: :desc).map do |reaction|
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
