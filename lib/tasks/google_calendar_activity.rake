namespace :google_calendar do
  desc 'Create Google OAuth configuration file'
  task :oauth_config => :environment do
    oauth_path = GoogleCalendarActivity::Synchronizer::OAUTH_CONFIG_PATH
    puts "Enter Google API client ID"
    client_id = STDIN.gets.chomp
    puts "Enter client secret"
    client_secret = STDIN.gets.chomp
    File.binwrite(oauth_path, YAML.dump(client_id: client_id, client_secret: client_secret))
  end

  desc 'Synchronize activity with Google Calendar entries'
  task :synchronize => :environment do
    UserGoogleCalendarToken.all.each do |token|
      io = StringIO.new
      logger = Logger.new(io)
      logger.level = Logger::DEBUG
      logger.formatter = lambda {|severity, _, _, msg| "[#{severity[0..0]}] #{msg}\n" }
      synchronizer = GoogleCalendarActivity::Synchronizer.new(user: token.user,
                                                              calendar: token.calendar,
                                                              refresh_token: token.refresh_token,
                                                              mapping: token.mappings,
                                                              force: ENV['FORCE'],
                                                              logger: logger)
      ndays = ENV['DAYS'].to_i
      ndays = 14 if ndays == 0
      synchronizer.synchronize(Time.now - ndays.days)
      result = io.string.chomp
      unless result.empty?
        puts result
        lines = ["Synchronized at #{Time.now}"]
        lines += (result.lines.reverse + token.synchronization_result.to_s.lines).map(&:chomp).reject(&:blank?)[0..100]
        token.update_attributes! synchronization_result: lines.join("\n"), synchronized_at: Time.now
      end
    end
  end
end
