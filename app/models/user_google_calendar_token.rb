class UserGoogleCalendarToken < ActiveRecord::Base
  unloadable

  belongs_to :user

  validates :user_id, presence: true, :uniqueness => true
  validates :refresh_token, presence: true
  validates :time_range, presence: true, :inclusion => { :in => 1..31 }

  def mappings
    self.settings.to_s.lines.inject({}) do |hash, line|
      if line =~ /^([^:]+): (.+)$/
        key = $1.chomp
        value = $2.chomp
        hash[key] = value
        hash
      end
    end
  end

	def synchronize!(force=false, debug=true, verbose=false, time_range=nil)
		io = StringIO.new
		logger = Logger.new(io)
		logger.level = debug ? Logger::DEBUG : Logger::INFO
		logger.formatter = lambda {|severity, _, _, msg| "[#{severity[0..0]}] #{msg}\n" }
		synchronizer = GoogleCalendarActivity::Synchronizer.new(user: self.user,
		                                                        calendar: self.calendar,
		                                                        refresh_token: self.refresh_token,
		                                                        mapping: self.mappings,
		                                                        force: force,
		                                                        logger: logger)
		ndays = time_range ? time_range : self.time_range
		synchronizer.synchronize(Time.now - ndays.days)
		result = io.string.chomp
		unless result.empty?
			puts result if verbose
			lines = ["Synchronized at #{Time.now}"] + result.lines.reverse + ['-'*80]
			append_synchronization_result! lines
		end
	rescue
		lines = ["Synchronized FAILED at #{Time.now}", $!.message, '-'*80]
		Rails.logger.error $!.message
		Rails.logger.error $!.backtrace.join("\n")
		if verbose
			puts lines
			puts $!.backtrace
		end
		append_synchronization_result! lines
	end

	def append_synchronization_result!(lines)
		lines = Array(lines)
		lines += self.synchronization_result.to_s.lines
		lines = lines.map(&:chomp).reject(&:blank?)[0..100]
		self.update_attributes! synchronization_result: lines.join("\n"), synchronized_at: Time.now
	end
end
