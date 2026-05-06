class CommunityPostsController < ApplicationController
  before_action :require_login
  before_action :set_community_post, only: [ :update, :destroy ]

  # Creates a new community post in the selected channel.
  def create
    permitted_params = community_post_params
    @community_post = current_user.community_posts.new(permitted_params)

    if @community_post.save
      redirect_to community_path(channel: @community_post.channel, anchor: dom_id_for(@community_post)), notice: "Post created."
    else
      redirect_to community_path(channel: permitted_params[:channel].presence || CommunityPost::CHANNELS.first), alert: @community_post.errors.full_messages.to_sentence
    end
  end

  # Updates a post when the current user owns it or has admin permission.
  def update
    unless @community_post.user_id == current_user.id || current_user.admin?
      return redirect_to community_path(channel: params[:channel].presence || @community_post.channel, anchor: dom_id_for(@community_post)), alert: "You cannot edit that post."
    end

    permitted_params = community_post_update_params
    channel = params[:channel].presence || permitted_params[:channel].presence || @community_post.channel

    if @community_post.update(permitted_params)
      redirect_to community_path(channel: @community_post.channel, anchor: dom_id_for(@community_post)), notice: "Post updated."
    else
      redirect_to community_path(channel: channel, anchor: dom_id_for(@community_post)), alert: @community_post.errors.full_messages.to_sentence
    end
  end

  # Deletes a post when the current user owns it or has admin permission.
  def destroy
    unless @community_post.user_id == current_user.id || current_user.admin?
      return redirect_to community_path(channel: params[:channel].presence || @community_post.channel, anchor: dom_id_for(@community_post)), alert: "You cannot delete that post."
    end

    channel = params[:channel].presence || @community_post.channel
    @community_post.destroy
    redirect_to community_path(channel: channel), notice: "Post deleted."
  end

  private

  # Loads the post for actions that need an existing community post.
  def set_community_post
    @community_post = CommunityPost.find(params[:id])
  end

  # Allows the post channel, body, and uploaded images.
  def community_post_params
    params.require(:community_post).permit(:channel, :body, images: [])
  end

  # Allows editing the post text and channel without replacing existing images.
  def community_post_update_params
    params.require(:community_post).permit(:channel, :body)
  end

  # Only logged-in users can create, edit or delete community posts.
  def require_login
    return if current_user.present?
    redirect_to community_path(channel: params.dig(:community_post, :channel).presence || params[:channel].presence || CommunityPost::CHANNELS.first), alert: "You must be logged in to do that."
  end

  # Keeps redirects anchored to the post that was created or checked.
  def dom_id_for(post)
    "community-post-#{post.id}"
  end
end
