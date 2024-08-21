#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See COPYRIGHT and LICENSE files for more details.
#++

require "spec_helper"

# Scenarios specified in https://community.openproject.org/wp/40749
RSpec.describe WorkPackages::SetAttributesService::DeriveProgressValuesWorkBased,
               type: :model,
               with_settings: { work_package_done_ratio: "field" } do
  let(:user) { build_stubbed(:user) }
  let(:project) { build_stubbed(:project) }
  let(:work_package) { build_stubbed(:work_package, project:) }
  let(:instance) { described_class.new(work_package) }

  shared_examples_for "update progress values" do |description:|
    subject do
      allow(work_package)
        .to receive(:save)

      instance.call
    end

    it description do
      work_package.attributes = set_attributes
      all_expected_attributes = {}
      all_expected_attributes.merge!(expected_derived_attributes) if defined?(expected_derived_attributes)
      if defined?(expected_kept_attributes)
        kept = work_package.attributes.slice(*expected_kept_attributes)
        if kept.size != expected_kept_attributes.size
          raise ArgumentError, "expected_kept_attributes contains attributes that are not present in the work_package: " \
                               "#{expected_kept_attributes - kept.keys} not present in #{work_package.attributes}"
        end
        all_expected_attributes.merge!(kept)
      end
      next if all_expected_attributes.blank?

      subject

      aggregate_failures do
        expect(work_package).to have_attributes(all_expected_attributes)
        expect(work_package).to have_attributes(set_attributes.except(*all_expected_attributes.keys))
        # work package is not saved and no errors are created
        expect(work_package).not_to have_received(:save)
        expect(work_package.errors).to be_empty
      end
    end
  end

  context "given a work package with work, remaining work, and % complete being set" do
    before do
      work_package.estimated_hours = 10.0
      work_package.remaining_hours = 3.0
      work_package.done_ratio = 70
      work_package.clear_changes_information
    end

    context "when work is unset" do
      let(:set_attributes) { { estimated_hours: nil } }
      let(:expected_derived_attributes) { { remaining_hours: nil } }
      let(:expected_kept_attributes) { %w[done_ratio] }

      include_examples "update progress values", description: "keeps % complete, and unsets remaining work"
    end

    context "when remaining work is unset" do
      let(:set_attributes) { { remaining_hours: nil } }
      let(:expected_derived_attributes) { { done_ratio: nil } }
      let(:expected_kept_attributes) { %w[estimated_hours] }

      include_examples "update progress values", description: "keeps work, and unsets % complete"
    end

    context "when % complete is unset" do
      let(:set_attributes) { { done_ratio: nil } }
      let(:expected_derived_attributes) { { remaining_hours: nil } }
      let(:expected_kept_attributes) { %w[estimated_hours] }

      include_examples "update progress values", description: "keeps work, and unsets remaining work"
    end

    context "when both work and remaining work are unset" do
      let(:set_attributes) { { estimated_hours: nil, remaining_hours: nil } }
      let(:expected_kept_attributes) { %w[done_ratio] }

      include_examples "update progress values", description: "keeps % complete"
    end

    context "when both work and percent complete are unset" do
      let(:set_attributes) { { estimated_hours: nil, done_ratio: nil } }
      let(:expected_kept_attributes) { %w[remaining_hours] }

      include_examples "update progress values", description: "keeps remaining work"
    end

    context "when both remaining work and percent complete are unset" do
      let(:set_attributes) { { remaining_hours: nil, done_ratio: nil } }
      let(:expected_kept_attributes) { %w[estimated_hours] }

      include_examples "update progress values", description: "keeps work"
    end

    context "when work is increased" do
      # work changed by +10h
      let(:set_attributes) { { estimated_hours: 10.0 + 10.0 } }
      let(:expected_derived_attributes) do
        { remaining_hours: 3.0 + 10.0, done_ratio: 35 }
      end

      include_examples "update progress values",
                       description: "remaining work is increased by the same amount, and % complete is updated accordingly"
    end

    context "when work is set to 0h" do
      let(:set_attributes) { { estimated_hours: 0 } }
      let(:expected_derived_attributes) do
        { remaining_hours: 0, done_ratio: nil }
      end

      include_examples "update progress values",
                       description: "remaining work is set to 0h and % Complete is unset"
    end

    context "when work is decreased" do
      # work changed by -2h
      let(:set_attributes) { { estimated_hours: 10.0 - 2.0 } }
      let(:expected_derived_attributes) do
        { remaining_hours: 3.0 - 2.0, done_ratio: 88 }
      end

      include_examples "update progress values",
                       description: "remaining work is decreased by the same amount, and % complete is updated accordingly"
    end

    context "when work is decreased below remaining work value" do
      # work changed by -8h
      let(:set_attributes) { { estimated_hours: 10.0 - 8.0 } }
      let(:expected_derived_attributes) do
        { remaining_hours: 0, done_ratio: 100 }
      end

      include_examples "update progress values",
                       description: "remaining work becomes 0h, and % complete becomes 100%"
    end

    context "when work is changed to a negative value" do
      let(:set_attributes) { { estimated_hours: -1.0 } }
      let(:expected_kept_attributes) { %w[remaining_hours done_ratio] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), " \
                                    "and % complete and remaining work are kept"
    end

    context "when remaining work is changed" do
      let(:set_attributes) { { remaining_hours: 2 } }
      let(:expected_derived_attributes) { { done_ratio: 80 } }
      let(:expected_kept_attributes) { %w[estimated_hours] }

      include_examples "update progress values", description: "updates % complete accordingly"
    end

    context "when remaining work and % complete are both changed" do
      let(:set_attributes) { { remaining_hours: 12.0, done_ratio: 40 } }
      let(:expected_derived_attributes) { { estimated_hours: 20.0 } }

      include_examples "update progress values", description: "work is updated accordingly"
    end

    context "when work and remaining work are both changed to negative values" do
      let(:set_attributes) { { estimated_hours: -10, remaining_hours: -5 } }
      let(:expected_kept_attributes) { %w[done_ratio] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), and % Complete is kept"
    end

    context "when work and remaining work are both changed to values with more than 2 decimals" do
      let(:set_attributes) { { estimated_hours: 10.123456, remaining_hours: 5.6789 } }
      let(:expected_derived_attributes) { { estimated_hours: 10.12, remaining_hours: 5.68, done_ratio: 44 } }

      include_examples "update progress values", description: "rounds work and remaining work to 2 decimals " \
                                                              "and updates % complete accordingly"
    end

    context "when remaining work is changed to a value greater than work" do
      let(:set_attributes) { { remaining_hours: 200.0 } }
      let(:expected_kept_attributes) { %w[done_ratio] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), and % Complete is kept"
    end

    context "when remaining work is changed to a negative value" do
      let(:set_attributes) { { remaining_hours: -1.0 } }
      let(:expected_kept_attributes) { %w[done_ratio] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), and % Complete is kept"
    end

    context "when both work and remaining work are changed" do
      let(:set_attributes) { { estimated_hours: 20, remaining_hours: 2 } }
      let(:expected_derived_attributes) { { done_ratio: 90 } }

      include_examples "update progress values", description: "updates % complete accordingly"
    end

    context "when work is changed and remaining work is unset" do
      let(:set_attributes) { { estimated_hours: 8.0, remaining_hours: nil } }
      let(:expected_derived_attributes) { { done_ratio: nil } }

      include_examples "update progress values", description: "% complete is unset"
    end

    context "when percent complete is changed and work is unset" do
      let(:set_attributes) { { done_ratio: 40, estimated_hours: nil } }
      let(:expected_derived_attributes) { { remaining_hours: nil } }

      include_examples "update progress values", description: "remaining work is unset"
    end

    context "when percent complete is changed and remaining work is unset" do
      let(:set_attributes) { { done_ratio: 40, remaining_hours: nil } }
      let(:expected_derived_attributes) { { estimated_hours: nil } }

      include_examples "update progress values", description: "work is unset"
    end

    context "when % complete is changed and remaining work is set to same value" do
      let(:set_attributes) { { done_ratio: 90, remaining_hours: 3 } }
      let(:expected_derived_attributes) { { estimated_hours: 30 } }

      include_examples "update progress values", description: "work is updated accordingly"
    end

    context "when work is set to the same value and remaining work is changed" do
      let(:set_attributes) { { estimated_hours: 10.0, remaining_hours: 1.0 } }
      let(:expected_derived_attributes) { { done_ratio: 90 } }

      include_examples "update progress values",
                       description: "% complete is updated accordingly"
    end

    context "when work is increased and remaining work is set to its current value (to prevent it from being increased)" do
      # work changed by +10h
      let(:set_attributes) { { estimated_hours: 10.0 + 10.0, remaining_hours: 3 } }
      let(:expected_derived_attributes) { { remaining_hours: 3.0, done_ratio: 85 } }

      include_examples "update progress values",
                       description: "remaining work is kept (not increased), and % complete is updated accordingly"
    end

    context "when % complete is changed" do
      let(:set_attributes) { { done_ratio: 40 } }
      let(:expected_derived_attributes) { { remaining_hours: 6.0 } }
      let(:expected_kept_attributes) { %w[estimated_hours] }

      include_examples "update progress values", description: "work is kept, and remaining work is updated accordingly"
    end

    context "when % complete is changed to a negative value" do
      let(:set_attributes) { { done_ratio: -1.0 } }
      let(:expected_kept_attributes) { %w[estimated_hours remaining_hours] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), and work and remaining work are kept"
    end

    context "when % complete is more than 100%" do
      let(:set_attributes) { { done_ratio: 101 } }
      let(:expected_kept_attributes) { %w[estimated_hours remaining_hours] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), and work and remaining work are kept"
    end

    context "when work, remaining work, and % complete are all changed to consistent values" do
      let(:set_attributes) { { estimated_hours: 20, remaining_hours: 12.0, done_ratio: 40 } }
      let(:expected_kept_attributes) { %w[estimated_hours remaining_hours done_ratio] }

      include_examples "update progress values", description: "they are all kept"
    end

    context "when work, remaining work, and % complete are all changed to inconsistent values" do
      let(:set_attributes) { { estimated_hours: 5, remaining_hours: -3.0, done_ratio: 42 } }
      let(:expected_kept_attributes) { %w[estimated_hours remaining_hours done_ratio] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), and all values are kept"
    end
  end

  context "given a work package with work and % complete being set, and remaining work being unset" do
    before do
      work_package.estimated_hours = 10
      work_package.remaining_hours = nil
      work_package.done_ratio = 30
      work_package.clear_changes_information
    end

    context "when work is changed" do
      let(:set_attributes) { { estimated_hours: 20.0 } }
      let(:expected_derived_attributes) { { remaining_hours: 14.0 } }
      let(:expected_kept_attributes) { %w[done_ratio] }

      include_examples "update progress values", description: "% complete is kept and remaining work is updated accordingly"
    end

    context "when work is changed to a negative value" do
      let(:set_attributes) { { estimated_hours: -1.0 } }
      let(:expected_kept_attributes) { %w[remaining_hours done_ratio] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), " \
                                    "and % complete and remaining work are kept"
    end

    context "when remaining work is set" do
      let(:set_attributes) { { remaining_hours: 1.0 } }
      let(:expected_derived_attributes) { { done_ratio: 90.0 } }
      let(:expected_kept_attributes) { %w[estimated_hours] }

      include_examples "update progress values", description: "work is kept and % complete is updated accordingly"
    end

    context "when % complete is set" do
      let(:set_attributes) { { done_ratio: 90 } }
      let(:expected_derived_attributes) { { remaining_hours: 1.0 } }
      let(:expected_kept_attributes) { %w[estimated_hours] }

      include_examples "update progress values", description: "work is kept and remaining work is updated accordingly"
    end
  end

  context "given a work package with remaining work and % complete being set, and work being unset" do
    before do
      work_package.estimated_hours = nil
      work_package.remaining_hours = 2.0
      work_package.done_ratio = 50
      work_package.clear_changes_information
    end

    context "when remaining work is changed" do
      let(:set_attributes) { { remaining_hours: 10.0 } }
      let(:expected_derived_attributes) { { estimated_hours: 20.0 } }
      let(:expected_kept_attributes) { %w[done_ratio] }

      include_examples "update progress values", description: "% complete is kept and work is updated accordingly"
    end

    context "when % complete is 0% and remaining work is changed to a decimal rounded up" do
      let(:set_attributes) { { remaining_hours: 5.679 } }
      let(:expected_derived_attributes) { { estimated_hours: 5.68, remaining_hours: 5.68 } }
      let(:expected_kept_attributes) { %w[done_ratio] }

      before do
        work_package.done_ratio = 0
        work_package.clear_changes_information
      end

      include_examples "update progress values",
                       description: "% complete is kept, values are rounded, and work is updated accordingly"
    end

    context "when work is set" do
      let(:set_attributes) { { estimated_hours: 10.0 } }
      let(:expected_derived_attributes) { { done_ratio: 80.0 } }
      let(:expected_kept_attributes) { %w[remaining_hours] }

      include_examples "update progress values", description: "remaining work is kept and % complete is updated accordingly"
    end

    context "when % complete is changed" do
      let(:set_attributes) { { done_ratio: 80 } }
      let(:expected_derived_attributes) { { estimated_hours: 10.0 } }
      let(:expected_kept_attributes) { %w[remaining_hours] }

      include_examples "update progress values", description: "remaining work is kept and work is updated accordingly"
    end
  end

  context "given a work package with work being set, and remaining work and % complete being unset" do
    before do
      work_package.estimated_hours = 10
      work_package.remaining_hours = nil
      work_package.done_ratio = nil
      work_package.clear_changes_information
    end

    context "when work is changed" do
      let(:set_attributes) { { estimated_hours: 20.0 } }
      let(:expected_derived_attributes) { { remaining_hours: 20.0, done_ratio: 0 } }

      include_examples "update progress values",
                       description: "remaining work is set to the same value and % complete is set to 0%"
    end

    context "when work is changed and remaining work is unset" do
      let(:set_attributes) { { estimated_hours: 10.0, remaining_hours: nil } }
      let(:expected_kept_attributes) { %w[done_ratio] }

      include_examples "update progress values",
                       description: "% complete is kept and remaining work is kept unset and not recomputed" \
                                    "(error state to be detected by contract)"
    end

    context "when work is changed to a negative value" do
      let(:set_attributes) { { estimated_hours: -1.0 } }
      let(:expected_kept_attributes) { %w[remaining_hours done_ratio] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), " \
                                    "and % complete and remaining work are kept"
    end

    context "when % complete is set" do
      let(:set_attributes) { { done_ratio: 100 } }
      let(:expected_derived_attributes) { { remaining_hours: 0.0 } }
      let(:expected_kept_attributes) { %w[estimated_hours] }

      include_examples "update progress values",
                       description: "work is kept and remaining work is updated accordingly"
    end
  end

  context "given a work package with remaining work being set, and work and % complete being unset" do
    before do
      work_package.estimated_hours = nil
      work_package.remaining_hours = 6.0
      work_package.done_ratio = nil
      work_package.clear_changes_information
    end

    context "when work is set" do
      let(:set_attributes) { { estimated_hours: 10.0 } }
      let(:expected_derived_attributes) { { done_ratio: 40 } }
      let(:expected_kept_attributes) { %w[remaining_hours] }

      include_examples "update progress values",
                       description: "remaining work is kept to the same value and % complete is updated accordingly"
    end

    context "when work is changed to a negative value" do
      let(:set_attributes) { { estimated_hours: -1.0 } }
      let(:expected_kept_attributes) { %w[remaining_hours done_ratio] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), " \
                                    "and % complete and remaining work are kept"
    end

    context "when remaining work is changed" do
      let(:set_attributes) { { remaining_hours: 12.0 } }
      let(:expected_derived_attributes) { { estimated_hours: 12.0, done_ratio: 0 } }

      include_examples "update progress values",
                       description: "work is set to the same value and % complete is set to 0%"
    end

    context "when remaining work is changed to a negative value" do
      let(:set_attributes) { { remaining_hours: -1.0 } }
      let(:expected_kept_attributes) { %w[estimated_hours done_ratio] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), " \
                                    "and % complete and work are kept"
    end

    context "when % complete is set" do
      let(:set_attributes) { { done_ratio: 40 } }
      let(:expected_derived_attributes) { { estimated_hours: 10.0 } }
      let(:expected_kept_attributes) { %w[remaining_hours] }

      include_examples "update progress values", description: "work is updated accordingly"
    end
  end

  context "given a work package with work and remaining work set to 0h, and % complete being unset" do
    before do
      work_package.estimated_hours = 0
      work_package.remaining_hours = 0
      work_package.done_ratio = nil
      work_package.clear_changes_information
    end

    context "when work is set" do
      let(:set_attributes) { { estimated_hours: 5.0 } }
      let(:expected_derived_attributes) { { remaining_hours: 5.0, done_ratio: 0 } }

      include_examples "update progress values",
                       description: "remaining work is set to same value as work, and % complete is set to 0%"
    end
  end

  context "given a work package with work and remaining work unset, and % complete being set" do
    before do
      work_package.estimated_hours = nil
      work_package.remaining_hours = nil
      work_package.done_ratio = 60
      work_package.clear_changes_information
    end

    context "when work is set" do
      let(:set_attributes) { { estimated_hours: 10.0 } }
      let(:expected_derived_attributes) { { remaining_hours: 4.0 } }
      let(:expected_kept_attributes) { %w[done_ratio] }

      include_examples "update progress values", description: "% complete is kept and remaining work is updated accordingly"
    end

    context "when work is set to a number with with 4 decimals" do
      let(:set_attributes) { { estimated_hours: 2.5678 } }
      let(:expected_derived_attributes) { { estimated_hours: 2.57, remaining_hours: 1.03 } }
      let(:expected_kept_attributes) { %w[done_ratio] }

      include_examples "update progress values",
                       description: "% complete is kept, work is rounded to 2 decimals, " \
                                    "and remaining work is updated and rounded to 2 decimals"
    end

    context "when work is set to a string" do
      let(:set_attributes) { { estimated_hours: "I am a string" } }
      let(:expected_derived_attributes) { { estimated_hours: 0.0, remaining_hours: 0.0 } }

      it "keeps the original string value in the _before_type_cast method " \
         "so that validation can detect it is invalid" do
        work_package.attributes = set_attributes
        instance.call

        expect(work_package.estimated_hours_before_type_cast).to eq("I am a string")
      end
    end

    context "when work and remaining work are set" do
      let(:set_attributes) { { estimated_hours: 10.0, remaining_hours: 0 } }
      let(:expected_derived_attributes) { { done_ratio: 100 } }

      include_examples "update progress values", description: "% complete is updated accordingly"
    end

    context "when work is set and remaining work is unset" do
      let(:set_attributes) { { estimated_hours: 10.0, remaining_hours: nil } }
      let(:expected_derived_attributes) { { done_ratio: nil } }

      include_examples "update progress values", description: "% complete is unset"
    end

    context "when work and remaining work are both set to negative values" do
      let(:set_attributes) { { estimated_hours: -10, remaining_hours: -5 } }
      let(:expected_kept_attributes) { %w[done_ratio] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), and % complete is kept"
    end

    context "when % complete is changed" do
      let(:set_attributes) { { done_ratio: 80 } }
      let(:expected_kept_attributes) { %w[estimated_hours remaining_hours] }

      include_examples "update progress values",
                       description: "work and remaining work are kept unset"
    end
  end

  context "given a work package with work, remaining work, and % complete being unset" do
    before do
      work_package.estimated_hours = nil
      work_package.remaining_hours = nil
      work_package.done_ratio = nil
      work_package.clear_changes_information
    end

    context "when work is set" do
      let(:set_attributes) { { estimated_hours: 10.0 } }
      let(:expected_derived_attributes) do
        { remaining_hours: 10.0, done_ratio: 0 }
      end

      include_examples "update progress values",
                       description: "remaining work is set to the same value and % complete is set to 0%"
    end

    context "when work is set to a negative value" do
      let(:set_attributes) { { estimated_hours: -1.0 } }
      let(:expected_kept_attributes) { %w[remaining_hours done_ratio] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), " \
                                    "and % complete and remaining work are kept"
    end

    context "when remaining work is set" do
      let(:set_attributes) { { remaining_hours: 10.0 } }
      let(:expected_derived_attributes) { { estimated_hours: 10.0, done_ratio: 0 } }

      include_examples "update progress values", description: "work is set to the same value and % complete is set to 0%"
    end

    context "when remaining work is set to a negative value" do
      let(:set_attributes) { { remaining_hours: -1.0 } }
      let(:expected_kept_attributes) { %w[estimated_hours done_ratio] }

      include_examples "update progress values",
                       description: "is an error state (to be detected by contract), " \
                                    "and % complete and work are kept"
    end

    context "when remaining work is set and work is unset" do
      let(:set_attributes) { { estimated_hours: nil, remaining_hours: 6.7 } }
      let(:expected_kept_attributes) { %w[done_ratio] }

      include_examples "update progress values",
                       description: "% complete is kept and work is kept unset and not recomputed" \
                                    "(error state to be detected by contract)"
    end

    context "when % complete is set" do
      let(:set_attributes) { { done_ratio: 80 } }
      let(:expected_kept_attributes) { %w[estimated_hours remaining_hours] }

      include_examples "update progress values",
                       description: "work and remaining work are kept unset"
    end
  end
end
