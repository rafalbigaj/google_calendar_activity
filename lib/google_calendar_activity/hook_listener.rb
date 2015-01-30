module GoogleCalendarActivity
  class HookListener < Redmine::Hook::ViewListener
    render_on :view_my_account_preferences, :partial => "google_calendar_activity/account_preferences"
  end
end