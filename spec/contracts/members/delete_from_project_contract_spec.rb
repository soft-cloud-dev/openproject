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
require "contracts/shared/model_contract_shared_context"

RSpec.describe Members::DeleteFromProjectContract do
  include_context "ModelContract shared context"

  let(:contract) { described_class.new(member, current_user) }
  let(:member) { build_stubbed(:member, project:, roles:, principal:) }
  let(:project) { build_stubbed(:project) }
  let(:roles) { [build_stubbed(:project_role)] }
  let(:principal) { build_stubbed(:user) }

  context "when member is deletable" do
    it_behaves_like "contract is valid for active admins and invalid for regular users"

    include_examples "contract reuses the model errors" do
      let(:current_user) { build_stubbed(:user) }
    end

    context "when user has permission" do
      let(:current_user) { build_stubbed(:user) }

      before do
        mock_permissions_for(current_user) do |mock|
          mock.allow_in_project(:manage_members, project:)
        end
      end

      it_behaves_like "contract is valid"
    end
  end

  context "when member is not deletable" do
    before do
      allow(member).to receive(:some_roles_deletable?).and_return(false)
    end

    context "for admin" do
      let(:current_user) { build_stubbed(:admin) }

      it_behaves_like "contract is invalid"
    end

    context "when user has permission" do
      let(:current_user) { build_stubbed(:user) }

      before do
        mock_permissions_for(current_user) do |mock|
          mock.allow_in_project(:manage_members, project:)
        end
      end

      it_behaves_like "contract is invalid"
    end
  end
end
