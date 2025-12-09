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
      time_min: Time.now.iso8601
    )

    @events = response.items || []
  end
end
