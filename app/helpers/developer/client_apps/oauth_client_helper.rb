module Developer::ClientApps::OAuthClientHelper
  def listable_scopes
    scopes = Doorkeeper.configuration.scopes.to_a
    tree = { }

    scopes.each do |scope|
      next if scope.start_with?("internal")

      parts = scope.split(":")
      current = tree
      parts.each_with_index do |_part, idx|
        key = parts[0..idx].join(":")
        current[key] ||= { key: key, children: { } }
        current = current[key][:children]
      end
    end

    # Recursively convert children hashes to arrays
    to_array = lambda do |node|
      node.values.map do |v|
        { key: v[:key], children: to_array.call(v[:children]) }
      end
    end

    to_array.call(tree)
  end
end
