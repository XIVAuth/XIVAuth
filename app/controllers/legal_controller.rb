class LegalController < ApplicationController
  skip_before_action :authenticate_user!

  layout "chroma/container"

  def terms_of_service; end
  def privacy_policy; end
  def developer_agreement; end
  def security_policy; end

  def moderation_policy; end
end
