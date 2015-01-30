class CreateGoogleCalendarTimeEntries < ActiveRecord::Migration
  def change
    create_table :google_calendar_time_entries do |t|
      t.references :time_entry
      t.string :event_id
      t.string :etag
    end
    add_index "google_calendar_time_entries", ["event_id"], :name => "index_gc_time_entries_on_event_id"
  end
end
