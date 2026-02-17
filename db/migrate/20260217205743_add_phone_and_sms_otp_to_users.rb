class AddPhoneAndSmsOtpToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :phone_number, :string
    add_column :users, :sms_otp_code, :string
    add_column :users, :sms_otp_sent_at, :datetime
    add_index :users, :phone_number, unique: true, where: "phone_number IS NOT NULL"

    # Allow phone-only users (no email)
    change_column_null :users, :email, true
    # Allow self-registered users to complete name during onboarding
    change_column_null :users, :name, true
  end
end
