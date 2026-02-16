FactoryBot.define do
  factory :property do
    name { FFaker::Lorem.words(2).map(&:capitalize).join(' ') }
    address { "#{FFaker::AddressUS.street_address}, #{FFaker::AddressUS.city}, #{FFaker::AddressUS.state_abbr} #{FFaker::AddressUS.zip_code}" }
  end
end
