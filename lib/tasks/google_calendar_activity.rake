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
	    token.synchronize!(ENV['FORCE'], true, true, ENV['DAYS'])
    end
  end
end
