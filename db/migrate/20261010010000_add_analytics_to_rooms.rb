# frozen_string_literal: true

class AddAnalyticsToRooms < ActiveRecord::Migration[7.0]
  def change
    add_column :rooms, :analytics_data, :jsonb
    add_column :rooms, :analytics_session_id, :string
  end
end
