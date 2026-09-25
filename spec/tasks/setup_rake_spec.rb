# frozen_string_literal: true

require "rails_helper"
require "rake"

# bin/docker-entrypoint runs app:setup on EVERY container start (each deploy,
# pod restart or eviction), so it must only ever seed an empty database.
RSpec.describe "app:setup" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("app:setup")
  end

  before { allow($stdout).to receive(:puts) }

  def run_setup
    task = Rake::Task["app:setup"]
    task.reenable
    task.invoke
  end

  context "first boot on an empty database" do
    it "seeds exactly one visitor per family member, not a second one from the membership callback" do
      run_setup

      property = Property.sole
      expect(property.subdomain).to eq("sepot")
      expect(property.visitors.group(:name).count.values).to all(eq(1))
      expect(property.visitors.count).to eq(6)
    end

    it "points every seeded user at their own seeded visitor" do
      run_setup

      tereza = User.find_by!(email: "tereza.landovska@gmail.com")
      expect(tereza.default_visitor).to eq(Visitor.find_by!(name: "Tereza"))
      expect(tereza.properties).to eq([ Property.sole ])
    end
  end

  context "a later boot after admins edited the live data in the UI" do
    before { run_setup }

    let(:property) { Property.sole }
    let(:petr) { User.find_by!(email: "potuznik@volny.cz") }
    let(:kristina) { User.find_by!(email: "kristina.djakoualnova@seznam.cz") }
    let(:admin) { User.find_by!(email: "landovsky@gmail.com") }

    it "does not give back property access an admin revoked" do
      property.update!(user_ids: property.user_ids - [ petr.id ])

      run_setup

      expect(PropertyUser.where(property: property, user: petr)).not_to exist
      expect(property.visitors.where(name: "Petr").count).to eq(1)
    end

    it "does not re-create a renamed visitor or re-point the user at an empty duplicate" do
      Visitor.find_by!(name: "Kristina").update!(name: "Kristína")

      expect { run_setup }.not_to change(Visitor, :count)
      expect(kristina.reload.default_visitor.name).to eq("Kristína")
    end

    it "keeps the default visitor an admin chose instead of forcing the seeded mapping back" do
      chosen = Visitor.find_by!(name: "Jirka")
      petr.update!(default_visitor: chosen)

      run_setup

      expect(petr.reload.default_visitor).to eq(chosen)
    end

    it "does not duplicate a renamed property or re-create an admin whose email was changed" do
      property.update!(name: "Chalupa Suchá")
      admin.update!(email: "tomas@example.com")

      expect { run_setup }.not_to change { [ Property.count, Meter.count, User.count ] }
      expect(User.where(email: "landovsky@gmail.com")).not_to exist
    end
  end
end
