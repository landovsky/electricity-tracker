# frozen_string_literal: true

class MagicLinkMailer < ApplicationMailer
  def login_link(user:, token:)
    @user = user
    @login_url = auth_verify_url(token: token)

    mail(
      to: user.email,
      subject: t("mailer.login_link.subject")
    )
  end
end
