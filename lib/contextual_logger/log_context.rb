module LogContext
  def self.add(**args)
    idx, existing = self.find_mdc

    if idx.present?
      Thread.current[:semantic_logger_named_tags][idx][:_mdc] = existing.deep_merge(args.deep_symbolize_keys)
    else
      (Thread.current[:semantic_logger_named_tags] ||= []) << { _mdc: args.deep_symbolize_keys }
    end
  end

  def self.clear
    Thread.current[:semantic_logger_named_tags]&.delete_if { |t| t.key?(:_mdc) }
  end

  def self.get
    _, existing = find_mdc

    return existing
  end

  def self.find_mdc
    tags = Thread.current[:semantic_logger_named_tags] || []
    idx = tags.find_index { |t| t[:_mdc].present? }

    [idx, idx.present? ? tags[idx][:_mdc] : { }]
  end
end
