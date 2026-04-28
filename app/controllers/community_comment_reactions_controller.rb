class CommunityCommentReactionsController < ApplicationController
  before_action :require_login

  def create
    comment = CommunityComment.includes(community_comment_reactions: :user).find(params[:id])
    kind = params[:kind].to_s

    unless CommunityCommentReaction::KINDS.include?(kind)
      respond_to do |format|
        format.html { redirect_to community_path(channel: params[:channel].presence || comment.community_post.channel), alert: "Invalid reaction." }
        format.json { render json: { ok: false, message: "Invalid reaction." }, status: :unprocessable_entity }
      end
      return
    end

    reaction = comment.community_comment_reactions.find_or_initialize_by(user_id: current_user.id)

    current_reaction =
      if reaction.persisted? && reaction.kind == kind
        reaction.destroy
        nil
      else
        reaction.kind = kind
        reaction.save!
        kind
      end

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

  def community_comment_reaction_counts(comment)
    counts = CommunityCommentReaction::KINDS.each_with_object({}) { |kind, hash| hash[kind] = 0 }
    comment.community_comment_reactions.group(:kind).count.each do |kind, count|
      counts[kind.to_s] = count.to_i
    end
    counts
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
    badges = []
    badges << "Admin" if user && ((user.respond_to?(:admin?) && user.admin?) || (user.respond_to?(:admin) && user.admin))
    badges
  end
end
