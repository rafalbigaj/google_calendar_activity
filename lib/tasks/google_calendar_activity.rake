namespace :google_calendar do
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
      synchronizer.synchronize(Time.now - 14.days)
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
