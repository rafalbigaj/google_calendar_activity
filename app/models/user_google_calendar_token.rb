class UserGoogleCalendarToken < ActiveRecord::Base
  unloadable

  belongs_to :user

  validates :user_id, presence: true, :uniqueness => true
  validates :refresh_token, presence: true

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
end
