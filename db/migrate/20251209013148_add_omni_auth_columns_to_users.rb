class AddOmniAuthColumnsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :provider, :string
    add_column :users, :uid, :string
    add_column :users, :google_access_token, :string
  end
end
