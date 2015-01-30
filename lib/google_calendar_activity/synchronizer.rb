module GoogleCalendarActivity
  class Synchronizer
    unloadable

    def self.calendar(opts={})
      new(opts).calendar
    end

    attr_reader :calendar

    def initialize(opts)
      @calendar ||= Google::Calendar.new(client_id: '210767827009-eu3a73gdhtoptm9d8omf8gq0fipkoe3e.apps.googleusercontent.com',
                                         client_secret: 'haXEgdGXPUD0JBUTBaLykRB4',
                                         calendar: opts.fetch(:calendar, ''),
                                         redirect_url: opts[:redirect_url]
      )
      @refresh_token = opts[:refresh_token]
      @user = opts[:user]
      @mapping = opts[:mapping] || {}
      @logger = opts[:logger] || Logger.new(STDOUT)
    end

    def synchronize(start_date, end_date=nil)
      log_in
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

    def log_in
      unless @logged_in
        @calendar.login_with_refresh_token(@refresh_token)
        @logged_in = true
      end
    end

    def map_title(title)
      title.downcase!
      @mapping.each do |key, value|
        begin
          title[key.downcase] = value
        rescue IndexError
        end
      end
      title
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
          when /\@([a-z0-9\-_]+)/i
            synchronize_project_event $1.downcase, event, start_date, hours
          when /\#([a-z0-9\-_]+)/
            synchronize_issue_event $1.downcase, event, start_date, hours
        end
      end
    end

    def update_existing_event(gc_time_entry, event, start_date, hours)
      if gc_time_entry.etag != event.raw["etag"]
        time_entry = gc_time_entry.time_entry
        time_entry.transaction do
          gc_time_entry.update_attributes!(etag: event.raw["etag"])
          time_entry.update_attributes!(spent_on: start_date,
                                        hours: hours,
                                        comments: event.title)
        end
        @logger.debug "Updated activity on project #{time_entry.project.identifier}: #{hours}h spent on #{start_date}"
      end
    end

    def synchronize_project_event(identifier, event, start_date, hours)
      @projects ||= Project.all
      project = @projects.find { |p| p.identifier == identifier }
      if project
        activities = project.activities(true).all

        create_time_entry! project, nil, event, activities.first, start_date, hours

        @logger.debug "Activity on project #{identifier}: #{hours}h spent on #{start_date}"
      else
        @logger.warn "Project #{identifier} not found for event: '#{event.title}'"
      end
    end

    def synchronize_issue_event(issue_id, event, start_date, hours)
      issue = Issue.find_by_id(issue_id)
      if issue
        project = issue.project
        activities = project.activities(true).all

        create_time_entry! project, issue, event, activities.first, start_date, hours

        @logger.debug "Activity on issue #{issue_id}: #{hours}h spent on #{start_date}"
      else
        @logger.warn "Issue #{issue_id} not found for event: '#{event.title}'"
      end
    end

    def create_time_entry!(project, issue, event, activity, start_date, hours)
      project.transaction do
        time_entry = project.time_entries.create!(issue: issue,
                                                  user: @user,
                                                  activity: activity,
                                                  spent_on: start_date,
                                                  hours: hours,
                                                  comments: event.title)
        GoogleCalendarTimeEntry.create!(time_entry: time_entry, event_id: event.id, etag: event.raw["etag"])
      end
    end
  end
end