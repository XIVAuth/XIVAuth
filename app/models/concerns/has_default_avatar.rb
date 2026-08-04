module HasDefaultAvatar
  extend ActiveSupport::Concern

  class_methods do
    # Declares that +name+ (an attachment declared via has_upload_attachment) should
    # be backed by a generated Dicebear avatar when nothing was uploaded on create.
    #
    # Defines default_<name>_url, used both as the presentational fallback and as
    # the source the background job fetches from. Preserves any icon uploaded as
    # part of the create request.
    #
    # Options:
    #   seed:    Attribute name or proc (instance_exec'd) providing the Dicebear seed.
    #            Defaults to :name.
    #   style:   Dicebear sprite style (e.g. "initials", "identicon", "shapes").
    #            Defaults to "initials".
    #   **options: Any other Dicebear query parameter (e.g. backgroundType:,
    #            backgroundColor:, radius:). Array values are comma-joined, as
    #            Dicebear expects. Proc values are instance_exec'd.
    #
    # See https://www.dicebear.com/styles/ for the parameters each style supports.
    def generate_default_avatar(name, seed: :id, style: "initials", **options)
      define_method(:"default_#{name}_url") do
        seed_value = seed.respond_to?(:call) ? instance_exec(&seed) : public_send(seed)

        params = { seed: seed_value }.merge(options).transform_values do |value|
          value = instance_exec(&value) if value.respond_to?(:call)
          value.is_a?(Array) ? value.join(",") : value
        end

        "https://api.dicebear.com/10.x/#{style}/png?#{URI.encode_www_form(params)}"
      end

      after_create_commit do
        next if public_send(name).present?

        Attachment::GenerateDefaultAvatarJob.perform_later(self.class.name, id, name.to_s)
      end
    end
  end
end
