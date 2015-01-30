module GoogleCalendarActivity
  class Synchronizer
    unloadable

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
    end

    def synchronize(start_date, end_date=nil)
      log_in
      load_models
      end_date ||= Time.now
      events = @calendar.find_events_in_range(start_date, end_date, max_results: 500)
      events.each do |event|
        synchronize_event event
      end
    end

    def connected?
      log_in
      !!@calendar.find_events_in_range(Time.now-14.days, Time.now, max_results: 1)[0]
    rescue
      false
    end

    protected

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
          title[key.to_s.downcase] = value.to_s
        rescue IndexError
        end
      end
      title
    end

    def find_activity(title)
      title = map_title(title)
      @activities.each_value do |activity|
        return activity if title.include?("[#{activity.name}]")
      end
      @default_activity
    end

    def synchronize_event(event)
      start_date = Time.parse(event.start_time).to_date
      hours = event.duration.to_f / 1.hour
      gc_time_entry = GoogleCalendarTimeEntry.where(event_id: event.id).first
      if gc_time_entry
        update_existing_event gc_time_entry, event, start_date, hours
      else
        title = map_title(event.title)
        case title
          when /^\$/
            # ignore events starting with $ (already logged)
          when /\@([a-z0-9\-_]+)/i
            synchronize_project_event $1.downcase, event, start_date, hours
          when /\#([a-z0-9\-_]+)/
            synchronize_issue_event $1.downcase, event, start_date, hours
        end
      end
    end

    def update_existing_event(gc_time_entry, event, start_date, hours)
      if @force_update || gc_time_entry.etag != event.raw["etag"]
        time_entry = gc_time_entry.time_entry
        time_entry.transaction do
          gc_time_entry.update_attributes!(etag: event.raw["etag"])
          activity = find_activity(event.title)
          time_entry.update_attributes!(spent_on: start_date,
                                        hours: hours,
                                        activity: activity,
                                        comments: event.title)
        end
        @logger.debug "Updated activity on project #{time_entry.project.identifier}: #{hours}h spent on #{start_date}"
      end
    end

    def synchronize_project_event(identifier, event, start_date, hours)
      project = @projects[identifier]
      if project
        create_time_entry! project, nil, event, start_date, hours

        @logger.debug "Activity on project #{identifier}: #{hours}h spent on #{start_date}"
      else
        @logger.warn "Project #{identifier} not found for event: '#{event.title}'"
      end
    end

    def synchronize_issue_event(issue_id, event, start_date, hours)
      issue = Issue.find_by_id(issue_id)
      if issue
        project = issue.project

        create_time_entry! project, issue, event, start_date, hours

        @logger.debug "Activity on issue #{issue_id}: #{hours}h spent on #{start_date}"
      else
        @logger.warn "Issue #{issue_id} not found for event: '#{event.title}'"
      end
    end

    def create_time_entry!(project, issue, event, start_date, hours)
      project.transaction do
        activity = find_activity(event.title)
        time_entry = project.time_entries.create!(issue: issue,
                                                  user: @user,
                                                  activity: activity,
                                                  spent_on: start_date,
                                                  hours: hours,
                                                  comments: event.title)
        GoogleCalendarTimeEntry.create!(time_entry: time_entry, event_id: event.id, etag: event.raw["etag"])
        unless event.title =~ / \*$/
          event.title += ' *' # mark as logged
          event.save
        end
      end
    end
  end
end