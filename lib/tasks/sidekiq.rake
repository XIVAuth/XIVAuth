desc "Start worker process"
task work: :environment do
  if ENV["DEV_USE_SIDEKIQ"].blank?
    puts "Sidekiq disabled. Set DEV_USE_SIDEKIQ=1 to enable."
    sleep
  end

  require "sidekiq/cli"
  cli = Sidekiq::CLI.instance
  cli.parse
  cli.run
end
