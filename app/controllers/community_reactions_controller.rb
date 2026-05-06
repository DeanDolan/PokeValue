class CommunityReactionsController < ApplicationController
  before_action :require_login

  # Creates, changes, or removes a reaction on a community post.
  def create
    post = CommunityPost.includes(community_reactions: :user).find(params[:id])
    kind = params[:kind].to_s

    # Stops reaction values outside the approved list.
    unless CommunityReaction::KINDS.include?(kind)
      respond_to do |format|
        format.html { redirect_to community_path(channel: params[:channel].presence || post.channel), alert: "Invalid reaction." }
        format.json { render json: { ok: false, message: "Invalid reaction." }, status: :unprocessable_entity }
      end
      return
    end

    # Each user can only have one current reaction per post.
    reaction = post.community_reactions.find_or_initialize_by(user_id: current_user.id)

    # Clicking the same reaction again removes it. Clicking a different reaction updates it.
    current_reaction =
      if reaction.persisted? && reaction.kind == kind
        reaction.destroy
        nil
      else
        reaction.kind = kind
        reaction.save!
        kind
      end

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

  # Reactions require a logged-in user.
  def require_login
    return if current_user.present?

    respond_to do |format|
      format.html { redirect_to community_path(channel: params[:channel].presence || CommunityPost::CHANNELS.first), alert: "You must be logged in to do that." }
      format.json { render json: { ok: false, message: "You must be logged in to do that." }, status: :unauthorized }
    end
  end

  # Returns a count for every allowed reaction kind, including kinds with zero reactions.
  def community_reaction_counts(post)
    counts = CommunityReaction::KINDS.each_with_object({}) { |kind, hash| hash[kind] = 0 }
    post.community_reactions.group(:kind).count.each do |kind, count|
      counts[kind.to_s] = count.to_i
    end
    counts
  end

  # Builds the reaction hover/list data used by the frontend.
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

  # Adds profile badges beside users who reacted.
  def community_user_badges_for(user)
    badges = []
    badges << "Admin" if user && ((user.respond_to?(:admin?) && user.admin?) || (user.respond_to?(:admin) && user.admin))
    badges
  end
end
