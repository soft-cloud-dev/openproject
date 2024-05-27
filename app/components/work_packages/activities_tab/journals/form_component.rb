#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2023 the OpenProject GmbH
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

module WorkPackages
  module ActivitiesTab
    module Journals
      class FormComponent < ApplicationComponent
        include ApplicationHelper
        include OpPrimer::ComponentHelpers

        def initialize(journal:, submit_path:, cancel_path: nil)
          super

          @journal = journal
          @submit_path = submit_path
          @cancel_path = cancel_path
          @method = journal.new_record? ? :post : :put
        end

        private

        attr_reader :journal, :submit_path, :cancel_path, :method

        def cancel_button
          if cancel_path
            render(Primer::Beta::Button.new(
                     scheme: :secondary,
                     size: :medium,
                     tag: :a,
                     href: cancel_path,
                     data: { "turbo-stream": true }
                   )) do
              t("button_cancel")
            end
          else
            render(Primer::Beta::Button.new(
                     scheme: :default,
                     size: :medium,
                     data: {
                       action: "click->work-packages--activities-tab--new#hideForm"
                     }
                   )) do
              I18n.t("button_cancel")
            end
          end
        end
      end
    end
  end
end
