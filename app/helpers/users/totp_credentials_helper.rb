module Users::TotpCredentialsHelper
  def qr_code_svg(uri)
    RQRCode::QRCode.new(uri).as_svg(
      offset: 0,
      color: "000",
      shape_rendering: "crispEdges",
      module_size: 4,
      standalone: true
    ).html_safe # rubocop:disable Rails/OutputSafety -- verified.
  end
end
