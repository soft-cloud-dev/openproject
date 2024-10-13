# frozen_string_literal: true

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

module Storages
  class FileLinkSyncService < BaseService
    using Peripherals::ServiceResultRefinements

    def initialize(user:)
      super()
      @user = user
    end

    def call(file_links)
      with_tagged_logger do
        info "Starting File Link remote synchronization"

        resulting_file_links = file_links
                               .group_by(&:storage_id)
                               .map { |storage_id, storage_file_links| sync_storage_data(storage_id, storage_file_links) }
                               .reduce([]) do |state, sync_result|
          sync_result.match(
            on_success: ->(sr) { state + sr },
            on_failure: ->(_) { state }
          )
        end

        @result.result = resulting_file_links
        info "File Link Synchronization successful"
        @result
      end
    end

    private

    def sync_storage_data(storage_id, file_links)
      storage = Storage.find(storage_id)

      info "Retrieving file link information from #{storage.name}"
      Peripherals::Registry
        .resolve("#{storage}.queries.files_info")
        .call(storage:, auth_strategy: strategy(storage), file_ids: file_links.map(&:origin_id))
        .map { |file_infos| to_hash(file_infos) }
        .match(
          on_success: set_file_link_status(file_links),
          on_failure: lambda { |_|
            ServiceResult.success(result: file_links.map do |file_link|
              file_link.origin_status = :error
              file_link
            end)
          }
        )
    end

    def strategy(storage)
      Peripherals::Registry.resolve("#{storage}.authentication.user_bound").call(user: @user)
    end

    def to_hash(file_infos)
      file_infos.index_by { |file_info| file_info.id.to_s }.to_h
    end

    def set_file_link_status(file_links)
      info "Updating file link status..."
      lambda do |file_infos|
        resulting_file_links = []

        file_links.each do |file_link|
          file_info = file_infos[file_link.origin_id]

          file_link.origin_status = case file_info.status_code
                                    when 200
                                      update_file_link(file_link, file_info)
                                      :view_allowed
                                    when 403
                                      :view_not_allowed
                                    when 404
                                      :not_found
                                    else
                                      :error
                                    end

          resulting_file_links << file_link
          file_link.save
        end

        ServiceResult.success(result: resulting_file_links)
      end
    end

    def update_file_link(file_link, file_info)
      file_link.origin_mime_type = file_info.mime_type
      file_link.origin_created_by_name = file_info.owner_name
      file_link.origin_last_modified_by_name = file_info.last_modified_by_name
      file_link.origin_name = file_info.name
      file_link.origin_created_at = file_info.created_at
      file_link.origin_updated_at = file_info.last_modified_at

      file_link
    end
  end
end
