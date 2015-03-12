class GoogleCalendarTimeEntry < ActiveRecord::Base
  unloadable

  belongs_to :time_entry

  validates :event_id, presence: true, :uniqueness => true
  validates :etag, presence: true
end
