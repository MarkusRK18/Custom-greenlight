# frozen_string_literal: true

class PromoteSietAccountsToAdministrators < ActiveRecord::Migration[7.1]
  def up
    execute <<~SQL
      UPDATE users
      SET role_id = roles.id, updated_at = CURRENT_TIMESTAMP
      FROM roles
      WHERE roles.name = 'Administrator'
        AND roles.provider = users.provider
        AND LOWER(SPLIT_PART(users.email, '@', 2)) = 'siet.ac.in'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Previous institutional roles cannot be reconstructed'
  end
end
