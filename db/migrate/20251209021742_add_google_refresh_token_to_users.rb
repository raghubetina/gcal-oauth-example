class AddGoogleRefreshTokenToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :google_refresh_token, :string
  end
end
