class UserGoogleCalendarToken < ActiveRecord::Base
  unloadable

  belongs_to :user

  serialize :settings

  validates :user_id, presence: true, :uniqueness => true
  validates :refresh_token, presence: true

  after_validation do
    object = YAML.load(self.settings) # check YAML
    self.errors.add :settings, "must be a hash" unless object.is_a?(Hash)
  end
end
