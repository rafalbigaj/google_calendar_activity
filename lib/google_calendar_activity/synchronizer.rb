module GoogleCalendarActivity
  class Synchronizer
    unloadable

    class UrlHelper
	    include Rails.application.routes.url_helpers

	    def self.default_url_options
		    { :host => Setting.host_name, :protocol => Setting.protocol }
	    end
    end

    def self.calendar(opts={})
      new(opts).calendar
    end

    attr_reader :calendar

    OAUTH_CONFIG_PATH = File.expand_path('../../../config/oauth.yml', __FILE__)

    def initialize(opts)
      oauth_config = load_oauth_config
      raise "Run 'rake google_calendar:oauth_config' first" unless oauth_config
      @calendar ||= Google::Calendar.new(client_id: oauth_config[:client_id],
                                         client_secret: oauth_config[:client_secret],
                                         calendar: opts.fetch(:calendar, ''),
                                         redirect_url: opts[:redirect_url]
      )
      @refresh_token = opts[:refresh_token]
      @user = opts[:user]
      @mapping = opts[:mapping] || {}
      @logger = opts[:logger] || Logger.new(STDOUT)
      @force_update = opts[:force]
      @url_helper = UrlHelper.new
    end

    def synchronize(start_date, end_date=nil)
      log_in
      load_models
      end_date ||= Time.now
      events = @calendar.find_events_in_range(start_date, end_date, max_results: 500)
      events.each do |event|
        synchronize_event event
      end if events
			remove_absent_events start_date, end_date, events.map(&:id)
    end

    def connected?
      log_in
      !!@calendar.find_events_in_range(Time.now-14.days, Time.now, max_results: 1)[0]
    rescue
      false
    end

    protected

    def remove_absent_events start_date, end_date, existing_ids
	    GoogleCalendarTimeEntry.
	        includes(:time_entry).
	        joins(:time_entry).
			    where('event_id NOT IN(?)', existing_ids).
					where('time_entries.spent_on BETWEEN ? AND ?', start_date, end_date).each do |gc_entry|

		    time_entry = gc_entry.time_entry
		    @logger.debug "Removing activity '#{time_entry.comments}' spent on #{time_entry.spent_on}"

		    gc_entry.transaction do
		      gc_entry.destroy
		      time_entry.destroy
		    end

	    end
    end

    def load_oauth_config
      if File.exists?(OAUTH_CONFIG_PATH)
        config = File.binread(OAUTH_CONFIG_PATH)
        YAML.load(config) rescue nil
      end
    end

    def log_in
      unless @logged_in
        @calendar.login_with_refresh_token(@refresh_token)
        @logged_in = true
      end
    end

    def load_models
      @activities = TimeEntryActivity.all.inject({}) {|h, a| h[a.name] = a; h }
      @default_activity = @activities.values.find(&:is_default?) || @activities.values.first
      @projects = Project.all.inject({}) {|h, p| h[p.identifier] = p; h }
    end

    def map_title(title)
      title = title.downcase
      @mapping.each do |key, value|
        begin
					if key =~ /^[@#]/
						# replace whole words for identifiers
						title.sub!(/(^|[^\w])#{Regexp.escape(key)}([^\w]|$)/i, "\1#{value}\2")
          else
						title[key.to_s.downcase] = value.to_s
					end
        rescue IndexError
        end
      end
      title
    end

    def find_activity(title, use_default=true)
      @activities.each_value do |activity|
        return activity if title.include?("[#{activity.name.downcase}]")
      end
      use_default ? @default_activity : nil
    end

    def synchronize_event(event)
      start_date = Time.parse(event.start_time).to_date
      hours = event.duration.to_f / 1.hour
      title = map_title(event.title)
      project, issue = find_project_and_issue(title)
      gc_time_entry = GoogleCalendarTimeEntry.where(event_id: event.id).first

      if gc_time_entry
        update_existing_event project, issue, title, gc_time_entry, event, start_date, hours
      elsif project
	      synchronize_new_event project, issue, title, event, start_date, hours
      else
	      @logger.debug "Unrecognized activity: #{title}"
      end
    end

    def update_existing_event(project, issue, title, gc_time_entry, event, start_date, hours)
      if @force_update || gc_time_entry.etag != event.raw["etag"]
        time_entry = gc_time_entry.time_entry
        time_entry.transaction do
          gc_time_entry.update_attributes!(etag: event.raw["etag"])
          activity = find_activity(title, false)
          title = filter_comment(event.title)

          attributes = {
		          spent_on: start_date,
		          hours: hours
          }

          # do not overwrite attributes if not present
          attributes[:project] = project if project
          attributes[:issue] = issue if issue
          attributes[:activity] = activity if activity
          attributes[:comments] = title unless title.blank?

          time_entry.update_attributes!(attributes)

          update_google_event event, time_entry
        end
        @logger.debug "Updated activity on project #{time_entry.project.name}: #{hours}h spent on #{start_date}"
      end
    end

    def synchronize_new_event(project, issue, title, event, start_date, hours)
	    create_time_entry! project, issue, title, event, start_date, hours
	    if issue
		    @logger.debug "Activity on issue #{issue.id}: #{hours}h spent on #{start_date}"
	    else
		    @logger.debug "Activity on project #{project.name}: #{hours}h spent on #{start_date}"
	    end
    end

    def create_time_entry!(project, issue, title, event, start_date, hours)
      project.transaction do
        activity = find_activity(title)
        comment = filter_comment(event.title) # use original title

        time_entry = project.time_entries.create!(issue: issue,
                                                  user: @user,
                                                  activity: activity,
                                                  spent_on: start_date,
                                                  hours: hours,
                                                  comments: comment)

        GoogleCalendarTimeEntry.create!(time_entry: time_entry, event_id: event.id, etag: event.raw["etag"])

				update_google_event event, time_entry
      end
    end

    def update_google_event(event, time_entry)
			changed = false
	    unless event.title =~ /\*$/
		    event.title += ' *' # mark as logged
				changed = true
	    end

			unless event.description
				event.description = "Redmine activity: #{@url_helper.edit_time_entry_url(time_entry)}"
				changed = true
			end

			event.save if changed

    rescue
	    @logger.error "Unable to update calendar event title or description (#{event.start_time}): #{$!}"
    end

    def find_project_and_issue(title)
	    case title
		    when /^\$/
			    # ignore events starting with $ (already logged)
		    when /\#([a-z0-9\-_]+)/
					issue_id = $1.to_s
			    issue = Issue.find_by_id(issue_id)
			    @logger.warn "Issue #{issue_id} not found for event: '#{title}'" unless issue
			    [issue ? issue.project : nil, issue]
		    when /\@([a-z0-9\-_]+)/i
			    identifier = $1.downcase
			    project = @projects[identifier]
			    @logger.warn "Project #{identifier} not found for event: '#{title}'" unless project
			    [project, nil]
	    end
    end

    TITLE_FILTER = [
		    / ?\*$/,         # ending '*' (added to logged events)
		    / ?\[[^\]]+\]/,  # activity tag ex. [dev]
        / ?\#\w+/,       # issue id ex. #1234
        / ?\@\w+/,       # project id ex. @project
        /^ +/,           # spaces from the beginning
    ]

		def filter_comment(title)
			TITLE_FILTER.inject(title) {|t, filter| t.gsub(filter, '') }
		end
  end
end