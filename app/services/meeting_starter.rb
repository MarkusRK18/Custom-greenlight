# BigBlueButton open source conferencing system - http://www.bigbluebutton.org/.
#
# Copyright (c) 2022 BigBlueButton Inc. and by respective authors (see below).
#
# This program is free software; you can redistribute it and/or modify it under the
# terms of the GNU Lesser General Public License as published by the Free Software
# Foundation; either version 3.0 of the License, or (at your option) any later
# version.
#
# Greenlight is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
# PARTICULAR PURPOSE. See the GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License along
# with Greenlight; if not, see <http://www.gnu.org/licenses/>.

# frozen_string_literal: true

class MeetingStarter
  include Rails.application.routes.url_helpers

  def initialize(room:, base_url:, current_user:, provider:)
    @room = room
    @current_user = current_user
    @base_url = base_url
    @provider = provider
  end

  def call
    start_settings = RoomSettingsGetter.new(room_id: @room.id, provider: @room.user.provider, current_user: @current_user,
                                            settings: %w[glAnyoneCanStart glRequireAuthentication]).call
    link_start_allowed = start_settings['glAnyoneCanStart'] == 'true' &&
                         (start_settings['glRequireAuthentication'] != 'true' || @current_user.present?)
    raise ArgumentError, 'Meeting cannot be started' unless @room.schedule_open? && (InstitutionPolicy.host?(@current_user) || link_start_allowed)
    options = RoomSettingsGetter.new(room_id: @room.id, provider: @room.user.provider, current_user: @current_user, only_bbb_options: true).call
    viewer_code = RoomSettingsGetter.new(
      room_id: @room.id,
      provider: @room.user.provider,
      current_user: @current_user,
      show_codes: true,
      settings: 'glViewerAccessCode'
    ).call

    options.merge!(computed_options(access_code: viewer_code['glViewerAccessCode']))
    # Preserve the room's recording permission while starting capture as soon as
    # the host creates and joins a recordable meeting.
    if options['record'].to_s == 'true'
      options['autoStartRecording'] = 'true'
      options['allowStartStopRecording'] = 'true'
    end

    retries = 0
    begin
      meeting = BigBlueButtonApi.new(provider: @provider).start_meeting(room: @room, options:, presentation_url:)

      @room.update!(online: true, last_session: DateTime.strptime(meeting[:createTime].to_s, '%Q'))

      ActionCable.server.broadcast "#{@room.friendly_id}_rooms_channel", 'started'
    rescue BigBlueButton::BigBlueButtonException => e
      retries += 1
      retry if retries < 3 && e.key != 'idNotUnique'
      raise e
    end
  end

  private

  def computed_options(access_code:)
    room_url = "#{root_url(host: @base_url)}rooms/#{@room.friendly_id}/join"
    moderator_message = "#{I18n.t('meeting.moderator_message')}<br>#{room_url}"
    moderator_message += "<br>#{I18n.t('meeting.access_code', code: access_code)}" if access_code.present?
    {
      moderatorOnlyMessage: moderator_message,
      logo: ENV.fetch('BBB_BRANDING_LOGO_URL', "#{@base_url}#{File.join(Rails.configuration.relative_url_root, "sri-shakthi-logo.png")}"),
      bannerText: '',
      copyright: 'Sri Shakthi',
      welcome: 'Welcome to SIETConnect',
      # Native live captions: browser speech recognition, no paid API credentials.
      disabledFeaturesExclude: 'liveTranscription',
      clientSettingsOverride: {
        public: { app: { audioCaptions: {
          enabled: true, alwaysVisible: true, mobile: true, provider: 'webspeech',
          language: { available: ['en-US'], locale: 'en-US', defaultSelectLocale: true, forceLocale: false }
        } } }
      }.to_json,
      multiUserWhiteboardEnabled: false,
      duration: @room.duration_minutes.zero? ? 0 : [((@room.scheduled_at + @room.duration_minutes.minutes - Time.current) / 60).ceil, 1].max,
      meetingExpireWhenLastUserLeftInMinutes: 1,
      meetingExpireIfNoUserJoinedInMinutes: 1,
      keepEvents: true,
      'meta_analytics-callback-url': analytics_callback_url(host: ENV.fetch('BBB_CALLBACK_BASE_URL', @base_url)),
      logoutURL: room_url,
      meta_endCallbackUrl: meeting_ended_url(host: ENV.fetch('BBB_CALLBACK_BASE_URL', @base_url)),
      'meta_bbb-recording-ready-url': recording_ready_url(host: ENV.fetch('BBB_CALLBACK_BASE_URL', @base_url)),
      'meta_bbb-origin-version': ENV.fetch('VERSION_TAG', 'v3'),
      'meta_bbb-origin': 'greenlight'
    }
  end

  def presentation_url
    return unless @room.presentation.attached?

    rails_blob_url(@room.presentation, host: ENV.fetch('BBB_CALLBACK_BASE_URL', @base_url)).gsub('&', '%26')
  end
end
