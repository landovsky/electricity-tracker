class AddLoginHardeningToUsers < ActiveRecord::Migration[8.1]
  def change
    # Number of verification attempts spent on the current SMS OTP code.
    add_column :users, :sms_otp_attempts, :integer, null: false, default: 0
    # Per-user secret embedded in magic-link tokens; cleared on use and on logout
    # so that a link works only once.
    add_column :users, :magic_link_nonce, :string
  end
end
