class CreateUserGoogleCalendarTokens < ActiveRecord::Migration
  def change
    create_table :user_google_calendar_tokens do |t|
      t.integer :user_id
      t.string :refresh_token
      t.string :calendar
      t.text :settings
      t.text :synchronization_result
      t.timestamp :synchronized_at
      t.timestamps
    end
  end
end
