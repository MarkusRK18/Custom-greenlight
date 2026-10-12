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

module Api
  module V1
    module Admin
      class ServerRoomsController < ApiController
        before_action do
          ensure_authorized('ManageRooms')
        end

        before_action :find_room, only: %i[resync]

        # GET /api/v1/admin/server_rooms.json
        # Fetches only meetings currently running on the server
        def index
          sort_config = config_sorting(allowed_columns: %w[name users.name])

          active_meetings = Array(BigBlueButtonApi.new(provider: current_provider).active_meetings)
                           .select { |meeting| meeting[:running].to_s == 'true' }
          meetings_by_id = active_meetings.index_by { |meeting| meeting[:meetingID] }

          rooms = Room.includes(:user).where(users: { provider: current_provider }, meeting_id: meetings_by_id.keys).order(sort_config)
                      .order('last_session DESC NULLS LAST')&.admin_search(params[:search])

          pagy, paged_rooms = pagy(rooms)

          paged_rooms.each do |room|
            room.online = true
            room.participants = meetings_by_id.fetch(room.meeting_id)[:participantCount]
          end

          render_data data: paged_rooms, meta: pagy_metadata(pagy), serializer: ServerRoomSerializer, status: :ok
        end

        # GET /api/v1/admin/server_rooms/:friendly_id/resync.json
        # Re-syncs a room recordings.
        def resync
          RecordingsSync.new(room: @room, provider: current_provider).call

          render_data status: :ok
        end

        private

        def find_room
          @room = Room.find_by!(friendly_id: params[:friendly_id])
        end
      end
    end
  end
end
