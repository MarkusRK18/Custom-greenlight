# frozen_string_literal: true

class SetSriShakthiTheme < ActiveRecord::Migration[7.0]
  def up
    { 'PrimaryColor' => '#004d00', 'PrimaryColorLight' => '#e6ede6', 'PrimaryColorDark' => '#003d00' }.each do |name, color|
      execute <<~SQL
        UPDATE site_settings SET value = #{connection.quote(color)}
        FROM settings
        WHERE site_settings.setting_id = settings.id
          AND settings.name = #{connection.quote(name)}
          AND site_settings.provider = 'greenlight'
      SQL
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
