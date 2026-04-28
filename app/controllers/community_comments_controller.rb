class CommunityCommentsController < ApplicationController
  before_action :require_login
  before_action :set_community_post

  def create
    @community_comment = @community_post.community_comments.new(body: community_comment_params[:body])
    @community_comment.user = current_user

    parent_comment_id = community_comment_params[:parent_comment_id].presence

    if parent_comment_id.present?
      parent_comment = @community_post.community_comments.find_by(id: parent_comment_id)
      if parent_comment.present?
        parent_comment = parent_comment.parent_comment if parent_comment.parent_comment.present?
        @community_comment.parent_comment = parent_comment
      end
    end

    if @community_comment.save
      redirect_to community_path(channel: params[:channel].presence || @community_post.channel, anchor: dom_id_for(@community_post)), notice: "Comment added."
    else
      redirect_to community_path(channel: params[:channel].presence || @community_post.channel, anchor: dom_id_for(@community_post)), alert: @community_comment.errors.full_messages.to_sentence
    end
  end

  private

  def set_community_post
    @community_post = CommunityPost.find(params[:community_post_id])
  end

  def community_comment_params
    params.require(:community_comment).permit(:body, :parent_comment_id)
  end

  def require_login
    return if current_user.present?
    redirect_to community_path(channel: params[:channel].presence || CommunityPost::CHANNELS.first), alert: "You must be logged in to do that."
  end

  def dom_id_for(post)
    "community-post-#{post.id}"
  end
end
