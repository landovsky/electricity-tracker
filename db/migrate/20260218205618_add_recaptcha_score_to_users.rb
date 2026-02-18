class AddRecaptchaScoreToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :recaptcha_score, :float
  end
end
