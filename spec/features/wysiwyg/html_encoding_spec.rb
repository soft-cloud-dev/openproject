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

RSpec.describe "Wysiwyg escaping HTML entities (Regression #28906)", :js do
  let(:user) { create(:admin) }
  let(:project) { create(:project, enabled_module_names: %w[wiki]) }
  let(:editor) { Components::WysiwygEditor.new }

  before do
    login_as(user)
    visit project_wiki_path(project, :wiki)
  end

  it "shows the list correctly" do
    editor.in_editor do |_, editable|
      editor.click_and_type_slowly '<node foo="bar" />',
                                   :enter,
                                   '\<u>foo\</u>'

      expect(editable).to have_no_css("node")
      expect(editable).to have_no_css("u")
    end

    # Save wiki page
    click_on "Save"

    expect_flash(message: "Successful creation.")

    within("#content") do
      expect(page).to have_css("p", text: '<node foo="bar" />')
      expect(page).to have_no_css("u")
      expect(page).to have_no_css("node")
    end

    text = WikiPage.last.text
    expect(text).to include "&lt;node foo=&quot;bar&quot; /&gt;"
    expect(text).to include "\\\\&lt;u&gt;foo\\\\&lt;/u&gt;"
    expect(text).not_to include "<node>"
    expect(text).not_to include "<u>"
  end
end
