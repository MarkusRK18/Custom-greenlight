# frozen_string_literal: true

class MeetingMailer < ApplicationMailer
  layout false
  def scheduled
    @room = params[:room]
    @join_url = "#{params[:base_url]}#{File.join(Rails.configuration.relative_url_root, "rooms")}/#{@room.friendly_id}/join"
    mail(to: params[:email], subject: "Sri Shakthi meeting: #{@room.name}")
  end
end
