# frozen_string_literal: true

class MagicLinkMailer < ApplicationMailer
  def login_link(user:, token:, origin_host: nil)
    @user = user
    @login_url = if origin_host
      auth_verify_url(token: token, host: origin_host)
    else
      auth_verify_url(token: token)
    end

    mail(
      to: user.email,
      subject: t("mailer.login_link.subject")
    )
  end
end
