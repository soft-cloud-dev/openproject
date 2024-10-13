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
  class NextcloudManagedFolderSyncService < BaseService
    using Peripherals::ServiceResultRefinements

    FILE_PERMISSIONS = OpenProject::Storages::Engine.external_file_permissions

    include Injector["nextcloud.commands.create_folder",
                     "nextcloud.commands.rename_file",
                     "nextcloud.commands.set_permissions",
                     "nextcloud.queries.group_users",
                     "nextcloud.queries.file_path_to_id_map",
                     "nextcloud.authentication.userless",
                     "nextcloud.commands.add_user_to_group",
                     "nextcloud.commands.remove_user_from_group"]

    def self.i18n_key = "NextcloudSyncService"

    def self.call(storage)
      if storage.is_a? NextcloudStorage
        new(storage).call
      else
        raise ArgumentError, "Expected Storages::NextcloudStorage but got #{storage.class}"
      end
    end

    def initialize(storage, **deps)
      super(**deps)
      @storage = storage
    end

    def call
      with_tagged_logger([self.class.name, "storage-#{@storage.id}"]) do
        info "Starting AMPF Sync for Nextcloud Storage #{@storage.id}"
        prepare_remote_folders.on_failure { return epilogue }
        apply_permissions_to_folders
        epilogue
      end
    end

    private

    def epilogue
      info "Synchronization process for Nextcloud Storage #{@storage.id} has ended. #{@result.errors.count} errors found."
      @result
    end

    # @return [ServiceResult]
    def prepare_remote_folders
      info "Preparing the remote group folder #{@storage.group_folder}"

      remote_folders = remote_root_folder_map(@storage.group_folder).on_failure { return _1 }.result
      info "Found #{remote_folders.count} remote folders"

      ensure_root_folder_permissions(remote_folders["/#{@storage.group_folder}"].id).on_failure { return _1 }

      ensure_folders_exist(remote_folders).on_success { hide_inactive_folders(remote_folders) }
    end

    def apply_permissions_to_folders
      info "Setting permissions to project folders"
      remote_admins = admin_remote_identities_scope.pluck(:origin_user_id)

      active_project_storages_scope.where.not(project_folder_id: nil).find_each do |project_storage|
        set_folder_permissions(remote_admins, project_storage)
      end

      info "Updating user access on automatically managed project folders"
      add_remove_users_to_group(@storage.group, @storage.username)

      ServiceResult.success
    end

    def add_remove_users_to_group(group, username)
      remote_users = remote_group_users.result_or do |error|
        log_storage_error(error, group:)
        return add_error(:remote_group_users, error, options: { group: }).fail!
      end

      local_users = remote_identities_scope.order(:id).pluck(:origin_user_id)

      remove_users_from_remote_group(remote_users - local_users - [username])
      add_users_to_remote_group(local_users - remote_users - [username])
    end

    def add_users_to_remote_group(users_to_add)
      group = @storage.group

      users_to_add.each do |user|
        add_user_to_group.call(storage: @storage, auth_strategy:, user:, group:).error_and do |error|
          add_error(:add_user_to_group, error, options: { user:, group:, reason: error.log_message })
          log_storage_error(error, group:, user:, reason: error.log_message)
        end
      end
    end

    def remove_users_from_remote_group(users_to_remove)
      group = @storage.group

      users_to_remove.each do |user|
        remove_user_from_group.call(storage: @storage, auth_strategy:, user:, group:).error_and do |error|
          add_error(:remove_user_from_group, error, options: { user:, group:, reason: error.log_message })
          log_storage_error(error, group:, user:, reason: error.log_message)
        end
      end
    end

    # rubocop:disable Metrics/AbcSize
    def set_folder_permissions(remote_admins, project_storage)
      system_user = [{ user_id: @storage.username, permissions: FILE_PERMISSIONS }]

      admin_permissions = remote_admins.to_set.map { |username| { user_id: username, permissions: FILE_PERMISSIONS } }

      users_permissions = project_remote_identities(project_storage).map do |identity|
        permissions = identity.user.all_permissions_for(project_storage.project) & FILE_PERMISSIONS
        { user_id: identity.origin_user_id, permissions: }
      end

      group_permissions = [{ group_id: @storage.group, permissions: [] }]

      permissions = system_user + admin_permissions + users_permissions + group_permissions
      project_folder_id = project_storage.project_folder_id

      input_data = build_set_permissions_input_data(project_folder_id, permissions).value_or do |failure|
        log_validation_error(failure, project_folder_id:, permissions:)
        return # rubocop:disable Lint/NonLocalExitFromIterator
      end

      set_permissions.call(storage: @storage, auth_strategy:, input_data:).on_failure do |service_result|
        log_storage_error(service_result.errors, folder: project_folder_id)
        add_error(:set_folder_permission, service_result.errors, options: { folder: project_folder_id })
      end
    end

    # rubocop:enable Metrics/AbcSize

    def project_remote_identities(project_storage)
      remote_identities = remote_identities_scope.where.not(id: admin_remote_identities_scope).order(:id)

      if project_storage.project.public? && ProjectRole.non_member.permissions.intersect?(FILE_PERMISSIONS)
        remote_identities
      else
        remote_identities.where(user: project_storage.project.users)
      end
    end

    # rubocop:disable Metrics/AbcSize
    def hide_inactive_folders(remote_folders)
      info "Hiding folders related to inactive projects"
      project_folder_ids = active_project_storages_scope.pluck(:project_folder_id).compact

      remote_folders.except("/#{@storage.group_folder}").each do |(path, file)|
        folder_id = file.id

        next if project_folder_ids.include?(folder_id)

        info "Hiding folder #{folder_id} (#{path}) as it does not belong to any active project"
        permissions = [
          { user_id: @storage.username, permissions: FILE_PERMISSIONS },
          { group_id: @storage.group, permissions: [] }
        ]

        input_data = build_set_permissions_input_data(folder_id, permissions).value_or do |failure|
          log_validation_error(failure, folder_id:, permissions:)
          return # rubocop:disable Lint/NonLocalExitFromIterator
        end

        set_permissions.call(storage: @storage, auth_strategy:, input_data:).on_failure do |service_result|
          log_storage_error(service_result.errors, folder_id:, context: "hide_folder")
          add_error(:hide_inactive_folders, service_result.errors, options: { folder_id: })
        end
      end
    end

    # rubocop:enable Metrics/AbcSize

    def ensure_folders_exist(remote_folders)
      info "Ensuring that automatically managed project folders exist and are correctly named."
      id_folder_map = remote_folders.to_h { |path, file| [file.id, path] }

      active_project_storages_scope.includes(:project).map do |project_storage|
        unless id_folder_map.key?(project_storage.project_folder_id)
          info "#{project_storage.managed_project_folder_path} does not exist. Creating..."
          next create_remote_folder(project_storage)
        end

        rename_folder(project_storage, id_folder_map[project_storage.project_folder_id])&.on_failure { return _1 }
      end

      # We processed every folder successfully
      ServiceResult.success
    end

    # @param project_storage [Storages::ProjectStorage] Storages::ProjectStorage that the remote folder might need renaming
    # @param current_path [String] current name of the remote project storage folder
    # @return [ServiceResult, nil]
    def rename_folder(project_storage, current_path)
      return if UrlBuilder.path(current_path) == UrlBuilder.path(project_storage.managed_project_folder_path)

      name = project_storage.managed_project_folder_name
      file_id = project_storage.project_folder_id

      info "#{current_path} is misnamed. Renaming to #{name}"
      rename_file.call(storage: @storage, auth_strategy:, file_id:, name:).on_failure do |service_result|
        log_storage_error(service_result.errors, folder_id: file_id, folder_name: name)

        add_error(:rename_project_folder, service_result.errors,
                  options: { current_path:, project_folder_name: name, project_folder_id: file_id }).fail!
      end
    end

    def create_remote_folder(project_storage)
      folder_name = project_storage.managed_project_folder_path
      parent_location = Peripherals::ParentFolder.new("/")

      created_folder = create_folder.call(storage: @storage, auth_strategy:, folder_name:, parent_location:)
                                    .on_failure do |service_result|
        log_storage_error(service_result.errors, folder_name:)

        return add_error(:create_folder, service_result.errors, options: { folder_name:, parent_location: })
      end.result

      last_project_folder = LastProjectFolder.find_or_initialize_by(
        project_storage_id: project_storage.id, mode: project_storage.project_folder_mode
      )

      audit_last_project_folder(last_project_folder, created_folder.id)
    end

    def audit_last_project_folder(last_project_folder, project_folder_id)
      ApplicationRecord.transaction do
        success = last_project_folder.update(origin_folder_id: project_folder_id) &&
          last_project_folder.project_storage.update(project_folder_id:)

        raise ActiveRecord::Rollback unless success
      end
    end

    # rubocop:disable Metrics/AbcSize
    # @param root_folder_id [String] the id of the root folder
    # @return [ServiceResult]
    def ensure_root_folder_permissions(root_folder_id)
      username = @storage.username
      group = @storage.group
      info "Setting needed permissions for user #{username} and group #{group} on the root group folder."
      permissions = [
        { user_id: username, permissions: FILE_PERMISSIONS },
        { group_id: group, permissions: [:read_files] }
      ]

      input_data = build_set_permissions_input_data(root_folder_id, permissions).value_or do |failure|
        log_validation_error(failure, root_folder_id:, permissions:)
        return ServiceResult.failure(result: failure.errors.to_h) # rubocop:disable Rails/DeprecatedActiveModelErrorsMethods
      end

      set_permissions.call(storage: @storage, auth_strategy:, input_data:).on_failure do |service_result|
        log_storage_error(service_result.errors, folder: "root", root_folder_id:)
        add_error(:ensure_root_folder_permissions, service_result.errors, options: { group:, username: }).fail!
      end
    end

    # rubocop:enable Metrics/AbcSize

    def remote_root_folder_map(group_folder)
      info "Retrieving already existing folders under #{group_folder}"
      file_path_to_id_map.call(storage: @storage,
                               auth_strategy:,
                               folder: Peripherals::ParentFolder.new(group_folder),
                               depth: 1)
                         .on_failure do |service_result|
        log_storage_error(service_result.errors, { folder: group_folder })
        add_error(:remote_folders, service_result.errors, options: { group_folder:, username: @storage.username }).fail!
      end
    end

    def build_set_permissions_input_data(file_id, user_permissions)
      Peripherals::StorageInteraction::Inputs::SetPermissions.build(file_id:, user_permissions:)
    end

    def remote_group_users
      info "Retrieving users that a part of the #{@storage.group} group"
      group_users.call(storage: @storage, auth_strategy:, group: @storage.group)
    end

    ### Model Scopes

    def active_project_storages_scope
      @storage.project_storages.active.automatic
    end

    def remote_identities_scope
      RemoteIdentity.includes(:user).where(oauth_client: @storage.oauth_client)
    end

    def auth_strategy
      @auth_strategy ||= userless.call
    end

    def admin_remote_identities_scope
      RemoteIdentity.includes(:user).where(oauth_client: @storage.oauth_client, user: User.admin.active)
    end
  end
end
