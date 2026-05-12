module ErrorsHelper
  def link_to_safety
    if request.referer && URI(request.referer).host == request.host
      request.referer
    else
      root_path
    end
  end
end
