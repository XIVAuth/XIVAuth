class DebugController < Admin::AdminController
  def generate_exception
    raise "The exception you asked for."
  end
end
