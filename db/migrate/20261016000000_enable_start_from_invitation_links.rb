# frozen_string_literal: true

class EnableStartFromInvitationLinks < ActiveRecord::Migration[7.0]
  def up
    option = MeetingOption.find_by!(name: 'glAnyoneCanStart')
    option.update!(default_value: 'true')
    RoomMeetingOption.where(meeting_option_id: option.id).update_all(value: 'true')
    RoomsConfiguration.where(meeting_option_id: option.id).update_all(value: 'default_enabled')
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
