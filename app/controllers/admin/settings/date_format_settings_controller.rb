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

module Admin::Settings
  class DateFormatSettingsController < ::Admin::SettingsController
    menu_item :date_format

    before_action :validate_start_of_week_and_first_week_of_year_combination, only: :update

    def update # rubocop:disable Lint/UselessMethodDefinition
      super
    end

    private

    def validate_start_of_week_and_first_week_of_year_combination
      start_of_week = settings_params[:start_of_week]
      start_of_year = settings_params[:first_week_of_year]

      if start_of_week.present? ^ start_of_year.present?
        flash[:error] = I18n.t(
          "settings.date_format.first_date_of_week_and_year_set",
          first_week_setting_name: I18n.t(:setting_first_week_of_year),
          day_of_week_setting_name: I18n.t(:setting_start_of_week)
        )
        redirect_to action: :show
      end
    end
  end
end
