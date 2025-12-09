class PagesController < ApplicationController
  before_action :authenticate_user!

  def home
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = current_user.google_access_token

    response = service.list_events(
      "primary",
      max_results: 10,
      single_events: true,
      order_by: "startTime",
      time_min: Time.current.iso8601
    )

    @events = response.items || []
  rescue Google::Apis::ClientError, Google::Apis::AuthorizationError
    sign_out current_user
    redirect_to new_user_session_path,
      alert: "We need permission to access your calendar. Please sign in again."
  end
end
