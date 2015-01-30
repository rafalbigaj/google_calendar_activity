# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

scope 'users/:user_id' do
  resource :user_google_calendar_token, only: [:show, :update]
end
get 'google_calendar_oauth2', to: "user_google_calendar_tokens#create", as: :google_calendar_oauth2