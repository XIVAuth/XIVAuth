# Schema.org email markup (https://developers.google.com/workspace/gmail/markup) so supporting clients can show
# action buttons in the inbox. Emitted into the mailer layout's <head> via `content_for :email_markup`.
module EmailMarkupHelper
  # A one-click action: the client POSTs to +url+ itself, without opening a browser.
  def email_confirm_action(name:, url:, description:)
    email_markup({
      "@type" => "ConfirmAction",
      "name" => name,
      "handler" => { "@type" => "HttpActionHandler", "url" => url }
    }, description)
  end

  # A go-to action: a button that opens +url+ in the browser.
  def email_view_action(name:, url:, description:)
    email_markup({ "@type" => "ViewAction", "name" => name, "url" => url }, description)
  end

  private def email_markup(action, description)
    payload = {
      "@context" => "http://schema.org",
      "@type" => "EmailMessage",
      "potentialAction" => action,
      "description" => description
    }

    # ActiveSupport's JSON encoding escapes <, > and &, so the payload can't close the script tag early.
    content_for(:email_markup, tag.script(payload.to_json.html_safe, type: "application/ld+json"))
  end
end
