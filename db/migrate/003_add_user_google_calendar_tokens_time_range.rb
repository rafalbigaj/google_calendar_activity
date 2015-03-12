class AddUserGoogleCalendarTokensTimeRange < ActiveRecord::Migration
  def change
	  add_column :user_google_calendar_tokens, :time_range, :integer, default: 14
  end
end
