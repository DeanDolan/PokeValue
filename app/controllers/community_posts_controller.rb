class CommunityPostsController < ApplicationController
  before_action :require_login
  before_action :set_community_post, only: [ :update, :destroy ]

  def create
    @community_post = current_user.community_posts.new(community_post_params)

    if @community_post.save
      redirect_to community_path(channel: @community_post.channel, anchor: dom_id_for(@community_post)), notice: "Post created."
    else
      redirect_to community_path(channel: community_post_params[:channel].presence || CommunityPost::CHANNELS.first), alert: @community_post.errors.full_messages.to_sentence
    end
  end

  def update
    return redirect_to community_path(channel: params[:channel].presence || @community_post.channel, anchor: dom_id_for(@community_post)), alert: "You cannot edit that post." unless can_manage_post?

    if @community_post.update(community_post_update_params)
      redirect_to community_path(channel: @community_post.channel, anchor: dom_id_for(@community_post)), notice: "Post updated."
    else
      redirect_to community_path(channel: params[:channel].presence || @community_post.channel, anchor: dom_id_for(@community_post)), alert: @community_post.errors.full_messages.to_sentence
    end
  end

  def destroy
    return redirect_to community_path(channel: params[:channel].presence || @community_post.channel, anchor: dom_id_for(@community_post)), alert: "You cannot delete that post." unless can_manage_post?

    channel = params[:channel].presence || @community_post.channel
    @community_post.destroy
    redirect_to community_path(channel: channel), notice: "Post deleted."
  end

  private

  def set_community_post
    @community_post = CommunityPost.find(params[:id])
  end

  def can_manage_post?
    @community_post.user_id == current_user.id || current_user.admin?
  end

  def community_post_params
    params.require(:community_post).permit(:channel, :body)
  end

  def community_post_update_params
    params.require(:community_post).permit(:channel, :body)
  end

  def require_login
    return if current_user.present?

    redirect_to community_path(channel: params.dig(:community_post, :channel).presence || params[:channel].presence || CommunityPost::CHANNELS.first), alert: "You must be logged in to do that."
  end

  def dom_id_for(post)
    "community-post-#{post.id}"
  end
end
